package game

import (
	"math/rand/v2"
	"slices"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	"svoy-igra/app/httpx"
	"svoy-igra/app/ids"
	"svoy-igra/app/packs"
)

// Scope says who must receive a fresh state.
type Scope int

const (
	ScopeAll Scope = iota
	ScopeAdmins
)

// Hooks are called outside the engine lock, in the order the effects happened.
type Hooks struct {
	Changed func(Scope)
	Event   func(Event)
	// Revoke closes the sockets holding the given tokens with a WebSocket close code.
	Revoke func(tokens []string, code int)
	// Closed is called once when the game is deleted.
	Closed func()
}

// question is the live state of the open question.
type question struct {
	q            packs.Question
	categoryName string
	blocks       []packs.Block
	answerBlocks []packs.Block

	openedAt      int64
	readingEndsAt int64
	buzzStartsAt  int64 // base of the current buzz window
	buzzEndsAt    int64
	openAt        map[string]int64 // per-player moment the button opens
	opened        map[string]bool  // set by the server when that moment passed
	attempted     []string
	answering     string
	typed         string
	result        *Result

	modifier string // ModCat... or ""
	stake    int    // what a correct answer earns
	solo     string // the only player who answers (cat, auction, no_risk)
	hidden   bool   // the text is not shown yet (cat_transfer, auction, final bets)
}

type Engine struct {
	mu    sync.Mutex
	store *packs.Store
	path  string
	hooks Hooks
	now   func() time.Time

	identity // PIN, tokens of non-player roles, presence (identity.go)

	pack       *packs.Pack // snapshot taken by load_pack
	phase      Phase
	roundIndex int
	chooserID  string
	played     map[int64]bool
	settings   Settings
	players    []*Player
	history    []HistoryEntry

	q         *question
	modifiers map[int64]string // secret special cells of the current round
	auction   *auctionState
	final     *finalState
	gen       int // bumps whenever pending timers must be ignored

	dirty   bool
	pending []func() // hook calls collected under the lock
}

func newEngine(store *packs.Store, path string) *Engine {
	return &Engine{
		store:     store,
		path:      path,
		now:       time.Now,
		phase:     PhaseLobby,
		played:    map[int64]bool{},
		modifiers: map[int64]string{},
		settings:  DefaultSettings(),
		identity:  identity{adminTokens: map[string]bool{}, screenTokens: map[string]bool{}, watchTokens: map[string]bool{}},
	}
}

// SetHooks wires the outputs; call before serving.
func (e *Engine) SetHooks(h Hooks) { e.hooks = h }

func (e *Engine) ms() int64 { return e.now().UnixMilli() }

// do runs fn under the lock, then delivers the hook calls fn collected.
func (e *Engine) do(fn func() error) error {
	e.mu.Lock()
	err := fn()
	pending := e.pending
	e.pending = nil
	e.mu.Unlock()
	for _, p := range pending {
		p()
	}
	return err
}

func (e *Engine) changed(scope Scope) {
	if scope == ScopeAll {
		e.dirty = true
	}
	if h := e.hooks.Changed; h != nil {
		e.pending = append(e.pending, func() { h(scope) })
	}
}

func (e *Engine) emit(ev Event) {
	if h := e.hooks.Event; h != nil {
		e.pending = append(e.pending, func() { h(ev) })
	}
}

func (e *Engine) revoke(tokens []string, code int) {
	if h := e.hooks.Revoke; h != nil && len(tokens) > 0 {
		e.pending = append(e.pending, func() { h(tokens, code) })
	}
}

func (e *Engine) log(entry HistoryEntry) {
	entry.At = e.ms()
	e.history = append(e.history, entry)
}

func ptr[T any](v T) *T { return &v }

func (e *Engine) player(id string) *Player {
	for _, p := range e.players {
		if p.ID == id {
			return p
		}
	}
	return nil
}

// ---- players ----

// joinPlayer seats a new player; call through e.do.
func (e *Engine) joinPlayer(name string) (*Player, error) {
	name = strings.Join(strings.Fields(name), " ")
	if name == "" || utf8.RuneCountInString(name) > 32 {
		return nil, httpx.BadRequest("invalid_name", "Имя должно быть от 1 до 32 символов")
	}
	var out *Player
	err := func() error {
		for _, p := range e.players {
			if strings.EqualFold(p.Name, name) {
				return httpx.Conflict("name_taken", "Это имя уже занято")
			}
		}
		p := &Player{ID: "p_" + ids.Hex(4), Name: name, Token: ids.Token(), JoinedAt: e.ms()}
		e.players = append(e.players, p)
		e.log(HistoryEntry{Kind: "player_joined", By: "player", PlayerID: p.ID, Text: name})
		if e.phase == PhaseQuestion && e.q != nil {
			e.scheduleOpen(p, e.q.buzzStartsAt, e.gen)
		}
		e.changed(ScopeAll)
		cp := *p
		out = &cp
		return nil
	}()
	return out, err
}

