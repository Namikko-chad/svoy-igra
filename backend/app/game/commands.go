package game

import (
	"encoding/json"
	"unicode/utf8"
)

// Command applies one client command sent with token.
func (e *Engine) Command(role Role, playerID, token, typ string, data json.RawMessage) error {
	if typ == "leave" {
		return e.do(func() error {
			if e.closed {
				return ErrGameNotFound
			}
			e.leave(role, playerID, token)
			return nil
		})
	}
	var h cmd
	switch role {
	case RolePlayer:
		h = playerCommands[typ]
	case RoleHost:
		h = hostCommands[typ]
	case RoleAdmin:
		h = adminCommands[typ]
	}
	if h == nil {
		return errForbidden("Команда " + typ + " недоступна для роли " + string(role))
	}
	return e.do(func() error {
		if e.closed {
			return errNotFound("Игра закрыта")
		}
		return h(e, role, playerID, data)
	})
}

func decode(data json.RawMessage, v any) error {
	if len(data) == 0 {
		data = []byte("{}")
	}
	if err := json.Unmarshal(data, v); err != nil {
		return errInvalid("Некорректные данные команды")
	}
	return nil
}

type cmd = func(*Engine, Role, string, json.RawMessage) error

var playerCommands = map[string]cmd{
	"select_question":    (*Engine).cmdSelectQuestion,
	"buzz":               (*Engine).cmdBuzz,
	"submit_answer":      (*Engine).cmdSubmitAnswer,
	"give_cat":           (*Engine).cmdGiveCat,
	"auction_bid":        (*Engine).cmdAuctionBid,
	"auction_all_in":     (*Engine).cmdAuctionAllIn,
	"auction_pass":       (*Engine).cmdAuctionPass,
	"final_remove_theme": (*Engine).cmdFinalRemoveTheme,
	"final_bet":          (*Engine).cmdFinalBet,
	"final_answer":       (*Engine).cmdFinalAnswer,
}

var hostCommands = map[string]cmd{
	"start_game":          (*Engine).cmdStartGame,
	"select_question":     (*Engine).cmdSelectQuestion,
	"set_chooser":         (*Engine).cmdSetChooser,
	"judge":               (*Engine).cmdJudge,
	"skip_question":       (*Engine).cmdSkip,
	"continue":            (*Engine).cmdContinue,
	"next_round":          (*Engine).cmdNextRound,
	"set_round":           (*Engine).cmdSetRound,
	"finish_game":         (*Engine).cmdFinish,
	"reset_game":          (*Engine).cmdReset,
	"update_settings":     (*Engine).cmdUpdateSettings,
	"kick_player":         (*Engine).cmdKick,
	"give_cat":            (*Engine).cmdGiveCat,
	"auction_close":       (*Engine).cmdAuctionClose,
	"final_remove_theme":  (*Engine).cmdFinalRemoveTheme,
	"final_close_bets":    (*Engine).cmdFinalCloseBets,
	"final_close_answers": (*Engine).cmdFinalCloseAnswers,
	"final_judge":         (*Engine).cmdFinalJudge,
}

var adminCommands = map[string]cmd{
	"load_pack":       (*Engine).cmdLoadPack,
	"update_settings": (*Engine).cmdUpdateSettings,
	"update_game":     (*Engine).cmdUpdateGame,
	"adjust_score":    (*Engine).cmdAdjustScore,
	"set_score":       (*Engine).cmdSetScore,
	"set_buzz_offset": (*Engine).cmdSetBuzzOffset,
	"kick_player":     (*Engine).cmdKick,
	"reset_game":      (*Engine).cmdReset,
	"close_game":      (*Engine).cmdCloseGame,
	"clear_avatar":    (*Engine).cmdClearAvatar,
}

// ---- player ----

