package game

import (
	"encoding/json"
	"math/rand/v2"
	"slices"

	"svoy-igra/app/packs"
)

// Modifiers (protocol §4.5).
const (
	ModCat     = "cat"
	ModAuction = "auction"
	ModNoRisk  = "no_risk"
	ModDouble  = "double"
)

type ModifierCounts struct {
	Cat     int `json:"cat"`
	Auction int `json:"auction"`
	NoRisk  int `json:"noRisk"`
	Double  int `json:"double"`
}

type auctionState struct {
	turn    string
	high    int
	bidder  string
	allIn   bool
	passed  []string
	started string // the chooser: turns go round starting after them
}

func (e *Engine) roundKind() string {
	if e.pack == nil || e.roundIndex >= len(e.pack.Rounds) {
		return packs.RoundNormal
	}
	if e.pack.Rounds[e.roundIndex].Kind == packs.RoundFinal {
		return packs.RoundFinal
	}
	return packs.RoundNormal
}

// assignModifiers marks random unplayed cells of the current round.
func (e *Engine) assignModifiers() {
	e.modifiers = map[int64]string{}
	if e.pack == nil || e.roundKind() == packs.RoundFinal {
		return
	}
	var free []int64
	for _, c := range e.pack.Rounds[e.roundIndex].Categories {
		for _, q := range c.Questions {
			if !e.played[q.ID] {
				free = append(free, q.ID)
			}
		}
	}
	rand.Shuffle(len(free), func(i, j int) { free[i], free[j] = free[j], free[i] })
	m := e.settings.Modifiers
	for _, kind := range []struct {
		name string
		n    int
	}{{ModCat, m.Cat}, {ModAuction, m.Auction}, {ModNoRisk, m.NoRisk}, {ModDouble, m.Double}} {
		for i := 0; i < kind.n && len(free) > 0; i++ {
			e.modifiers[free[0]] = kind.name
			free = free[1:]
		}
	}
}

func (e *Engine) connectedOthers(id string) []*Player {
	var out []*Player
	for _, p := range e.players {
		if p.ID != id && p.connected {
			out = append(out, p)
		}
	}
	return out
}

// startSolo shows the question to everyone; after the reading time only
// pid answers. Nobody gets a button.
func (e *Engine) startSolo(pid string) {
	e.gen++
	gen := e.gen
	q := e.q
	q.solo = pid
	q.hidden = false
	now := e.ms()
	q.openedAt = now
	q.readingEndsAt = now + int64(e.readingSeconds(&q.q))*1000
	q.buzzStartsAt, q.buzzEndsAt = 0, 0
	q.openAt, q.opened = map[string]int64{}, map[string]bool{}
	e.auction = nil
	e.phase = PhaseQuestion
	e.after(q.readingEndsAt, gen, func() {
		if e.phase == PhaseQuestion && e.q != nil && e.q.solo != "" {
			e.gen++
			e.q.answering = e.q.solo
			e.q.typed = ""
			e.phase = PhaseAnswering
			e.changed(ScopeAll)
		}
	})
}

func (e *Engine) readingSeconds(q *packs.Question) int {
	if q.ReadingSeconds != nil {
		return *q.ReadingSeconds
	}
	return e.settings.ReadingSeconds
}

// startSpecial runs the modifier of a freshly opened question.
func (e *Engine) startSpecial() {
	q := e.q
	switch q.modifier {
	case ModNoRisk:
		q.stake = 2 * q.q.Value
		e.startSolo(e.chooserID)
	case ModCat:
		q.stake = q.q.Value
		q.hidden = true
		e.phase = PhaseCatTransfer
		if len(e.connectedOthers(e.chooserID)) == 0 {
			e.giveCat(e.chooserID, "system")
		}
	case ModAuction:
		q.stake = q.q.Value
		q.hidden = true
		e.phase = PhaseAuction
		e.auction = &auctionState{high: q.q.Value, bidder: e.chooserID, started: e.chooserID}
		e.auctionNext(e.chooserID)
	}
}

func (e *Engine) giveCat(to, by string) {
	e.log(HistoryEntry{Kind: "cat_given", By: by, PlayerID: to, QuestionID: e.q.q.ID})
	e.emit(Event{"kind": "cat_given", "fromId": e.chooserID, "toId": to})
	e.startSolo(to)
}