// SetConnected marks a player's live connection.
func (e *Engine) SetConnected(id string, connected bool) {
	_ = e.do(func() error {
		if p := e.player(id); p != nil && p.connected != connected {
			p.connected = connected
			if connected {
				p.lastSeen = e.ms()
			}
			e.changed(ScopeAll)
		}
		return nil
	})
}

// SetDevice stores what the player's client reported in hello.
func (e *Engine) SetDevice(id string, d Device) {
	_ = e.do(func() error {
		if p := e.player(id); p != nil {
			p.Device = &d
			e.dirty = true
			e.changed(ScopeAdmins)
		}
		return nil
	})
}

// RecordRTT stores a ping round-trip.
func (e *Engine) RecordRTT(id string, rtt int64) {
	_ = e.do(func() error {
		if p := e.player(id); p != nil {
			p.rtts = append(p.rtts, rtt)
			if len(p.rtts) > 10 {
				p.rtts = p.rtts[len(p.rtts)-10:]
			}
			p.lastSeen = e.ms()
			e.changed(ScopeAdmins)
		}
		return nil
	})
}

func rttStats(rtts []int64) (last, avg, jitter *int64) {
	if len(rtts) == 0 {
		return nil, nil, nil
	}
	var sum int64
	for _, r := range rtts {
		sum += r
	}
	a := sum / int64(len(rtts))
	var dev int64
	for _, r := range rtts {
		d := r - a
		if d < 0 {
			d = -d
		}
		dev += d
	}
	return ptr(rtts[len(rtts)-1]), ptr(a), ptr(dev / int64(len(rtts)))
}

func (e *Engine) effectiveOffset(p *Player) int {
	off := p.BuzzOffsetMs
	if e.settings.AutoLatencyCompensation {
		if _, avg, _ := rttStats(p.rtts); avg != nil {
			off -= int(*avg / 2)
		}
	}
	return off
}

func (e *Engine) attempted(id string) bool {
	return e.q != nil && slices.Contains(e.q.attempted, id)
}

func (e *Engine) removePlayer(id string) {
	if p := e.player(id); p != nil {
		e.dropAvatarFile(p.Avatar)
	}
	e.players = slices.DeleteFunc(e.players, func(p *Player) bool { return p.ID == id })
	if e.chooserID == id {
		e.chooserID = ""
	}
	if e.q == nil {
		return
	}
	delete(e.q.openAt, id)
	delete(e.q.opened, id)
	if e.final != nil {
		e.finalDrop(id)
		return
	}
	switch {
	case e.q.solo == id && (e.phase == PhaseQuestion || e.phase == PhaseAnswering):
		e.q.answering = ""
		e.reveal()
	case e.q.answering == id:
		e.q.answering = ""
		e.q.typed = ""
		e.afterFailedAttempt()
	case e.phase == PhaseAuction && e.auction != nil:
		a := e.auction
		if a.bidder == id {
			a.bidder, a.allIn, a.high = "", false, e.q.q.Value
		}
		a.passed = slices.DeleteFunc(a.passed, func(s string) bool { return s == id })
		if a.turn == id || a.turn == "" {
			e.auctionNext(id)
		}
	case e.phase == PhaseCatTransfer && e.chooserID == "":
		if others := e.connectedOthers(""); len(others) > 0 {
			e.chooserID = others[0].ID
		}
	}
}

// ---- question mechanics ----

func (e *Engine) findQuestion(id int64) (*packs.Question, string) {
	if e.pack == nil || e.roundIndex >= len(e.pack.Rounds) {
		return nil, ""
	}
	for _, c := range e.pack.Rounds[e.roundIndex].Categories {
		for i := range c.Questions {
			if c.Questions[i].ID == id {
				return &c.Questions[i], c.Name
			}
		}
	}
	return nil, ""
}

