package game

import (
	"encoding/json"
	"slices"
	"sort"
	"unicode/utf8"

	"svoy-igra/app/packs"
)

// finalState is the final round in progress (protocol §4.6).
type finalState struct {
	themes         []packs.Category // themes that have a question
	removed        map[int64]bool
	order          []string // removal order: lowest score first
	turn           int      // index into order
	remover        string
	finalists      []string
	bets           map[string]int
	answers        map[string]string
	judged         map[string]bool // playerId → correct
	answerStartsAt int64
	answerEndsAt   int64
}

func (e *Engine) isFinalist(pid string) bool {
	return e.final != nil && slices.Contains(e.final.finalists, pid)
}

// startFinal begins the final round at index.
func (e *Engine) startFinal(index int) {
	e.gen++
	e.q = nil
	e.auction = nil
	e.modifiers = map[int64]string{}
	e.roundIndex = index
	f := &finalState{removed: map[int64]bool{}, bets: map[string]int{}, answers: map[string]string{}, judged: map[string]bool{}}
	for _, c := range e.pack.Rounds[index].Categories {
		if len(c.Questions) > 0 {
			f.themes = append(f.themes, c)
		}
	}
	var finalists []*Player
	for _, p := range e.players {
		if p.Score > 0 {
			finalists = append(finalists, p)
			f.finalists = append(f.finalists, p.ID)
		}
	}
	e.log(HistoryEntry{Kind: "final_started", By: "host", Value: ptr(index)})
	e.emit(Event{"kind": "round_started", "index": index})
	if len(f.finalists) == 0 || len(f.themes) == 0 {
		e.final = nil
		e.finish()
		return
	}
	sort.SliceStable(finalists, func(i, j int) bool { return finalists[i].Score < finalists[j].Score })
	for _, p := range finalists {
		f.order = append(f.order, p.ID)
	}
	e.final = f
	e.phase = PhaseFinalThemes
	if len(f.themes) == 1 {
		e.startFinalBets()
		return
	}
	f.remover = f.order[0]
}

func (e *Engine) remainingThemes() []packs.Category {
	var out []packs.Category
	for _, t := range e.final.themes {
		if !e.final.removed[t.ID] {
			out = append(out, t)
		}
	}
	return out
}

// buildFinalQuestion prepares e.q from the last remaining theme.
func (e *Engine) buildFinalQuestion() {
	rest := e.remainingThemes()
	if len(rest) == 0 {
		return
	}
	t := rest[0]
	qq := t.Questions[0]
	e.q = &question{
		q: qq, categoryName: t.Name, hidden: true,
		blocks:       packs.SplitBlocks(e.pack.ID, qq.Question),
		answerBlocks: packs.SplitBlocks(e.pack.ID, qq.Answer),
		openAt:       map[string]int64{}, opened: map[string]bool{},
	}
}

func (e *Engine) startFinalBets() {
	e.final.remover = ""
	e.buildFinalQuestion()
	e.phase = PhaseFinalBets
}

func (e *Engine) startFinalQuestion() {
	e.gen++
	gen := e.gen
	f := e.final
	for _, id := range f.finalists {
		if _, ok := f.bets[id]; !ok {
			f.bets[id] = 1
		}
	}
	e.q.hidden = false
	e.q.openedAt = e.ms()
	f.answerStartsAt = e.ms()
	f.answerEndsAt = f.answerStartsAt + int64(e.settings.FinalSeconds)*1000
	e.phase = PhaseFinalQuestion
	e.log(HistoryEntry{Kind: "question_opened", By: "system", QuestionID: e.q.q.ID})
	e.emit(Event{"kind": "question_opened", "questionId": e.q.q.ID})
	e.after(f.answerEndsAt, gen, func() {
		if e.phase == PhaseFinalQuestion {
			e.startFinalJudging()
			e.changed(ScopeAll)
		}
	})
}

func (e *Engine) startFinalJudging() {
	e.gen++
	e.phase = PhaseFinalJudging
	e.final.answerEndsAt = 0
	e.maybeFinalReveal()
}

func (e *Engine) maybeFinalReveal() {
	f := e.final
	for _, id := range f.finalists {
		if _, ok := f.judged[id]; !ok {
			return
		}
	}
	e.phase = PhaseFinalReveal
	if e.q != nil {
		e.played[e.q.q.ID] = true
	}
}

