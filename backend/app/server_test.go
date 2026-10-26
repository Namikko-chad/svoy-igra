package app

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/coder/websocket"

	"svoy-igra/app/config"
)

// ---- harness ----

type harness struct {
	t    *testing.T
	srv  *httptest.Server
	stop func()
}

func newHarness(t *testing.T) *harness { return newHarnessAt(t, t.TempDir()) }

func newHarnessAt(t *testing.T, dir string) *harness {
	t.Helper()
	cfg := &config.Config{DataDir: dir, MaxUploadMB: 10, CORSOrigins: []string{"*"}, GameIdleMin: 60, MaxGames: 10}
	s, err := build(cfg)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	var wg sync.WaitGroup
	s.start(ctx, &wg)
	ts := httptest.NewServer(s.handler)
	var once sync.Once
	stop := func() {
		once.Do(func() {
			cancel()
			wg.Wait()
			ts.Close()
			s.store.Close()
		})
	}
	t.Cleanup(stop)
	return &harness{t: t, srv: ts, stop: stop}
}

func (h *harness) do(method, path, token string, body any, out any) int {
	h.t.Helper()
	var rd io.Reader
	ct := ""
	switch b := body.(type) {
	case nil:
	case *bytes.Buffer:
		rd = b
	case multipartBody:
		rd, ct = b.buf, b.ct
	default:
		raw, _ := json.Marshal(b)
		rd, ct = bytes.NewReader(raw), "application/json"
	}
	req, _ := http.NewRequest(method, h.srv.URL+path, rd)
	if ct != "" {
		req.Header.Set("Content-Type", ct)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		h.t.Fatal(err)
	}
	defer res.Body.Close()
	data, _ := io.ReadAll(res.Body)
	if out != nil {
		if p, ok := out.(*[]byte); ok {
			*p = data
		} else if err := json.Unmarshal(data, out); err != nil {
			h.t.Fatalf("%s %s: decode %q: %v", method, path, data, err)
		}
	}
	return res.StatusCode
}

type multipartBody struct {
	buf *bytes.Buffer
	ct  string
}

func multipartFile(name string, content []byte) multipartBody {
	buf := &bytes.Buffer{}
	mw := multipart.NewWriter(buf)
	w, _ := mw.CreateFormFile("file", name)
	_, _ = w.Write(content)
	_ = mw.Close()
	return multipartBody{buf, mw.FormDataContentType()}
}

type joined struct {
	Token    string
	Role     string
	PlayerID string
	Game     struct {
		PIN       string
		Link      string
		HostTaken bool
	}
}

func (h *harness) createGame(adminPin string) joined {
	h.t.Helper()
	var out joined
	if code := h.do("POST", "/api/games", "", map[string]string{"adminPin": adminPin, "title": "Тест"}, &out); code != 201 {
		h.t.Fatalf("create game: %d", code)
	}
	return out
}

func (h *harness) join(pin string, body map[string]string, want int) joined {
	h.t.Helper()
	var out joined
	if code := h.do("POST", "/api/games/"+pin+"/join", "", body, &out); code != want {
		h.t.Fatalf("join %v: %d, want %d", body, code, want)
	}
	return out
}

type wsClient struct {
	t      *testing.T
	c      *websocket.Conn
	mu     sync.Mutex
	state  map[string]any
	errs   []string
	events []string
	closed websocket.StatusCode
	done   chan struct{}
	notify chan struct{}
}

func (h *harness) connect(query string) *wsClient {
	h.t.Helper()
	url := "ws" + strings.TrimPrefix(h.srv.URL, "http") + "/api/ws?" + query
	c, _, err := websocket.Dial(context.Background(), url, nil)
	if err != nil {
		h.t.Fatal(err)
	}
	w := &wsClient{t: h.t, c: c, done: make(chan struct{}), notify: make(chan struct{}, 1), closed: -1}
	go w.loop()
	h.t.Cleanup(func() { _ = c.CloseNow() })
	_ = w.send("hello", map[string]any{"platform": "web", "model": "test", "os": "linux"})
	return w
}

func (w *wsClient) loop() {
	defer close(w.done)
	for {
		_, b, err := w.c.Read(context.Background())
		if err != nil {
			w.mu.Lock()
			w.closed = websocket.CloseStatus(err)
			w.mu.Unlock()
			w.ping()
			return
		}
		var m struct {
			Type string          `json:"type"`
			Data json.RawMessage `json:"data"`
		}
		_ = json.Unmarshal(b, &m)
		w.mu.Lock()
		switch m.Type {
		case "state":
			var s map[string]any
			_ = json.Unmarshal(m.Data, &s)
			w.state = s
		case "ping":
			go func(d json.RawMessage) {
				_ = w.c.Write(context.Background(), websocket.MessageText, []byte(`{"type":"pong","data":`+string(d)+`}`))
			}(m.Data)
		case "error":
			w.errs = append(w.errs, string(m.Data))
		case "event":
			w.events = append(w.events, string(m.Data))
		}
		w.mu.Unlock()
		w.ping()
	}
}

