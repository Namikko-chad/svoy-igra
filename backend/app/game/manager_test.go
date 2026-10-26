package game

import (
	"context"
	"encoding/json"
	"os"
	"testing"
	"time"

	"svoy-igra/app/packs"
)

func TestIdleGameIsDeleted(t *testing.T) {
	dir := t.TempDir()
	store, err := packs.NewStore(dir, "", 1<<20)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	m, err := NewManager(store, dir, 50*time.Millisecond, 5)
	if err != nil {
		t.Fatal(err)
	}
	m.sweepTicks = 1
	m.SetWire(nil)

	busy, _ := m.Create("", "1234", "http://x")
	idle, _ := m.Create("", "1234", "http://x")
	be, _ := m.ByPIN(*busy.Game.PIN)
	be.Attach(RoleScreen, "t") // someone is watching this one
	ie, _ := m.ByPIN(*idle.Game.PIN)

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { m.Run(ctx); close(done) }()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := m.ByPIN(*idle.Game.PIN); err != nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	cancel()
	<-done

	if _, err := m.ByPIN(*idle.Game.PIN); err == nil {
		t.Fatal("idle game not deleted")
	}
	if _, err := os.Stat(ie.path); !os.IsNotExist(err) {
		t.Fatal("idle game file left on disk")
	}
	if _, err := m.ByPIN(*busy.Game.PIN); err != nil {
		t.Fatal("a game with a socket was deleted")
	}
	if _, _, _, ok := m.Resolve(idle.Token); ok {
		t.Fatal("token of a deleted game still resolves")
	}
}

func TestFinalSurvivesRestart(t *testing.T) {
	dir := t.TempDir()
	store, err := packs.NewStore(dir, "", 1<<20)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	p, _ := store.Create("P")
	r, _ := store.CreateRound(p.ID, "Финал", "final")
	for _, name := range []string{"А", "Б"} {
		c, _ := store.CreateCategory(p.ID, r.ID, name)
		q := "вопрос " + name
		if _, err := store.CreateQuestion(p.ID, c.ID, packs.QuestionInput{Question: &q}); err != nil {
			t.Fatal(err)
		}
	}
	m, _ := NewManager(store, dir, time.Hour, 5)
	m.SetWire(nil)
	g, _ := m.Create("", "1234", "http://x")
	e, _ := m.ByPIN(*g.Game.PIN)
	a, _ := e.Join(RolePlayer, "Аня", "")
	b, _ := e.Join(RolePlayer, "Боря", "")
	must := func(role Role, pid, typ string, data any) {
		t.Helper()
		raw, _ := json.Marshal(data)
		if err := e.Command(role, pid, "", typ, raw); err != nil {
			t.Fatalf("%s: %v", typ, err)
		}
	}
	must(RoleAdmin, "", "load_pack", map[string]any{"packId": p.ID})
	must(RoleAdmin, "", "set_score", map[string]any{"playerId": a.PlayerID, "score": 100})
	must(RoleAdmin, "", "set_score", map[string]any{"playerId": b.PlayerID, "score": 200})
	must(RoleHost, "", "start_game", nil)
	v := e.View(RoleHost, "", false)
	if v.Phase != PhaseFinalThemes || *v.Final.RemoverID != a.PlayerID {
		t.Fatalf("final start: %s %v", v.Phase, v.Final.RemoverID)
	}
	must(RolePlayer, a.PlayerID, "final_remove_theme", map[string]any{"themeId": v.Final.Themes[0].ID})
	must(RolePlayer, b.PlayerID, "final_bet", map[string]any{"amount": 150})
	e.Save(true)

	e2, err := loadEngine(store, e.path)
	if err != nil {
		t.Fatal(err)
	}
	v2 := e2.View(RolePlayer, b.PlayerID, false)
	if v2.Phase != PhaseFinalBets || v2.Question == nil || v2.Question.CategoryName != "Б" || len(v2.Question.Blocks) != 0 {
		t.Fatalf("restored final: %s %+v", v2.Phase, v2.Question)
	}
	if bet := v2.Final.Participants[1].Bet; bet == nil || *bet != 150 {
		t.Fatalf("restored bet %v", bet)
	}
	if v2.Final.Participants[0].HasBet {
		t.Fatal("phantom bet after restore")
	}
}