func (e *Engine) openQuestion(id int64, by string) error {
	qq, cat := e.findQuestion(id)
	if qq == nil {
		return errNotFound("Вопрос не найден в текущем раунде")
	}
	if e.played[id] {
		return errInvalid("Этот вопрос уже сыгран")
	}
	now := e.ms()
	e.q = &question{
		q:             *qq,
		categoryName:  cat,
		blocks:        packs.SplitBlocks(e.pack.ID, qq.Question),
		answerBlocks:  packs.SplitBlocks(e.pack.ID, qq.Answer),
		openedAt:      now,
		readingEndsAt: now + int64(e.readingSeconds(qq))*1000,
		stake:         qq.Value,
		modifier:      e.modifiers[id],
	}
	// A special question needs someone to hold it; without a chooser it plays normally.
	if e.q.modifier != "" && e.q.modifier != ModDouble && (e.chooserID == "" || e.player(e.chooserID) == nil) {
		e.q.modifier = ""
	}
	e.log(HistoryEntry{Kind: "question_opened", By: by, QuestionID: id, Value: ptr(qq.Value)})
	e.emit(Event{"kind": "question_opened", "questionId": id})
	if m := e.q.modifier; m != "" {
		e.log(HistoryEntry{Kind: "modifier", By: "system", QuestionID: id, Text: m})
		e.emit(Event{"kind": "modifier", "questionId": id, "modifier": m})
	}
	switch e.q.modifier {
	case "", ModDouble:
		if e.q.modifier == ModDouble {
			e.q.stake = 2 * qq.Value
		}
		e.phase = PhaseQuestion
		e.openWindow(e.q.readingEndsAt)
	default:
		e.startSpecial()
	}
	e.changed(ScopeAll)
	return nil
}

// openWindow schedules every eligible player's button relative to base and
// the end of the buzz window.
func (e *Engine) openWindow(base int64) {
	e.gen++
	gen := e.gen
	q := e.q
	q.openAt = map[string]int64{}
	q.opened = map[string]bool{}
	maxOff := 0
	for _, p := range e.players {
		if e.attempted(p.ID) {
			continue
		}
		maxOff = max(maxOff, e.effectiveOffset(p))
		e.scheduleOpen(p, base, gen)
	}
	q.buzzStartsAt = base
	q.buzzEndsAt = base + int64(maxOff) + int64(e.settings.BuzzSeconds)*1000
	e.after(q.buzzEndsAt, gen, func() {
		if e.phase == PhaseQuestion {
			e.log(HistoryEntry{Kind: "timeout", By: "system", QuestionID: e.q.q.ID})
			e.emit(Event{"kind": "timeout"})
			e.reveal()
			e.changed(ScopeAll)
		}
	})
}

func (e *Engine) scheduleOpen(p *Player, base int64, gen int) {
	q := e.q
	at := max(base+int64(e.effectiveOffset(p)), q.openedAt, e.ms())
	q.openAt[p.ID] = at
	id := p.ID
	e.after(at, gen, func() {
		if e.phase == PhaseQuestion && e.q != nil {
			e.q.opened[id] = true
			e.changed(ScopeAll)
		}
	})
}

// after runs fn under the lock at the given server time, unless the
// generation moved on in the meantime.
func (e *Engine) after(at int64, gen int, fn func()) {
	d := time.Duration(at-e.ms()) * time.Millisecond
	time.AfterFunc(max(d, 0), func() {
		_ = e.do(func() error {
			if e.gen == gen {
				fn()
			}
			return nil
		})
	})
}

func (e *Engine) reveal() {
	e.gen++
	e.auction = nil
	e.phase = PhaseReveal
	if e.q != nil {
		e.played[e.q.q.ID] = true
		e.q.answering = ""
	}
}

// afterFailedAttempt reopens the buttons for whoever is left, or reveals.
func (e *Engine) afterFailedAttempt() {
	if e.q != nil && e.q.solo != "" {
		e.reveal()
		return
	}
	for _, p := range e.players {
		if p.connected && !e.attempted(p.ID) {
			e.phase = PhaseQuestion
			e.openWindow(e.ms())
			return
		}
	}
	e.reveal()
}

func (e *Engine) roundComplete() bool {
	if e.pack == nil || e.roundIndex >= len(e.pack.Rounds) {
		return true
	}
	for _, c := range e.pack.Rounds[e.roundIndex].Categories {
		for _, q := range c.Questions {
			if !e.played[q.ID] {
				return false
			}
		}
	}
	return true
}

func (e *Engine) startRound(index int) {
	if e.pack != nil && index < len(e.pack.Rounds) && e.pack.Rounds[index].Kind == packs.RoundFinal {
		e.startFinal(index)
		return
	}
	e.gen++
	e.q = nil
	e.auction = nil
	e.final = nil
	e.roundIndex = index
	e.phase = PhaseBoard
	e.assignModifiers()
	e.log(HistoryEntry{Kind: "round_started", By: "host", Value: ptr(index)})
	e.emit(Event{"kind": "round_started", "index": index})
}

func (e *Engine) pickChooser() {
	var online []*Player
	for _, p := range e.players {
		if p.connected {
			online = append(online, p)
		}
	}
	switch {
	case len(online) > 0:
		e.chooserID = online[rand.IntN(len(online))].ID
	case len(e.players) > 0:
		e.chooserID = e.players[0].ID
	default:
		e.chooserID = ""
	}
}

// LoadedPackID is the pack the game uses, or "".
func (e *Engine) LoadedPackID() string {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.pack == nil {
		return ""
	}
	return e.pack.ID
}