func (w *wsClient) ping() {
	select {
	case w.notify <- struct{}{}:
	default:
	}
}

func (w *wsClient) send(typ string, data any) error {
	b, _ := json.Marshal(map[string]any{"type": typ, "data": data})
	return w.c.Write(context.Background(), websocket.MessageText, b)
}

// waitFor polls the latest state until cond holds.
func (w *wsClient) waitFor(what string, cond func(s map[string]any) bool) map[string]any {
	w.t.Helper()
	deadline := time.After(5 * time.Second)
	for {
		w.mu.Lock()
		s := w.state
		w.mu.Unlock()
		if s != nil && cond(s) {
			return s
		}
		select {
		case <-w.notify:
		case <-time.After(50 * time.Millisecond):
		case <-deadline:
			w.t.Fatalf("timeout waiting for %s; last state: %v", what, s)
		}
	}
}

func (w *wsClient) waitErr(contains string) {
	w.t.Helper()
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		w.mu.Lock()
		for _, e := range w.errs {
			if strings.Contains(e, contains) {
				w.errs = nil
				w.mu.Unlock()
				return
			}
		}
		w.mu.Unlock()
		time.Sleep(20 * time.Millisecond)
	}
	w.t.Fatalf("no error containing %q (got %v)", contains, w.errs)
}

func (w *wsClient) waitClosed(code websocket.StatusCode) {
	w.t.Helper()
	select {
	case <-w.done:
	case <-time.After(3 * time.Second):
		w.t.Fatal("socket not closed")
	}
	if w.closed != code {
		w.t.Fatalf("close code %d, want %d", w.closed, code)
	}
}

func phase(p string) func(map[string]any) bool {
	return func(s map[string]any) bool { return s["phase"] == p }
}

func me(s map[string]any) map[string]any {
	m, _ := s["me"].(map[string]any)
	return m
}

func playerScore(s map[string]any, id string) float64 {
	for _, p := range s["players"].([]any) {
		pm := p.(map[string]any)
		if pm["id"] == id {
			return pm["score"].(float64)
		}
	}
	return -1
}

// ---- the tests ----

