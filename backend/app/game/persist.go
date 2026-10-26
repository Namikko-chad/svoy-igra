package game

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"strconv"

	"svoy-igra/app/httpx"
	"svoy-igra/app/packs"
)

// snapshot builds the game file; call with the lock held.
func (e *Engine) snapshot() *File {
	f := &File{
		Format: FileFormat, Version: FileVersion, SavedAt: e.ms(),
		Phase: e.phase, RoundIndex: e.roundIndex, Settings: e.settings,
		Played: make([]int64, 0, len(e.played)), Players: make([]*Player, 0, len(e.players)),
		History: slices.Clone(e.history),
	}
	if f.History == nil {
		f.History = []HistoryEntry{}
	}
	if e.pack != nil {
		f.Pack = &PackRef{ID: e.pack.ID, Title: e.pack.Title}
	}
	if e.chooserID != "" {
		f.ChooserID = ptr(e.chooserID)
	}
	for id, ok := range e.played {
		if ok {
			f.Played = append(f.Played, id)
		}
	}
	slices.Sort(f.Played)
	f.Modifiers = map[string]string{}
	for id, m := range e.modifiers {
		f.Modifiers[strconv.FormatInt(id, 10)] = m
	}
	if fs := e.final; fs != nil {
		ff := &FinalFile{Order: slices.Clone(fs.order), Turn: fs.turn, Finalists: slices.Clone(fs.finalists),
			Bets: maps.Clone(fs.bets), Answers: maps.Clone(fs.answers), Judged: maps.Clone(fs.judged), Removed: []int64{}}
		for id, r := range fs.removed {
			if r {
				ff.Removed = append(ff.Removed, id)
			}
		}
		slices.Sort(ff.Removed)
		if fs.remover != "" {
			ff.RemoverID = ptr(fs.remover)
		}
		f.Final = ff
	}
	for _, p := range e.players {
		cp := *p
		f.Players = append(f.Players, &cp)
	}
	return f
}

// Export returns the current game file.
func (e *Engine) Export() *File {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.snapshot()
}

func validateFile(f *File) error {
	if f.Format != FileFormat || f.Version != FileVersion {
		return httpx.BadRequest("invalid_game_file", "Это не файл игры (format/version)")
	}
	seen := map[string]bool{}
	for _, p := range f.Players {
		if p == nil || p.ID == "" || p.Token == "" || p.Name == "" || seen[p.ID] {
			return httpx.BadRequest("invalid_game_file", "Некорректный список игроков")
		}
		seen[p.ID] = true
	}
	return nil
}