// auctionNext passes the turn to the next player after from who can still
// outbid; players who cannot are marked passed. With nobody left the
// auction is decided.
func (e *Engine) auctionNext(from string) {
	a := e.auction
	n := len(e.players)
	start := slices.IndexFunc(e.players, func(p *Player) bool { return p.ID == from })
	for i := 1; i <= n; i++ {
		p := e.players[(start+i+n)%n]
		if p.ID == a.bidder || slices.Contains(a.passed, p.ID) {
			continue
		}
		if !p.connected || p.Score <= a.high {
			a.passed = append(a.passed, p.ID)
			continue
		}
		a.turn = p.ID
		return
	}
	e.finishAuction("system")
}

func (e *Engine) finishAuction(by string) {
	a := e.auction
	a.turn = ""
	if a.bidder == "" && len(e.players) > 0 {
		a.bidder = e.players[0].ID
	}
	e.q.stake = a.high
	e.log(HistoryEntry{Kind: "auction_won", By: by, PlayerID: a.bidder, QuestionID: e.q.q.ID, Value: ptr(a.high)})
	e.emit(Event{"kind": "auction_won", "playerId": a.bidder, "amount": a.high})
	e.startSolo(a.bidder)
}

// ---- commands ----

func (e *Engine) cmdGiveCat(role Role, pid string, data json.RawMessage) error {
	var in struct {
		PlayerID string `json:"playerId"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseCatTransfer {
		return errPhase("Сейчас некому отдавать кота")
	}
	if role == RolePlayer && pid != e.chooserID {
		return errForbidden("Кота отдаёт выбравший вопрос")
	}
	target := e.player(in.PlayerID)
	if target == nil {
		return errNotFound("Игрок не найден")
	}
	if target.ID == e.chooserID && len(e.connectedOthers(e.chooserID)) > 0 {
		return errInvalid("Кота в мешке нужно отдать другому игроку")
	}
	e.giveCat(target.ID, string(role))
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) auctionTurn(role Role, pid string) error {
	if e.phase != PhaseAuction || e.auction == nil {
		return errPhase("Аукцион не идёт")
	}
	if role != RolePlayer || pid != e.auction.turn {
		return errForbidden("Сейчас ход другого игрока")
	}
	return nil
}

func (e *Engine) cmdAuctionBid(role Role, pid string, data json.RawMessage) error {
	var in struct {
		Amount int `json:"amount"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if err := e.auctionTurn(role, pid); err != nil {
		return err
	}
	a, p := e.auction, e.player(pid)
	if a.allIn {
		return errInvalid("После ва-банка можно только пойти ва-банк с бо́льшей суммой")
	}
	if in.Amount <= a.high || in.Amount > p.Score {
		return errInvalid("Ставка должна быть больше текущей и не больше вашего счёта")
	}
	return e.placeBid(p, in.Amount, false)
}

func (e *Engine) cmdAuctionAllIn(role Role, pid string, _ json.RawMessage) error {
	if err := e.auctionTurn(role, pid); err != nil {
		return err
	}
	p := e.player(pid)
	if p.Score <= e.auction.high {
		return errInvalid("Ваш счёт не больше текущей ставки")
	}
	return e.placeBid(p, p.Score, true)
}

func (e *Engine) placeBid(p *Player, amount int, allIn bool) error {
	a := e.auction
	a.high, a.bidder, a.allIn = amount, p.ID, allIn
	e.log(HistoryEntry{Kind: "auction_bid", By: "player", PlayerID: p.ID, QuestionID: e.q.q.ID, Value: ptr(amount)})
	e.emit(Event{"kind": "auction_bid", "playerId": p.ID, "amount": amount, "allIn": allIn})
	e.auctionNext(p.ID)
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdAuctionPass(role Role, pid string, _ json.RawMessage) error {
	if err := e.auctionTurn(role, pid); err != nil {
		return err
	}
	e.auction.passed = append(e.auction.passed, pid)
	e.log(HistoryEntry{Kind: "auction_pass", By: "player", PlayerID: pid, QuestionID: e.q.q.ID})
	e.emit(Event{"kind": "auction_pass", "playerId": pid})
	e.auctionNext(pid)
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdAuctionClose(Role, string, json.RawMessage) error {
	if e.phase != PhaseAuction || e.auction == nil {
		return errPhase("Аукцион не идёт")
	}
	e.finishAuction("host")
	e.changed(ScopeAll)
	return nil
}