func TestFullGame(t *testing.T) {
	h := newHarness(t)
	// Like the scratch image: no system temp dir. Uploads and exports below must
	// stage in DATA_DIR/tmp.
	t.Setenv("TMPDIR", "/nonexistent-tmp")
	if code := h.do("POST", "/api/games", "", map[string]string{"adminPin": "12"}, nil); code != 400 {
		t.Fatalf("short admin pin: %d", code)
	}
	g := h.createGame("2222")
	admin, pin := g.Token, g.Game.PIN
	if len(pin) != 6 || !strings.HasSuffix(g.Game.Link, "/g/"+pin) {
		t.Fatalf("game %+v", g.Game)
	}
	var list []map[string]any
	h.do("GET", "/api/games", "", nil, &list)
	if len(list) != 1 || list[0]["pin"] != nil || list[0]["link"] != nil || list[0]["id"] == nil {
		t.Fatalf("public list must hide PIN and link: %v", list)
	}
	gameID := list[0]["id"].(string)
	if code := h.do("GET", "/api/games/000000", "", nil, nil); code != 404 {
		t.Fatalf("unknown game: %d", code)
	}

	// Roles by PIN.
	host := h.join(pin, map[string]string{"role": "host"}, 200).Token
	h.join(pin, map[string]string{"role": "host"}, 409)
	h.join(pin, map[string]string{"role": "admin", "adminPin": "9999"}, 401)
	admin2 := h.join(pin, map[string]string{"role": "admin", "adminPin": "2222"}, 200).Token
	screen := h.join(pin, map[string]string{"role": "screen"}, 200).Token
	h.join(pin, map[string]string{"role": "judge"}, 400)
	pa := h.join(pin, map[string]string{"role": "player", "name": "Аня"}, 200)
	pb := h.join(pin, map[string]string{"role": "player", "name": "Боря"}, 200)
	h.join(pin, map[string]string{"role": "player", "name": "аня"}, 409)
	var who struct {
		Role string
		Name string
	}
	if code := h.do("GET", "/api/auth/me", pa.Token, nil, &who); code != 200 || who.Role != "player" || who.Name != "Аня" {
		t.Fatalf("me %d %+v", code, who)
	}
	if code := h.do("GET", "/api/packs", host, nil, nil); code != 403 {
		t.Fatalf("host on packs: %d", code)
	}

	// Pack: one round, one category, two questions, one image (any admin may edit).
	var pack struct{ ID string }
	h.do("POST", "/api/packs", admin, map[string]string{"title": "Тестовый пак"}, &pack)
	var round struct{ ID int64 }
	h.do("POST", fmt.Sprintf("/api/packs/%s/rounds", pack.ID), admin2, map[string]string{"name": "Раунд 1"}, &round)
	var cat struct{ ID int64 }
	h.do("POST", fmt.Sprintf("/api/packs/%s/rounds/%d/categories", pack.ID, round.ID), admin, map[string]string{"name": "Кино"}, &cat)
	var q1, q2 struct {
		ID    int64
		Value int
	}
	h.do("POST", fmt.Sprintf("/api/packs/%s/categories/%d/questions", pack.ID, cat.ID), admin,
		map[string]any{"question": "Кто это?\n\n![](media:pic.png)", "answer": "Кот", "readingSeconds": 1}, &q1)
	h.do("POST", fmt.Sprintf("/api/packs/%s/categories/%d/questions", pack.ID, cat.ID), admin,
		map[string]any{"question": "Второй", "answer": "Ответ"}, &q2)
	if q1.Value != 100 || q2.Value != 200 {
		t.Fatalf("auto values %d %d", q1.Value, q2.Value)
	}
	var media struct{ Name, URL string }
	if code := h.do("POST", fmt.Sprintf("/api/packs/%s/media", pack.ID), admin, multipartFile("pic.png", []byte("PNGDATA")), &media); code != 201 {
		t.Fatalf("upload media: %d", code)
	}
	var got []byte
	if code := h.do("GET", media.URL, "", nil, &got); code != 200 || string(got) != "PNGDATA" {
		t.Fatalf("serve media: %d %q", code, got)
	}

	// Round-trip through .dub.
	var dub []byte
	if code := h.do("GET", fmt.Sprintf("/api/packs/%s/export", pack.ID), admin, nil, &dub); code != 200 {
		t.Fatalf("export: %d", code)
	}
	var imported struct {
		ID         string
		Questions  int
		MediaCount int
		Locked     bool
	}
	if code := h.do("POST", "/api/packs/import", admin, multipartFile("x.dub", dub), &imported); code != 201 {
		t.Fatalf("import: %d", code)
	}
	if imported.ID == pack.ID || imported.Questions != 2 || imported.MediaCount != 1 {
		t.Fatalf("imported %+v", imported)
	}
	if code := h.do("POST", "/api/packs/import", admin, multipartFile("x.dub", []byte("junk")), nil); code != 400 {
		t.Fatalf("junk import: %d", code)
	}

	// Locking.
	if code := h.do("POST", "/api/packs/"+imported.ID+"/lock", admin, nil, &imported); code != 200 || !imported.Locked {
		t.Fatalf("lock: %d %+v", code, imported)
	}
	for _, c := range []struct{ method, path string }{
		{"PATCH", "/api/packs/" + imported.ID},
		{"DELETE", "/api/packs/" + imported.ID},
		{"POST", "/api/packs/" + imported.ID + "/rounds"},
	} {
		var e struct{ Error struct{ Code string } }
		if code := h.do(c.method, c.path, admin, map[string]string{"title": "x", "name": "x"}, &e); code != 409 || e.Error.Code != "pack_locked" {
			t.Fatalf("%s %s on locked: %d %v", c.method, c.path, code, e)
		}
	}
	var cp struct {
		ID     string
		Title  string
		Locked bool
		Media  []any
	}
	if code := h.do("POST", "/api/packs/"+imported.ID+"/copy", admin, map[string]string{"title": "Копия"}, &cp); code != 201 || cp.Locked || cp.Title != "Копия" || len(cp.Media) != 1 {
		t.Fatalf("copy: %d %+v", code, cp)
	}

	H := h.connect("token=" + host)
	A := h.connect("token=" + admin)
	S := h.connect("token=" + screen)
	PA := h.connect("token=" + pa.Token)
	PB := h.connect("token=" + pb.Token)
	h.connect("role=screen").waitClosed(4001)

	// A screen from the public list sees the game but never its PIN or link.
	var watch struct {
		Token string
		Role  string
		Game  map[string]any
	}
	if code := h.do("POST", "/api/games/"+gameID+"/watch", "", nil, &watch); code != 200 || watch.Role != "screen" || watch.Game["pin"] != nil {
		t.Fatalf("watch: %d %+v", code, watch)
	}
	var watchMe map[string]any
	h.do("GET", "/api/auth/me", watch.Token, nil, &watchMe)
	if watchMe["game"].(map[string]any)["pin"] != nil {
		t.Fatal("/api/auth/me leaks the PIN to a watcher")
	}
	W := h.connect("token=" + watch.Token)
	ws := W.waitFor("watcher state", func(s map[string]any) bool { return s["role"] == "screen" })
	if g := ws["game"].(map[string]any); g["pin"] != nil || g["link"] != nil {
		t.Fatalf("watcher sees PIN/link: %v", g)
	}
	if g := S.waitFor("pin screen", func(s map[string]any) bool { return s["role"] == "screen" })["game"].(map[string]any); g["pin"] != pin {
		t.Fatalf("PIN screen must see the PIN: %v", g)
	}

	A.waitFor("admin sees device", func(s map[string]any) bool {
		p := s["players"].([]any)[0].(map[string]any)
		adm, _ := p["admin"].(map[string]any)
		return adm != nil && adm["device"].(map[string]any)["model"] == "test"
	})
	H.waitFor("host connected", func(s map[string]any) bool { return s["game"].(map[string]any)["hostConnected"] == true })

	_ = H.send("load_pack", map[string]any{"packId": pack.ID})
	H.waitErr("forbidden")
	_ = A.send("load_pack", map[string]any{"packId": pack.ID})
	H.waitFor("pack loaded", func(s map[string]any) bool { return s["pack"] != nil })
	if code := h.do("DELETE", "/api/packs/"+pack.ID, admin, nil, nil); code != 409 {
		t.Fatalf("delete pack in use: %d", code)
	}
	_ = A.send("update_settings", map[string]any{"modifiers": map[string]int{"cat": 0, "auction": 0, "noRisk": 0, "double": 0}})
	A.waitFor("no modifiers", func(s map[string]any) bool {
		return s["settings"].(map[string]any)["modifiers"].(map[string]any)["cat"].(float64) == 0
	})
	_ = H.send("start_game", nil)
	H.waitFor("board", phase("board"))
	_ = H.send("set_chooser", map[string]any{"playerId": pa.PlayerID})
	PA.waitFor("can select", func(s map[string]any) bool { return me(s)["canSelect"] == true })

	_ = PB.send("select_question", map[string]any{"questionId": q1.ID})
	PB.waitErr("forbidden")
	_ = PA.send("select_question", map[string]any{"questionId": q1.ID})

	sb := PB.waitFor("question", phase("question"))
	if ids, ok := sb["attemptedPlayerIds"].([]any); !ok || len(ids) != 0 {
		t.Fatalf("attemptedPlayerIds must be [], got %v", sb["attemptedPlayerIds"])
	}
	q := sb["question"].(map[string]any)
	if q["answerBlocks"] != nil {
		t.Fatal("player sees the answer before reveal")
	}
	blocks := q["blocks"].([]any)
	if len(blocks) != 2 || blocks[1].(map[string]any)["type"] != "image" {
		t.Fatalf("blocks %v", blocks)
	}
	hs := H.waitFor("host question", phase("question"))
	if hs["question"].(map[string]any)["answerBlocks"] == nil {
		t.Fatal("host must see the answer")
	}
	as := A.waitFor("admin question phase", phase("question"))
	if as["question"] != nil || as["board"] != nil || as["pack"] == nil {
		t.Fatal("admin must see the pack but not board/question")
	}
	S.waitFor("screen question", phase("question"))

	_ = PB.send("buzz", nil)
	PB.waitErr("wrong_phase")
	PA.waitFor("A open", func(s map[string]any) bool { return me(s)["buzzer"] == "open" })
	_ = PA.send("buzz", nil)
	PA.waitFor("A answering", func(s map[string]any) bool { return me(s)["buzzer"] == "answering" })
	_ = PA.send("submit_answer", map[string]any{"text": "собака"})
	H.waitFor("typed", func(s map[string]any) bool { return s["typedAnswer"] == "собака" })
	if s := PB.waitFor("B closed", func(s map[string]any) bool { return me(s)["buzzer"] == "closed" }); s["typedAnswer"] != nil {
		t.Fatal("typed answer leaked to a player")
	}
	_ = H.send("judge", map[string]any{"correct": false})
	PA.waitFor("A used", func(s map[string]any) bool { return me(s)["buzzer"] == "used" })
	PB.waitFor("B open again", func(s map[string]any) bool { return me(s)["buzzer"] == "open" })
	_ = PB.send("buzz", nil)
	H.waitFor("B answering", func(s map[string]any) bool { return s["answeringPlayerId"] == pb.PlayerID })
	_ = H.send("judge", map[string]any{"correct": true})

	ra := PA.waitFor("reveal", phase("reveal"))
	if ra["question"].(map[string]any)["answerBlocks"] == nil {
		t.Fatal("answer hidden on reveal")
	}
	if playerScore(ra, pb.PlayerID) != 100 || playerScore(ra, pa.PlayerID) != 0 || ra["chooserId"] != pb.PlayerID {
		t.Fatalf("after judge: %v chooser %v", ra["players"], ra["chooserId"])
	}
	_ = H.send("continue", nil)
	PB.waitFor("board again", phase("board"))
	_ = PB.send("select_question", map[string]any{"questionId": q2.ID})
	H.waitFor("q2", phase("question"))
	_ = H.send("skip_question", nil)
	H.waitFor("reveal q2", phase("reveal"))
	_ = H.send("continue", nil)
	H.waitFor("round end", phase("round_end"))
	_ = H.send("next_round", nil)
	S.waitFor("finished", phase("finished"))

	// Admin corrections.
	_ = A.send("adjust_score", map[string]any{"playerId": pa.PlayerID, "delta": 50})
	_ = A.send("set_buzz_offset", map[string]any{"playerId": pa.PlayerID, "offsetMs": 250})
	_ = A.send("set_buzz_offset", map[string]any{"playerId": pa.PlayerID, "offsetMs": 99999})
	A.waitErr("invalid")
	A.waitFor("offset", func(s map[string]any) bool {
		p := s["players"].([]any)[0].(map[string]any)
		return p["score"].(float64) == 50 && p["admin"].(map[string]any)["buzzOffsetMs"].(float64) == 250
	})
	_ = A.send("judge", map[string]any{"correct": true})
	A.waitErr("forbidden")
	_ = A.send("update_game", map[string]any{"title": "Новая", "adminPin": "5555"})
	A.waitFor("renamed", func(s map[string]any) bool { return s["game"].(map[string]any)["title"] == "Новая" })
	h.join(pin, map[string]string{"role": "admin", "adminPin": "2222"}, 401)

	// Game file round-trip (admin only).
	var file []byte
	if code := h.do("GET", "/api/game/export", host, nil, nil); code != 403 {
		t.Fatalf("host export: %d", code)
	}
	if code := h.do("GET", "/api/game/export", admin, nil, &file); code != 200 || !bytes.Contains(file, []byte(`"svoy-igra/game"`)) {
		t.Fatalf("export game: %d", code)
	}
	if bytes.Contains(file, []byte(admin)) || bytes.Contains(file, []byte("adminHash")) {
		t.Fatal("game export leaks admin secrets")
	}
	_ = H.send("reset_game", map[string]any{"keepPlayers": false})
	PA.waitClosed(4001)
	PB.waitClosed(4001)
	H.waitFor("empty lobby", func(s map[string]any) bool { return s["phase"] == "lobby" && len(s["players"].([]any)) == 0 })
	if code := h.do("POST", "/api/game/import", admin, bytes.NewBuffer(file), nil); code != 204 {
		t.Fatalf("import game: %d", code)
	}
	PA2 := h.connect("token=" + pa.Token)
	if s := PA2.waitFor("restored", func(s map[string]any) bool { return me(s) != nil && me(s)["score"].(float64) == 50 }); s["phase"] != "finished" {
		t.Fatalf("restored phase %v", s["phase"])
	}
	PA3 := h.connect("token=" + pa.Token)
	PA2.waitClosed(4009)
	PA3.waitFor("connected", func(s map[string]any) bool { return me(s) != nil })
	_ = H.send("kick_player", map[string]any{"playerId": pa.PlayerID})
	PA3.waitClosed(4003)

	// The host leaves; the slot frees at once.
	_ = H.send("leave", nil)
	H.waitClosed(1000)
	host2 := h.join(pin, map[string]string{"role": "host"}, 200).Token
	if code := h.do("GET", "/api/auth/me", host, nil, nil); code != 401 {
		t.Fatalf("old host token after leave: %d", code)
	}

	// A second game is independent and shares the pack library.
	g2 := h.createGame("7777")
	if g2.Game.PIN == pin {
		t.Fatal("PIN reused")
	}
	A2 := h.connect("token=" + g2.Token)
	_ = A2.send("load_pack", map[string]any{"packId": cp.ID})
	A2.waitFor("game 2 pack", func(s map[string]any) bool {
		return s["pack"] != nil && s["game"].(map[string]any)["pin"] == g2.Game.PIN
	})
	h.join(g2.Game.PIN, map[string]string{"role": "admin", "adminPin": "5555"}, 401)

	// Closing the first game.
	H2 := h.connect("token=" + host2)
	H2.waitFor("host2", func(s map[string]any) bool { return s["role"] == "host" })
	_ = A.send("close_game", nil)
	A.waitClosed(4004)
	H2.waitClosed(4004)
	S.waitClosed(4004)
	if code := h.do("GET", "/api/games/"+pin, "", nil, nil); code != 404 {
		t.Fatalf("closed game still found: %d", code)
	}
	if code := h.do("GET", "/api/auth/me", admin, nil, nil); code != 401 {
		t.Fatalf("token of a closed game: %d", code)
	}
}