// restore replaces the game with f; call with the lock held. strict makes a
// missing pack an error (import) instead of a downgrade to the lobby (start-up).
func (e *Engine) restore(f *File, strict bool) error {
	if err := validateFile(f); err != nil {
		return err
	}
	var pack *packs.Pack
	if f.Pack != nil {
		p, err := e.store.Get(f.Pack.ID)
		if err != nil {
			if strict {
				return httpx.Conflict("pack_missing", fmt.Sprintf("Пака «%s» нет в библиотеке — сначала загрузите его", f.Pack.Title))
			}
			slog.Warn("game pack is missing, the game goes back to the lobby", "pack", f.Pack.ID)
		} else {
			pack = p
		}
	}

	e.gen++
	e.q = nil
	e.pack = pack
	e.phase = f.Phase
	switch f.Phase {
	case PhaseQuestion, PhaseAnswering, PhaseReveal, PhaseCatTransfer, PhaseAuction:
		e.phase = PhaseBoard
	case PhaseFinalThemes, PhaseFinalBets, PhaseFinalQuestion, PhaseFinalJudging, PhaseFinalReveal:
	case PhaseLobby, PhaseBoard, PhaseRoundEnd, PhaseFinished:
	default:
		e.phase = PhaseLobby
	}
	e.roundIndex = f.RoundIndex
	if pack == nil {
		e.phase = PhaseLobby
		e.roundIndex = 0
	} else if e.roundIndex < 0 || e.roundIndex >= len(pack.Rounds) {
		e.roundIndex = 0
	}
	e.settings = DefaultSettings()
	if f.Settings.ReadingSeconds >= 1 && f.Settings.ReadingSeconds <= 120 {
		e.settings.ReadingSeconds = f.Settings.ReadingSeconds
	}
	if f.Settings.BuzzSeconds >= 3 && f.Settings.BuzzSeconds <= 300 {
		e.settings.BuzzSeconds = f.Settings.BuzzSeconds
	}
	e.settings.WrongPenalty = f.Settings.WrongPenalty
	e.settings.AutoLatencyCompensation = f.Settings.AutoLatencyCompensation
	e.played = map[int64]bool{}
	for _, id := range f.Played {
		e.played[id] = true
	}
	e.auction = nil
	e.final = nil
	e.modifiers = map[int64]string{}
	for k, m := range f.Modifiers {
		if id, err := strconv.ParseInt(k, 10, 64); err == nil && (m == ModCat || m == ModAuction || m == ModNoRisk || m == ModDouble) {
			e.modifiers[id] = m
		}
	}

	old := map[string]*Player{}
	for _, p := range e.players {
		old[p.ID] = p
	}
	var revoked []string
	e.players = make([]*Player, 0, len(f.Players))
	for _, p := range f.Players {
		cp := *p
		cp.BuzzOffsetMs = max(-5000, min(cp.BuzzOffsetMs, 10000))
		if !e.avatarExists(cp.Avatar) {
			cp.Avatar = ""
		}
		if o := old[cp.ID]; o != nil && o.Token == cp.Token {
			cp.connected, cp.rtts, cp.lastSeen = o.connected, o.rtts, o.lastSeen
			delete(old, cp.ID)
		}
		e.players = append(e.players, &cp)
	}
	for _, o := range old {
		revoked = append(revoked, o.Token)
	}
	e.revoke(revoked, 4001)

	e.chooserID = ""
	if f.ChooserID != nil && e.player(*f.ChooserID) != nil {
		e.chooserID = *f.ChooserID
	}
	e.history = slices.Clone(f.History)
	if e.phase.isFinal() {
		e.restoreFinal(f.Final)
	}
	e.changed(ScopeAll)
	return nil
}

// restoreFinal rebuilds a final in progress; a final_question in progress
// resumes as final_judging (the answers so far are kept).
func (e *Engine) restoreFinal(ff *FinalFile) {
	if ff == nil || e.pack == nil || e.roundKind() != "final" {
		e.phase = PhaseBoard
		e.startRound(e.roundIndex)
		e.pending = nil
		return
	}
	fs := &finalState{removed: map[int64]bool{}, bets: map[string]int{}, answers: map[string]string{}, judged: map[string]bool{}}
	for _, c := range e.pack.Rounds[e.roundIndex].Categories {
		if len(c.Questions) > 0 {
			fs.themes = append(fs.themes, c)
		}
	}
	for _, id := range ff.Removed {
		fs.removed[id] = true
	}
	for _, id := range ff.Finalists {
		if e.player(id) != nil {
			fs.finalists = append(fs.finalists, id)
		}
	}
	for _, id := range ff.Order {
		if e.player(id) != nil {
			fs.order = append(fs.order, id)
		}
	}
	maps.Copy(fs.bets, ff.Bets)
	maps.Copy(fs.answers, ff.Answers)
	maps.Copy(fs.judged, ff.Judged)
	if len(fs.order) > 0 {
		fs.turn = ff.Turn % len(fs.order)
	}
	if ff.RemoverID != nil && e.player(*ff.RemoverID) != nil {
		fs.remover = *ff.RemoverID
	} else if len(fs.order) > 0 {
		fs.remover = fs.order[fs.turn]
	}
	e.final = fs
	if len(fs.finalists) == 0 || len(fs.themes) == 0 {
		e.final = nil
		e.phase = PhaseFinished
		return
	}
	if e.phase == PhaseFinalQuestion {
		e.phase = PhaseFinalJudging
	}
	if e.phase != PhaseFinalThemes {
		fs.remover = ""
		e.buildFinalQuestion()
		if e.q != nil && e.phase != PhaseFinalBets {
			e.q.hidden = false
		}
	}
}

