package game

import "svoy-igra/app/packs"

// View builds the state for one receiver; limited hides the PIN and link
// (a screen that joined from the public list).
func (e *Engine) View(role Role, playerID string, limited bool) View {
	e.mu.Lock()
	defer e.mu.Unlock()
	now := e.ms()
	v := View{
		ServerNow: now,
		Role:      role,
		Phase:     e.phase,
		Game: GameBrief{
			Title:     e.title,
			HostTaken: e.hostTaken(), HostConnected: e.hostSockets > 0,
			HostAvatarURL: e.avatarURL(e.hostAvatar),
		},
		Players:            make([]PlayerView, 0, len(e.players)),
		AttemptedPlayerIDs: []string{},
	}
	if !limited {
		v.Game.PIN, v.Game.Link = ptr(e.pin), ptr(e.link())
	}
	for _, p := range e.players {
		pv := PlayerView{ID: p.ID, Name: p.Name, Score: p.Score, Connected: p.connected, AvatarURL: e.avatarURL(p.Avatar)}
		if role == RoleAdmin {
			pv.Admin = e.adminInfo(p)
		}
		v.Players = append(v.Players, pv)
	}
	if e.chooserID != "" {
		v.ChooserID = ptr(e.chooserID)
	}
	if role == RoleHost || role == RoleAdmin {
		v.Settings = ptr(e.settings)
	}
	if e.q != nil {
		v.AttemptedPlayerIDs = append(v.AttemptedPlayerIDs, e.q.attempted...)
		if e.q.answering != "" {
			v.AnsweringPlayerID = ptr(e.q.answering)
		}
		if e.q.result != nil {
			v.LastResult = ptr(*e.q.result)
		}
	}
	if role == RoleAdmin {
		v.Admins = ptr(e.adminConns)
	}

	if e.pack != nil {
		v.Pack = &PackRef{ID: e.pack.ID, Title: e.pack.Title}
		if e.roundIndex < len(e.pack.Rounds) && e.phase != PhaseLobby {
			r := e.pack.Rounds[e.roundIndex]
			v.Round = &RoundView{Index: e.roundIndex, Name: r.Name, Total: len(e.pack.Rounds), Kind: e.roundKind()}
		}
		if role != RoleAdmin && e.roundIndex < len(e.pack.Rounds) && e.phase != PhaseLobby && e.roundKind() != "final" {
			r := e.pack.Rounds[e.roundIndex]
			v.Board = make([]BoardCategory, 0, len(r.Categories))
			for _, c := range r.Categories {
				bc := BoardCategory{ID: c.ID, Name: c.Name, Questions: make([]BoardCell, 0, len(c.Questions))}
				for _, q := range c.Questions {
					bc.Questions = append(bc.Questions, BoardCell{ID: q.ID, Value: q.Value, Played: e.played[q.ID]})
				}
				v.Board = append(v.Board, bc)
			}
		}
	}

	if q := e.q; q != nil && role != RoleAdmin {
		qv := &QuestionView{ID: q.q.ID, CategoryName: q.categoryName, Value: q.q.Value, Stake: q.stake, Blocks: q.blocks}
		if q.modifier != "" {
			qv.Modifier = ptr(q.modifier)
		}
		if q.hidden {
			qv.Blocks = []packs.Block{}
		}
		if role == RoleHost || e.phase == PhaseReveal || e.phase == PhaseFinalReveal {
			qv.AnswerBlocks = q.answerBlocks
			qv.Comment = ptr(q.q.Comment)
		}
		v.Question = qv
		if q.solo != "" && (e.phase == PhaseQuestion || e.phase == PhaseAnswering) {
			v.SoloPlayerID = ptr(q.solo)
		}
		if e.phase == PhaseQuestion || e.phase == PhaseAnswering {
			v.ReadingStartsAt = ptr(q.openedAt)
			v.ReadingEndsAt = ptr(q.readingEndsAt)
			if q.solo == "" {
				v.BuzzStartsAt = ptr(q.buzzStartsAt)
				v.BuzzEndsAt = ptr(q.buzzEndsAt)
			}
		}
		if role == RoleHost && e.phase == PhaseAnswering {
			v.TypedAnswer = ptr(q.typed)
		}
	}

	if a := e.auction; a != nil && e.phase == PhaseAuction && role != RoleAdmin {
		av := &AuctionView{HighBid: a.high, HighBidderID: a.bidder, AllIn: a.allIn, PassedPlayerIDs: append([]string{}, a.passed...)}
		if a.turn != "" {
			av.TurnPlayerID = ptr(a.turn)
		}
		v.Auction = av
	}
	if e.final != nil && e.phase.isFinal() {
		v.Final = e.finalView(role, playerID)
	}

	if role == RolePlayer {
		if p := e.player(playerID); p != nil {
			v.Me = e.meView(p, now)
		}
	}
	return v
}