func TestGamesSurviveRestart(t *testing.T) {
	dir := t.TempDir()
	h := newHarnessAt(t, dir)
	g := h.createGame("1234")
	p := h.join(g.Game.PIN, map[string]string{"role": "player", "name": "Вася"}, 200)
	h.stop()

	h2 := newHarnessAt(t, dir)
	var who struct{ Role, Name string }
	if code := h2.do("GET", "/api/auth/me", p.Token, nil, &who); code != 200 || who.Name != "Вася" {
		t.Fatalf("after restart: %d %+v", code, who)
	}
	h2.join(g.Game.PIN, map[string]string{"role": "admin", "adminPin": "1234"}, 200)
}

func TestSpecialsAndFinal(t *testing.T) {
	h := newHarness(t)
	g := h.createGame("2222")
	admin, pin := g.Token, g.Game.PIN

	// Round 1: four questions (one per modifier); round 2: a final with three themes.
	var pack struct{ ID string }
	h.do("POST", "/api/packs", admin, map[string]string{"title": "Спец"}, &pack)
	var r1, r2 struct{ ID int64 }
	h.do("POST", "/api/packs/"+pack.ID+"/rounds", admin, map[string]string{"name": "Первый"}, &r1)
	h.do("POST", "/api/packs/"+pack.ID+"/rounds", admin, map[string]string{"name": "Финал", "kind": "final"}, &r2)
	var cat struct{ ID int64 }
	h.do("POST", fmt.Sprintf("/api/packs/%s/rounds/%d/categories", pack.ID, r1.ID), admin, map[string]string{"name": "Разное"}, &cat)
	for i := range 4 {
		h.do("POST", fmt.Sprintf("/api/packs/%s/categories/%d/questions", pack.ID, cat.ID), admin,
			map[string]any{"question": fmt.Sprintf("В%d", i), "answer": "О", "readingSeconds": 1}, nil)
	}
	for _, name := range []string{"Тема А", "Тема Б", "Тема В"} {
		var th struct{ ID int64 }
		h.do("POST", fmt.Sprintf("/api/packs/%s/rounds/%d/categories", pack.ID, r2.ID), admin, map[string]string{"name": name}, &th)
		var fq struct{ Value int }
		h.do("POST", fmt.Sprintf("/api/packs/%s/categories/%d/questions", pack.ID, th.ID), admin,
			map[string]any{"question": "Финальный " + name, "answer": "Финальный ответ"}, &fq)
		if fq.Value != 0 {
			t.Fatalf("final question value %d", fq.Value)
		}
		if code := h.do("POST", fmt.Sprintf("/api/packs/%s/categories/%d/questions", pack.ID, th.ID), admin, map[string]any{"question": "x"}, nil); code != 409 {
			t.Fatalf("second question in a final theme: %d", code)
		}
	}

	host := h.join(pin, map[string]string{"role": "host"}, 200).Token
	pa := h.join(pin, map[string]string{"role": "player", "name": "Аня"}, 200)
	pb := h.join(pin, map[string]string{"role": "player", "name": "Боря"}, 200)
	H, A := h.connect("token="+host), h.connect("token="+admin)
	P := map[string]*wsClient{pa.PlayerID: h.connect("token=" + pa.Token), pb.PlayerID: h.connect("token=" + pb.Token)}
	other := map[string]string{pa.PlayerID: pb.PlayerID, pb.PlayerID: pa.PlayerID}

	_ = A.send("load_pack", map[string]any{"packId": pack.ID})
	H.waitFor("pack", func(s map[string]any) bool { return s["pack"] != nil })
	_ = A.send("set_score", map[string]any{"playerId": pa.PlayerID, "score": 1000})
	_ = A.send("set_score", map[string]any{"playerId": pb.PlayerID, "score": 1000})
	_ = H.send("start_game", nil)
	H.waitFor("board", phase("board"))
	_ = H.send("set_chooser", map[string]any{"playerId": pa.PlayerID})
	H.waitFor("chooser A", func(s map[string]any) bool { return s["chooserId"] == pa.PlayerID })

	seen := map[string]bool{}
	for range 4 {
		s := H.waitFor("board turn", func(s map[string]any) bool { return s["phase"] == "board" && s["chooserId"] != nil })
		chooser := s["chooserId"].(string)
		// Fixed scores make the auction deterministic: the other player can outbid.
		_ = A.send("set_score", map[string]any{"playerId": chooser, "score": 1000})
		_ = A.send("set_score", map[string]any{"playerId": other[chooser], "score": 1500})
		s = H.waitFor("scores set", func(s map[string]any) bool {
			return playerScore(s, chooser) == 1000 && playerScore(s, other[chooser]) == 1500
		})
		var qid float64
		for _, c := range s["board"].([]any)[0].(map[string]any)["questions"].([]any) {
			if cell := c.(map[string]any); cell["played"] == false {
				qid = cell["id"].(float64)
				if _, leak := cell["modifier"]; leak {
					t.Fatal("modifier visible on the board")
				}
				break
			}
		}
		P[chooser].waitFor("can select", func(s map[string]any) bool { return me(s)["canSelect"] == true })
		_ = P[chooser].send("select_question", map[string]any{"questionId": qid})
		s = H.waitFor("opened", func(s map[string]any) bool {
			q, _ := s["question"].(map[string]any)
			return q != nil && q["id"].(float64) == qid && s["phase"] != "board"
		})
		mod := s["question"].(map[string]any)["modifier"].(string)
		seen[mod] = true
		before := playerScore(s, chooser)
		answerer, wantDelta := chooser, 0.0
		switch mod {
		case "double":
			P[chooser].waitFor("open", func(s map[string]any) bool { return me(s)["buzzer"] == "open" })
			_ = P[chooser].send("buzz", nil)
			H.waitFor("answering", phase("answering"))
			_ = H.send("judge", map[string]any{"correct": true})
			wantDelta = 2 * s["question"].(map[string]any)["value"].(float64)
		case "no_risk":
			if s["soloPlayerId"] != chooser {
				t.Fatalf("no_risk solo %v", s["soloPlayerId"])
			}
			H.waitFor("solo answering", phase("answering"))
			_ = H.send("judge", map[string]any{"correct": false})
			wantDelta = 0
		case "cat":
			if s["phase"] != "cat_transfer" || len(s["question"].(map[string]any)["blocks"].([]any)) != 0 {
				t.Fatalf("cat must hide the question: %v", s["question"])
			}
			_ = P[chooser].send("give_cat", map[string]any{"playerId": chooser})
			P[chooser].waitErr("invalid")
			answerer = other[chooser]
			before = playerScore(s, answerer)
			_ = P[chooser].send("give_cat", map[string]any{"playerId": answerer})
			P[answerer].waitFor("cat answering", func(s map[string]any) bool { return me(s)["buzzer"] == "answering" })
			_ = H.send("judge", map[string]any{"correct": false})
			wantDelta = -s["question"].(map[string]any)["value"].(float64)
		case "auction":
			a := s["auction"].(map[string]any)
			if s["phase"] != "auction" || a["highBidderId"] != chooser || a["turnPlayerId"] != other[chooser] {
				t.Fatalf("auction start %v", a)
			}
			value := s["question"].(map[string]any)["value"].(float64)
			_ = P[other[chooser]].send("auction_bid", map[string]any{"amount": value})
			P[other[chooser]].waitErr("invalid") // must exceed the nominal value
			_ = P[other[chooser]].send("auction_bid", map[string]any{"amount": value + 100})
			P[chooser].waitFor("my turn", func(s map[string]any) bool { return me(s)["canBid"] == true })
			_ = P[chooser].send("auction_all_in", nil)
			P[other[chooser]].waitFor("turn after all-in", func(s map[string]any) bool { return me(s)["canBid"] == true })
			_ = P[other[chooser]].send("auction_bid", map[string]any{"amount": 1200})
			P[other[chooser]].waitErr("invalid") // only a higher ва-банк after a ва-банк
			_ = P[other[chooser]].send("auction_pass", nil)
			H.waitFor("auction answering", func(s map[string]any) bool { return s["phase"] == "answering" && s["answeringPlayerId"] == chooser })
			_ = H.send("judge", map[string]any{"correct": true})
			wantDelta = 1000 // ва-банк: the whole score
		}
		r := H.waitFor("reveal", phase("reveal"))
		if got := playerScore(r, answerer) - before; got != wantDelta {
			t.Fatalf("%s: delta %v, want %v", mod, got, wantDelta)
		}
		_ = H.send("continue", nil)
	}
	if len(seen) != 4 {
		t.Fatalf("modifiers seen %v", seen)
	}

	// Final: make sure both are finalists, A lower than B.
	H.waitFor("round end", phase("round_end"))
	_ = A.send("set_score", map[string]any{"playerId": pa.PlayerID, "score": 300})
	_ = A.send("set_score", map[string]any{"playerId": pb.PlayerID, "score": 500})
	H.waitFor("scores", func(s map[string]any) bool {
		return playerScore(s, pb.PlayerID) == 500 && playerScore(s, pa.PlayerID) == 300
	})
	_ = H.send("next_round", nil)
	s := H.waitFor("final themes", phase("final_themes"))
	f := s["final"].(map[string]any)
	if f["removerId"] != pa.PlayerID || len(f["themes"].([]any)) != 3 {
		t.Fatalf("final start %v", f)
	}
	theme := func(s map[string]any, i int) float64 {
		return s["final"].(map[string]any)["themes"].([]any)[i].(map[string]any)["id"].(float64)
	}
	_ = P[pb.PlayerID].send("final_remove_theme", map[string]any{"themeId": theme(s, 0)})
	P[pb.PlayerID].waitErr("forbidden")
	_ = P[pa.PlayerID].send("final_remove_theme", map[string]any{"themeId": theme(s, 0)})
	P[pb.PlayerID].waitFor("B removes", func(s map[string]any) bool { return me(s)["canRemoveTheme"] == true })
	_ = P[pb.PlayerID].send("final_remove_theme", map[string]any{"themeId": theme(s, 1)})
	s = P[pa.PlayerID].waitFor("bets", phase("final_bets"))
	if q := s["question"].(map[string]any); q["categoryName"] != "Тема В" || len(q["blocks"].([]any)) != 0 {
		t.Fatalf("bets question %v", q)
	}
	_ = P[pa.PlayerID].send("final_bet", map[string]any{"amount": 301})
	P[pa.PlayerID].waitErr("invalid")
	_ = P[pa.PlayerID].send("final_bet", map[string]any{"amount": 300})
	sb := P[pb.PlayerID].waitFor("A bet seen", func(s map[string]any) bool {
		return s["final"].(map[string]any)["participants"].([]any)[0].(map[string]any)["hasBet"] == true
	})
	if sb["final"].(map[string]any)["participants"].([]any)[0].(map[string]any)["bet"] != nil {
		t.Fatal("a rival's bet leaked")
	}
	_ = P[pb.PlayerID].send("final_bet", map[string]any{"amount": 200})
	P[pa.PlayerID].waitFor("final question", func(s map[string]any) bool { return me(s)["canAnswerFinal"] == true })
	_ = P[pa.PlayerID].send("final_answer", map[string]any{"text": "Финальный ответ"})
	_ = P[pb.PlayerID].send("final_answer", map[string]any{"text": "не знаю"})
	H.waitFor("answers in", func(s map[string]any) bool {
		for _, p := range s["final"].(map[string]any)["participants"].([]any) {
			if p.(map[string]any)["answer"] == nil {
				return false
			}
		}
		return true
	})
	_ = H.send("final_close_answers", nil)
	H.waitFor("judging", phase("final_judging"))
	_ = H.send("final_judge", map[string]any{"playerId": pa.PlayerID, "correct": true})
	_ = H.send("final_judge", map[string]any{"playerId": pb.PlayerID, "correct": false})
	s = P[pa.PlayerID].waitFor("final reveal", phase("final_reveal"))
	if playerScore(s, pa.PlayerID) != 600 || playerScore(s, pb.PlayerID) != 300 {
		t.Fatalf("final scores %v", s["players"])
	}
	if s["question"].(map[string]any)["answerBlocks"] == nil {
		t.Fatal("final answer hidden at reveal")
	}
	_ = H.send("continue", nil)
	H.waitFor("finished", phase("finished"))
}