// finalDrop removes a player who left from the final and moves it on.
func (e *Engine) finalDrop(pid string) {
	f := e.final
	if f == nil || !slices.Contains(f.finalists, pid) {
		return
	}
	f.finalists = slices.DeleteFunc(f.finalists, func(s string) bool { return s == pid })
	f.order = slices.DeleteFunc(f.order, func(s string) bool { return s == pid })
	delete(f.bets, pid)
	delete(f.answers, pid)
	delete(f.judged, pid)
	if len(f.finalists) == 0 {
		e.final = nil
		e.finish()
		return
	}
	switch e.phase {
	case PhaseFinalThemes:
		if f.remover == pid {
			f.turn %= len(f.order)
			f.remover = f.order[f.turn]
		}
	case PhaseFinalBets:
		if len(f.bets) == len(f.finalists) {
			e.startFinalQuestion()
		}
	case PhaseFinalJudging:
		e.maybeFinalReveal()
	}
}

// ---- commands ----

func (e *Engine) cmdFinalRemoveTheme(role Role, pid string, data json.RawMessage) error {
	var in struct {
		ThemeID int64 `json:"themeId"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseFinalThemes || e.final == nil {
		return errPhase("Сейчас темы не убирают")
	}
	f := e.final
	if role == RolePlayer && pid != f.remover {
		return errForbidden("Сейчас тему убирает другой игрок")
	}
	if !slices.ContainsFunc(f.themes, func(c packs.Category) bool { return c.ID == in.ThemeID }) || f.removed[in.ThemeID] {
		return errInvalid("Эту тему убрать нельзя")
	}
	f.removed[in.ThemeID] = true
	e.log(HistoryEntry{Kind: "final_theme_removed", By: string(role), PlayerID: f.remover, QuestionID: in.ThemeID})
	e.emit(Event{"kind": "final_theme_removed", "playerId": f.remover, "themeId": in.ThemeID})
	if len(e.remainingThemes()) <= 1 {
		e.startFinalBets()
	} else {
		f.turn = (f.turn + 1) % len(f.order)
		f.remover = f.order[f.turn]
	}
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdFinalBet(_ Role, pid string, data json.RawMessage) error {
	var in struct {
		Amount int `json:"amount"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseFinalBets || !e.isFinalist(pid) {
		return errPhase("Сейчас нельзя сделать ставку")
	}
	p := e.player(pid)
	if in.Amount < 1 || in.Amount > p.Score {
		return errInvalid("Ставка — от 1 до вашего счёта")
	}
	e.final.bets[pid] = in.Amount
	e.log(HistoryEntry{Kind: "final_bet", By: "player", PlayerID: pid, Value: ptr(in.Amount)})
	if len(e.final.bets) == len(e.final.finalists) {
		e.startFinalQuestion()
	}
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdFinalCloseBets(Role, string, json.RawMessage) error {
	if e.phase != PhaseFinalBets {
		return errPhase("Ставки уже закрыты")
	}
	e.startFinalQuestion()
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdFinalAnswer(_ Role, pid string, data json.RawMessage) error {
	var in struct {
		Text string `json:"text"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseFinalQuestion || !e.isFinalist(pid) || e.ms() > e.final.answerEndsAt {
		return errPhase("Время на ответ вышло")
	}
	if utf8.RuneCountInString(in.Text) > 200 {
		return errInvalid("Ответ длиннее 200 символов")
	}
	e.final.answers[pid] = in.Text
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdFinalCloseAnswers(Role, string, json.RawMessage) error {
	if e.phase != PhaseFinalQuestion {
		return errPhase("Ответы уже закрыты")
	}
	e.startFinalJudging()
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdFinalJudge(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		PlayerID string `json:"playerId"`
		Correct  *bool  `json:"correct"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseFinalJudging {
		return errPhase("Сейчас финал не оценивают")
	}
	if in.Correct == nil || !e.isFinalist(in.PlayerID) {
		return errInvalid("Укажите финалиста и результат")
	}
	f := e.final
	if _, done := f.judged[in.PlayerID]; done {
		return errInvalid("Этот ответ уже оценён")
	}
	p := e.player(in.PlayerID)
	delta := f.bets[in.PlayerID]
	if !*in.Correct {
		delta = -delta
		p.Stats.Wrong++
	} else {
		p.Stats.Correct++
	}
	p.Score += delta
	f.judged[in.PlayerID] = *in.Correct
	e.log(HistoryEntry{Kind: "final_judged", By: "host", PlayerID: p.ID, Delta: ptr(delta), Correct: in.Correct, Text: f.answers[p.ID]})
	e.emit(Event{"kind": "final_judged", "playerId": p.ID, "correct": *in.Correct, "delta": delta})
	e.maybeFinalReveal()
	e.changed(ScopeAll)
	return nil
}