func (e *Engine) cmdSelectQuestion(role Role, pid string, data json.RawMessage) error {
	var in struct {
		QuestionID int64 `json:"questionId"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseBoard {
		return errPhase("Сейчас нельзя выбрать вопрос")
	}
	if role == RolePlayer && e.chooserID != pid {
		return errForbidden("Сейчас выбирает другой игрок")
	}
	return e.openQuestion(in.QuestionID, string(role))
}

func (e *Engine) cmdBuzz(_ Role, pid string, _ json.RawMessage) error {
	if e.phase != PhaseQuestion || e.q == nil {
		return errPhase("Сейчас нельзя отвечать")
	}
	q := e.q
	if q.solo != "" {
		return errPhase("На этот вопрос отвечает один игрок")
	}
	now := e.ms()
	openAt, scheduled := q.openAt[pid]
	if e.attempted(pid) || !scheduled || now > q.buzzEndsAt {
		return errPhase("Кнопка закрыта")
	}
	if !q.opened[pid] && now < openAt {
		return errPhase("Кнопка ещё не открылась")
	}
	p := e.player(pid)
	if p == nil {
		return errNotFound("Игрок не найден")
	}
	reaction := max(now-openAt, 0)
	p.Stats.Buzzes++
	p.Stats.TotalReactionMs += reaction
	if p.Stats.BestReactionMs == nil || reaction < *p.Stats.BestReactionMs {
		p.Stats.BestReactionMs = ptr(reaction)
	}
	e.gen++ // the buzz-window timeout no longer applies
	q.answering = pid
	q.typed = ""
	e.phase = PhaseAnswering
	e.log(HistoryEntry{Kind: "buzz", By: "player", PlayerID: pid, QuestionID: q.q.ID, ReactionMs: ptr(reaction)})
	e.emit(Event{"kind": "buzz", "playerId": pid, "reactionMs": reaction})
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdSubmitAnswer(_ Role, pid string, data json.RawMessage) error {
	var in struct {
		Text string `json:"text"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseAnswering || e.q == nil || e.q.answering != pid {
		return errPhase("Сейчас отвечаете не вы")
	}
	if utf8.RuneCountInString(in.Text) > 200 {
		return errInvalid("Ответ длиннее 200 символов")
	}
	e.q.typed = in.Text
	e.changed(ScopeAll)
	return nil
}

// ---- host ----

func (e *Engine) cmdLoadPack(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		PackID string `json:"packId"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseLobby && e.phase != PhaseFinished {
		return errPhase("Пак можно сменить только в лобби или после окончания игры")
	}
	p, err := e.store.Get(in.PackID)
	if err != nil {
		return errNotFound("Пак не найден")
	}
	if len(p.Rounds) == 0 {
		return errInvalid("В паке нет ни одного раунда")
	}
	e.gen++
	e.pack = p
	e.q = nil
	e.auction = nil
	e.final = nil
	e.modifiers = map[int64]string{}
	e.log(HistoryEntry{Kind: "pack_loaded", By: "admin", Text: p.Title})
	e.played = map[int64]bool{}
	e.roundIndex = 0
	e.phase = PhaseLobby
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdStartGame(Role, string, json.RawMessage) error {
	if e.phase != PhaseLobby {
		return errPhase("Игра уже идёт")
	}
	if e.pack == nil {
		return errInvalid("Сначала выберите пак")
	}
	e.log(HistoryEntry{Kind: "game_started", By: "host"})
	e.pickChooser()
	e.startRound(0)
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdSetChooser(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		PlayerID string `json:"playerId"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase == PhaseLobby {
		return errPhase("Игра ещё не началась")
	}
	if e.player(in.PlayerID) == nil {
		return errNotFound("Игрок не найден")
	}
	e.chooserID = in.PlayerID
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdJudge(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		Correct *bool `json:"correct"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if in.Correct == nil {
		return errInvalid("Не указано, верен ли ответ")
	}
	if e.phase != PhaseAnswering || e.q == nil {
		return errPhase("Сейчас никто не отвечает")
	}
	q := e.q
	p := e.player(q.answering)
	value := q.stake
	delta := 0
	if *in.Correct {
		delta = value
		p.Stats.Correct++
		e.chooserID = p.ID
	} else {
		p.Stats.Wrong++
		switch {
		case q.modifier == ModCat || q.modifier == ModAuction:
			delta = -value
		case q.modifier == ModNoRisk:
		case e.settings.WrongPenalty:
			delta = -value
		}
		q.attempted = append(q.attempted, p.ID)
	}
	p.Score += delta
	q.result = &Result{PlayerID: p.ID, Correct: *in.Correct, Delta: delta}
	e.log(HistoryEntry{Kind: "judged", By: "host", PlayerID: p.ID, QuestionID: q.q.ID, Value: ptr(value), Delta: ptr(delta), Correct: in.Correct, Text: q.typed})
	e.emit(Event{"kind": "judged", "playerId": p.ID, "correct": *in.Correct, "delta": delta})
	q.answering = ""
	q.typed = ""
	if *in.Correct {
		e.reveal()
	} else {
		e.afterFailedAttempt()
	}
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdSkip(Role, string, json.RawMessage) error {
	if e.phase != PhaseQuestion && e.phase != PhaseAnswering && e.phase != PhaseCatTransfer && e.phase != PhaseAuction {
		return errPhase("Нет открытого вопроса")
	}
	e.log(HistoryEntry{Kind: "skipped", By: "host", QuestionID: e.q.q.ID})
	e.reveal()
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdContinue(Role, string, json.RawMessage) error {
	if e.phase == PhaseFinalReveal {
		e.final = nil
		e.q = nil
		if e.roundIndex+1 < len(e.pack.Rounds) {
			e.phase = PhaseRoundEnd
		} else {
			e.finish()
		}
		e.changed(ScopeAll)
		return nil
	}
	if e.phase != PhaseReveal {
		return errPhase("Нечего продолжать")
	}
	e.gen++
	e.q = nil
	if e.roundComplete() {
		e.phase = PhaseRoundEnd
	} else {
		e.phase = PhaseBoard
	}
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) finish() {
	e.gen++
	e.q = nil
	e.auction = nil
	e.final = nil
	e.phase = PhaseFinished
	e.log(HistoryEntry{Kind: "game_finished", By: "host"})
	e.emit(Event{"kind": "game_finished"})
}

func (e *Engine) cmdNextRound(Role, string, json.RawMessage) error {
	if e.phase != PhaseBoard && e.phase != PhaseRoundEnd && e.phase != PhaseFinalThemes {
		return errPhase("Сначала закройте текущий вопрос")
	}
	if e.roundIndex+1 < len(e.pack.Rounds) {
		e.startRound(e.roundIndex + 1)
	} else {
		e.finish()
	}
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdSetRound(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		Index *int `json:"index"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if e.phase != PhaseBoard && e.phase != PhaseRoundEnd && e.phase != PhaseFinalThemes {
		return errPhase("Сначала закройте текущий вопрос")
	}
	if in.Index == nil || *in.Index < 0 || *in.Index >= len(e.pack.Rounds) {
		return errInvalid("Нет такого раунда")
	}
	e.startRound(*in.Index)
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdFinish(Role, string, json.RawMessage) error {
	if e.phase == PhaseLobby || e.phase == PhaseFinished {
		return errPhase("Игра не идёт")
	}
	e.finish()
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdReset(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		KeepPlayers bool `json:"keepPlayers"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	e.gen++
	e.q = nil
	e.auction = nil
	e.final = nil
	e.modifiers = map[int64]string{}
	e.phase = PhaseLobby
	e.roundIndex = 0
	e.chooserID = ""
	e.played = map[int64]bool{}
	e.history = nil
	if in.KeepPlayers {
		for _, p := range e.players {
			p.Score = 0
			p.Stats = Stats{}
		}
	} else {
		tokens := make([]string, 0, len(e.players))
		for _, p := range e.players {
			tokens = append(tokens, p.Token)
		}
		for _, p := range e.players {
			e.dropAvatarFile(p.Avatar)
		}
		e.players = nil
		e.revoke(tokens, 4001)
	}
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdUpdateSettings(role Role, _ string, data json.RawMessage) error {
	var in struct {
		ReadingSeconds          *int            `json:"readingSeconds"`
		BuzzSeconds             *int            `json:"buzzSeconds"`
		WrongPenalty            *bool           `json:"wrongPenalty"`
		AutoLatencyCompensation *bool           `json:"autoLatencyCompensation"`
		Modifiers               *ModifierCounts `json:"modifiers"`
		FinalSeconds            *int            `json:"finalSeconds"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	s := e.settings
	if role == RoleHost && in.AutoLatencyCompensation != nil {
		return errForbidden("Компенсацию задержки настраивает администратор")
	}
	if in.ReadingSeconds != nil {
		if *in.ReadingSeconds < 1 || *in.ReadingSeconds > 120 {
			return errInvalid("Время чтения: от 1 до 120 секунд")
		}
		s.ReadingSeconds = *in.ReadingSeconds
	}
	if in.BuzzSeconds != nil {
		if *in.BuzzSeconds < 3 || *in.BuzzSeconds > 300 {
			return errInvalid("Время на нажатие: от 3 до 300 секунд")
		}
		s.BuzzSeconds = *in.BuzzSeconds
	}
	if in.WrongPenalty != nil {
		s.WrongPenalty = *in.WrongPenalty
	}
	if in.AutoLatencyCompensation != nil {
		s.AutoLatencyCompensation = *in.AutoLatencyCompensation
	}
	if m := in.Modifiers; m != nil {
		for _, n := range []int{m.Cat, m.Auction, m.NoRisk, m.Double} {
			if n < 0 || n > 5 {
				return errInvalid("Модификаторов каждого типа — от 0 до 5 на раунд")
			}
		}
		s.Modifiers = *m
	}
	if in.FinalSeconds != nil {
		if *in.FinalSeconds < 10 || *in.FinalSeconds > 300 {
			return errInvalid("Время на ответ в финале: от 10 до 300 секунд")
		}
		s.FinalSeconds = *in.FinalSeconds
	}
	e.settings = s
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdKick(role Role, _ string, data json.RawMessage) error {
	var in struct {
		PlayerID string `json:"playerId"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	p := e.player(in.PlayerID)
	if p == nil {
		return errNotFound("Игрок не найден")
	}
	e.removePlayer(in.PlayerID)
	e.log(HistoryEntry{Kind: "player_kicked", By: string(role), PlayerID: in.PlayerID})
	e.revoke([]string{p.Token}, 4003)
	e.changed(ScopeAll)
	return nil
}

// ---- admin ----

func (e *Engine) cmdAdjustScore(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		PlayerID string `json:"playerId"`
		Delta    *int   `json:"delta"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	p := e.player(in.PlayerID)
	if p == nil {
		return errNotFound("Игрок не найден")
	}
	if in.Delta == nil || *in.Delta < -1_000_000 || *in.Delta > 1_000_000 {
		return errInvalid("Некорректное изменение счёта")
	}
	p.Score += *in.Delta
	e.log(HistoryEntry{Kind: "score_adjusted", By: "admin", PlayerID: p.ID, Delta: in.Delta})
	e.emit(Event{"kind": "score_adjusted", "playerId": p.ID, "delta": *in.Delta})
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdSetScore(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		PlayerID string `json:"playerId"`
		Score    *int   `json:"score"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	p := e.player(in.PlayerID)
	if p == nil {
		return errNotFound("Игрок не найден")
	}
	if in.Score == nil || *in.Score < -10_000_000 || *in.Score > 10_000_000 {
		return errInvalid("Некорректный счёт")
	}
	delta := *in.Score - p.Score
	p.Score = *in.Score
	e.log(HistoryEntry{Kind: "score_set", By: "admin", PlayerID: p.ID, Value: in.Score, Delta: ptr(delta)})
	e.emit(Event{"kind": "score_adjusted", "playerId": p.ID, "delta": delta})
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdSetBuzzOffset(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		PlayerID string `json:"playerId"`
		OffsetMs *int   `json:"offsetMs"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	p := e.player(in.PlayerID)
	if p == nil {
		return errNotFound("Игрок не найден")
	}
	if in.OffsetMs == nil || *in.OffsetMs < -5000 || *in.OffsetMs > 10000 {
		return errInvalid("Смещение должно быть от −5000 до 10000 мс")
	}
	p.BuzzOffsetMs = *in.OffsetMs
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdUpdateGame(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		Title    *string `json:"title"`
		AdminPin *string `json:"adminPin"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if in.Title != nil {
		t, err := ValidateTitle(*in.Title)
		if err != nil {
			return errInvalid("Название игры — не длиннее 60 символов")
		}
		if t == "" {
			t = "Игра " + e.pin
		}
		e.title = t
	}
	if in.AdminPin != nil {
		if ValidateAdminPin(*in.AdminPin) != nil {
			return errInvalid("PIN администратора — от 4 до 8 цифр")
		}
		e.setAdminPin(*in.AdminPin)
	}
	e.changed(ScopeAll)
	return nil
}

func (e *Engine) cmdCloseGame(Role, string, json.RawMessage) error {
	e.closeLocked()
	return nil
}