// Import replaces the game with an uploaded file.
func (e *Engine) Import(f *File) error {
	return e.do(func() error { return e.restore(f, true) })
}

// record is the on-disk form of a game: identity plus content.
type record struct {
	ID           string   `json:"id"`
	PIN          string   `json:"pin"`
	Title        string   `json:"title"`
	LinkBase     string   `json:"linkBase"`
	CreatedAt    int64    `json:"createdAt"`
	EmptySince   int64    `json:"emptySince"`
	AdminSalt    string   `json:"adminSalt"`
	AdminHash    string   `json:"adminHash"`
	AdminTokens  []string `json:"adminTokens"`
	HostToken    string   `json:"hostToken"`
	ScreenTokens []string `json:"screenTokens"`
	WatchTokens  []string `json:"watchTokens"`
	HostAvatar   string   `json:"hostAvatar,omitempty"`
	Game         *File    `json:"game"`
}

func keys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	slices.Sort(out)
	return out
}

// Save writes the game to its file when it changed (or always with force).
func (e *Engine) Save(force bool) {
	e.mu.Lock()
	if e.closed || (!e.dirty && !force) {
		e.mu.Unlock()
		return
	}
	emptySince := e.emptySince
	if e.sockets == 0 && emptySince == 0 {
		emptySince = e.ms()
	}
	rec := record{
		ID: e.id, PIN: e.pin, Title: e.title, LinkBase: e.linkBase, CreatedAt: e.createdAt,
		EmptySince: emptySince, AdminSalt: e.adminSalt, AdminHash: e.adminHash,
		AdminTokens: keys(e.adminTokens), HostToken: e.hostToken, ScreenTokens: keys(e.screenTokens),
		WatchTokens: keys(e.watchTokens), HostAvatar: e.hostAvatar,
		Game: e.snapshot(),
	}
	e.dirty = false
	e.mu.Unlock()

	if err := writeFileAtomic(e.path, rec); err != nil {
		slog.Error("save game file", "path", e.path, "err", err)
		e.mu.Lock()
		e.dirty = true
		e.mu.Unlock()
	}
}

// loadEngine restores a game saved by Save.
func loadEngine(store *packs.Store, path string) (*Engine, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var rec record
	if err := json.Unmarshal(b, &rec); err != nil {
		return nil, err
	}
	if rec.ID == "" || len(rec.PIN) != 6 || rec.AdminHash == "" || rec.Game == nil {
		return nil, errors.New("incomplete game record")
	}
	e := newEngine(store, path)
	e.id, e.pin, e.title, e.linkBase, e.createdAt = rec.ID, rec.PIN, rec.Title, rec.LinkBase, rec.CreatedAt
	e.adminSalt, e.adminHash, e.hostToken = rec.AdminSalt, rec.AdminHash, rec.HostToken
	for _, t := range rec.AdminTokens {
		e.adminTokens[t] = true
	}
	for _, t := range rec.ScreenTokens {
		e.screenTokens[t] = true
	}
	for _, t := range rec.WatchTokens {
		e.watchTokens[t] = true
	}
	e.emptySince = rec.EmptySince
	e.avatarDir = filepath.Join(filepath.Dir(filepath.Dir(path)), "avatars", rec.ID)
	if e.avatarExists(rec.HostAvatar) {
		e.hostAvatar = rec.HostAvatar
	}
	if e.emptySince == 0 {
		e.emptySince = e.ms()
	}
	if err := e.restore(rec.Game, false); err != nil {
		return nil, err
	}
	e.pending = nil
	e.dirty = false
	return e, nil
}

func writeFileAtomic(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), ".game-*.json")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(b); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