func (e *Engine) finalView(role Role, viewer string) *FinalView {
	f := e.final
	fv := &FinalView{Themes: []FinalTheme{}, Participants: []FinalParticipant{}}
	for _, t := range f.themes {
		fv.Themes = append(fv.Themes, FinalTheme{ID: t.ID, Name: t.Name, Removed: f.removed[t.ID]})
	}
	if f.remover != "" {
		fv.RemoverID = ptr(f.remover)
	}
	if f.answerEndsAt > 0 && e.phase == PhaseFinalQuestion {
		fv.AnswerStartsAt = ptr(f.answerStartsAt)
		fv.AnswerEndsAt = ptr(f.answerEndsAt)
	}
	open := e.phase == PhaseFinalReveal
	for _, id := range f.finalists {
		fp := FinalParticipant{PlayerID: id}
		bet, hasBet := f.bets[id]
		ans, hasAns := f.answers[id]
		correct, judged := f.judged[id]
		fp.HasBet, fp.HasAnswer = hasBet, hasAns
		see := role == RoleHost || id == viewer || judged || open
		if hasBet && see {
			fp.Bet = ptr(bet)
		}
		if hasAns && see {
			fp.Answer = ptr(ans)
		}
		if judged {
			fp.Correct = ptr(correct)
		}
		fv.Participants = append(fv.Participants, fp)
	}
	return fv
}

func (e *Engine) meView(p *Player, now int64) *MeView {
	me := &MeView{ID: p.ID, Name: p.Name, Score: p.Score, Buzzer: "hidden"}
	me.CanSelect = e.phase == PhaseBoard && e.chooserID == p.ID
	me.CanGiveCat = e.phase == PhaseCatTransfer && e.chooserID == p.ID
	me.CanBid = e.phase == PhaseAuction && e.auction != nil && e.auction.turn == p.ID
	if e.final != nil {
		me.Finalist = e.isFinalist(p.ID)
		me.CanRemoveTheme = e.phase == PhaseFinalThemes && e.final.remover == p.ID
		me.CanBet = e.phase == PhaseFinalBets && me.Finalist
		me.CanAnswerFinal = e.phase == PhaseFinalQuestion && me.Finalist && now <= e.final.answerEndsAt
	}
	q := e.q
	if q == nil {
		return me
	}
	if q.solo != "" && (e.phase == PhaseQuestion || e.phase == PhaseAnswering) {
		switch {
		case q.solo != p.ID:
			me.Buzzer = "closed"
		case e.phase == PhaseAnswering:
			me.Buzzer = "answering"
			me.CanType = true
		default:
			me.Buzzer = "waiting"
			me.BuzzOpensAt = ptr(q.readingEndsAt)
		}
		return me
	}
	switch e.phase {
	case PhaseQuestion:
		at, scheduled := q.openAt[p.ID]
		switch {
		case e.attempted(p.ID):
			me.Buzzer = "used"
		case !scheduled || now > q.buzzEndsAt:
			me.Buzzer = "closed"
		case q.opened[p.ID]:
			me.Buzzer = "open"
		default:
			me.Buzzer = "waiting"
		}
		if scheduled {
			me.BuzzOpensAt = ptr(at)
		}
	case PhaseAnswering:
		switch {
		case q.answering == p.ID:
			me.Buzzer = "answering"
			me.CanType = true
		case e.attempted(p.ID):
			me.Buzzer = "used"
		default:
			me.Buzzer = "closed"
		}
	}
	return me
}

func (e *Engine) adminInfo(p *Player) *AdminPlayerInfo {
	last, avg, jitter := rttStats(p.rtts)
	info := &AdminPlayerInfo{
		RttMs: last, RttAvgMs: avg, JitterMs: jitter,
		BuzzOffsetMs:      p.BuzzOffsetMs,
		EffectiveOffsetMs: e.effectiveOffset(p),
		Stats: AdminStats{
			Correct: p.Stats.Correct, Wrong: p.Stats.Wrong, Buzzes: p.Stats.Buzzes,
			BestReactionMs: p.Stats.BestReactionMs,
		},
	}
	if p.Device != nil {
		info.Device = *p.Device
	}
	if p.lastSeen > 0 {
		info.LastSeenAt = ptr(p.lastSeen)
	}
	if p.Stats.Buzzes > 0 {
		info.Stats.AvgReactionMs = ptr(p.Stats.TotalReactionMs / int64(p.Stats.Buzzes))
	}
	return info
}