func TestAvatars(t *testing.T) {
	h := newHarness(t)
	g := h.createGame("2222")
	pin := g.Game.PIN
	p := h.join(pin, map[string]string{"role": "player", "name": "Аня"}, 200)
	host := h.join(pin, map[string]string{"role": "host"}, 200).Token
	screen := h.join(pin, map[string]string{"role": "screen"}, 200).Token
	png := append([]byte("\x89PNG\r\n\x1a\n"), bytes.Repeat([]byte{0}, 64)...)

	if code := h.do("POST", "/api/avatar", p.Token, multipartFile("a.txt", []byte("hello")), nil); code != 400 {
		t.Fatalf("text avatar: %d", code)
	}
	if code := h.do("POST", "/api/avatar", screen, multipartFile("a.png", png), nil); code != 403 {
		t.Fatalf("screen avatar: %d", code)
	}
	if code := h.do("POST", "/api/avatar", p.Token, multipartFile("big.png", append(png, make([]byte, 2<<20)...)), nil); code != 413 {
		t.Fatalf("big avatar: %d", code)
	}
	var up struct{ AvatarURL string }
	if code := h.do("POST", "/api/avatar", p.Token, multipartFile("a.png", png), &up); code != 200 || up.AvatarURL == "" || strings.Contains(up.AvatarURL, pin) {
		t.Fatalf("upload: %d %q", code, up.AvatarURL)
	}
	var img []byte
	if code := h.do("GET", up.AvatarURL, "", nil, &img); code != 200 || !bytes.Equal(img, png) {
		t.Fatalf("serve avatar: %d", code)
	}
	var hostUp struct{ AvatarURL string }
	h.do("POST", "/api/avatar", host, multipartFile("h.png", png), &hostUp)

	A := h.connect("token=" + g.Token)
	s := A.waitFor("avatars in state", func(s map[string]any) bool {
		pl := s["players"].([]any)[0].(map[string]any)
		return pl["avatarUrl"] == up.AvatarURL && s["game"].(map[string]any)["hostAvatarUrl"] == hostUp.AvatarURL
	})
	_ = s
	// A new upload replaces the old file.
	var up2 struct{ AvatarURL string }
	h.do("POST", "/api/avatar", p.Token, multipartFile("b.png", png), &up2)
	if up2.AvatarURL == up.AvatarURL {
		t.Fatal("avatar URL must change on upload")
	}
	if code := h.do("GET", up.AvatarURL, "", nil, nil); code != 404 {
		t.Fatalf("old avatar still served: %d", code)
	}
	// Moderation.
	_ = A.send("clear_avatar", map[string]any{"playerId": p.PlayerID})
	A.waitFor("cleared", func(s map[string]any) bool { return s["players"].([]any)[0].(map[string]any)["avatarUrl"] == nil })
	if code := h.do("GET", up2.AvatarURL, "", nil, nil); code != 404 {
		t.Fatalf("cleared avatar still served: %d", code)
	}
	if code := h.do("DELETE", "/api/avatar", host, nil, nil); code != 204 {
		t.Fatalf("delete host avatar: %d", code)
	}
	A.waitFor("host cleared", func(s map[string]any) bool { return s["game"].(map[string]any)["hostAvatarUrl"] == nil })
}
