// Package game is the single in-memory game: rules, timers, role-filtered
// views and the JSON game file. It knows nothing about sockets — the ws hub
// feeds it commands and is told (through Hooks) when to push new state.
package game

import "svoy-igra/app/packs"

type Phase string

const (
	PhaseLobby     Phase = "lobby"
	PhaseBoard     Phase = "board"
	PhaseQuestion  Phase = "question"
	PhaseAnswering Phase = "answering"
	PhaseReveal    Phase = "reveal"
	PhaseRoundEnd  Phase = "round_end"
	PhaseFinished  Phase = "finished"

	PhaseCatTransfer   Phase = "cat_transfer"
	PhaseAuction       Phase = "auction"
	PhaseFinalThemes   Phase = "final_themes"
	PhaseFinalBets     Phase = "final_bets"
	PhaseFinalQuestion Phase = "final_question"
	PhaseFinalJudging  Phase = "final_judging"
	PhaseFinalReveal   Phase = "final_reveal"
)

func (p Phase) isFinal() bool {
	switch p {
	case PhaseFinalThemes, PhaseFinalBets, PhaseFinalQuestion, PhaseFinalJudging, PhaseFinalReveal:
		return true
	}
	return false
}

type Role string

const (
	RolePlayer Role = "player"
	RoleHost   Role = "host"
	RoleAdmin  Role = "admin"
	RoleScreen Role = "screen"
)

type Settings struct {
	ReadingSeconds          int            `json:"readingSeconds"`
	BuzzSeconds             int            `json:"buzzSeconds"`
	WrongPenalty            bool           `json:"wrongPenalty"`
	AutoLatencyCompensation bool           `json:"autoLatencyCompensation"`
	Modifiers               ModifierCounts `json:"modifiers"`
	FinalSeconds            int            `json:"finalSeconds"`
}

func DefaultSettings() Settings {
	return Settings{ReadingSeconds: 10, BuzzSeconds: 15, FinalSeconds: 60,
		Modifiers: ModifierCounts{Cat: 1, Auction: 1, NoRisk: 1, Double: 1}}
}

type Device struct {
	Platform   string `json:"platform"`
	Model      string `json:"model"`
	OS         string `json:"os"`
	AppVersion string `json:"appVersion"`
	UserAgent  string `json:"userAgent"`
	Screen     string `json:"screen"`
	IP         string `json:"ip"`
}

type Stats struct {
	Correct         int    `json:"correct"`
	Wrong           int    `json:"wrong"`
	Buzzes          int    `json:"buzzes"`
	TotalReactionMs int64  `json:"totalReactionMs"`
	BestReactionMs  *int64 `json:"bestReactionMs"`
}

// Player is a seat in the game. The exported fields are persisted; the rest
// is runtime telemetry.
type Player struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	Token        string  `json:"token"`
	Score        int     `json:"score"`
	JoinedAt     int64   `json:"joinedAt"`
	BuzzOffsetMs int     `json:"buzzOffsetMs"`
	Device       *Device `json:"device"`
	Stats        Stats   `json:"stats"`
	Avatar       string  `json:"avatar,omitempty"` // file in the game's avatar dir

	connected bool
	rtts      []int64
	lastSeen  int64
}

type PackRef struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

type HistoryEntry struct {
	At         int64  `json:"at"`
	Kind       string `json:"kind"`
	By         string `json:"by"`
	PlayerID   string `json:"playerId,omitempty"`
	QuestionID int64  `json:"questionId,omitempty"`
	Value      *int   `json:"value,omitempty"`
	Delta      *int   `json:"delta,omitempty"`
	Correct    *bool  `json:"correct,omitempty"`
	ReactionMs *int64 `json:"reactionMs,omitempty"`
	Text       string `json:"text,omitempty"`
}

// File is the game file (DATA_DIR/game.json, export/import).
type File struct {
	Format     string            `json:"format"`
	Version    int               `json:"version"`
	SavedAt    int64             `json:"savedAt"`
	Pack       *PackRef          `json:"pack"`
	Phase      Phase             `json:"phase"`
	RoundIndex int               `json:"roundIndex"`
	ChooserID  *string           `json:"chooserId"`
	Played     []int64           `json:"played"`
	Modifiers  map[string]string `json:"modifiers"`
	Final      *FinalFile        `json:"final"`
	Settings   Settings          `json:"settings"`
	Players    []*Player         `json:"players"`
	History    []HistoryEntry    `json:"history"`
}

// FinalFile is the saved state of a final in progress.
type FinalFile struct {
	Removed   []int64           `json:"removed"`
	RemoverID *string           `json:"removerId"`
	Order     []string          `json:"order"`
	Turn      int               `json:"turn"`
	Finalists []string          `json:"finalists"`
	Bets      map[string]int    `json:"bets"`
	Answers   map[string]string `json:"answers"`
	Judged    map[string]bool   `json:"judged"`
}

const (
	FileFormat  = "svoy-igra/game"
	FileVersion = 1
)

// ---- views (docs/<lang>/05-protocol.md §4.2) ----

type View struct {
	ServerNow          int64           `json:"serverNow"`
	Role               Role            `json:"role"`
	Game               GameBrief       `json:"game"`
	Phase              Phase           `json:"phase"`
	Pack               *PackRef        `json:"pack"`
	Round              *RoundView      `json:"round"`
	Board              []BoardCategory `json:"board"`
	Players            []PlayerView    `json:"players"`
	ChooserID          *string         `json:"chooserId"`
	Question           *QuestionView   `json:"question"`
	SoloPlayerID       *string         `json:"soloPlayerId"`
	Auction            *AuctionView    `json:"auction"`
	Final              *FinalView      `json:"final"`
	AnsweringPlayerID  *string         `json:"answeringPlayerId"`
	AttemptedPlayerIDs []string        `json:"attemptedPlayerIds"`
	ReadingStartsAt    *int64          `json:"readingStartsAt"`
	ReadingEndsAt      *int64          `json:"readingEndsAt"`
	BuzzStartsAt       *int64          `json:"buzzStartsAt"`
	BuzzEndsAt         *int64          `json:"buzzEndsAt"`
	TypedAnswer        *string         `json:"typedAnswer"`
	LastResult         *Result         `json:"lastResult"`
	Settings           *Settings       `json:"settings"`
	Admins             *int            `json:"admins"`
	Me                 *MeView         `json:"me"`
}

// GameBrief is the game identity inside every state.
type GameBrief struct {
	PIN           *string `json:"pin"`
	Title         string  `json:"title"`
	Link          *string `json:"link"`
	HostTaken     bool    `json:"hostTaken"`
	HostConnected bool    `json:"hostConnected"`
	HostAvatarURL *string `json:"hostAvatarUrl"`
}

type RoundView struct {
	Index int    `json:"index"`
	Name  string `json:"name"`
	Total int    `json:"total"`
	Kind  string `json:"kind"`
}

type AuctionView struct {
	TurnPlayerID    *string  `json:"turnPlayerId"`
	HighBid         int      `json:"highBid"`
	HighBidderID    string   `json:"highBidderId"`
	AllIn           bool     `json:"allIn"`
	PassedPlayerIDs []string `json:"passedPlayerIds"`
}

type FinalTheme struct {
	ID      int64  `json:"id"`
	Name    string `json:"name"`
	Removed bool   `json:"removed"`
}

type FinalParticipant struct {
	PlayerID  string  `json:"playerId"`
	HasBet    bool    `json:"hasBet"`
	Bet       *int    `json:"bet"`
	HasAnswer bool    `json:"hasAnswer"`
	Answer    *string `json:"answer"`
	Correct   *bool   `json:"correct"`
}

type FinalView struct {
	Themes         []FinalTheme       `json:"themes"`
	RemoverID      *string            `json:"removerId"`
	AnswerStartsAt *int64             `json:"answerStartsAt"`
	AnswerEndsAt   *int64             `json:"answerEndsAt"`
	Participants   []FinalParticipant `json:"participants"`
}

type BoardCategory struct {
	ID        int64       `json:"id"`
	Name      string      `json:"name"`
	Questions []BoardCell `json:"questions"`
}

type BoardCell struct {
	ID     int64 `json:"id"`
	Value  int   `json:"value"`
	Played bool  `json:"played"`
}

type QuestionView struct {
	ID           int64         `json:"id"`
	CategoryName string        `json:"categoryName"`
	Value        int           `json:"value"`
	Modifier     *string       `json:"modifier"`
	Stake        int           `json:"stake"`
	Blocks       []packs.Block `json:"blocks"`
	AnswerBlocks []packs.Block `json:"answerBlocks"`
	Comment      *string       `json:"comment"`
}

type PlayerView struct {
	ID        string           `json:"id"`
	Name      string           `json:"name"`
	Score     int              `json:"score"`
	Connected bool             `json:"connected"`
	AvatarURL *string          `json:"avatarUrl"`
	Admin     *AdminPlayerInfo `json:"admin,omitempty"`
}

type AdminPlayerInfo struct {
	Device            Device     `json:"device"`
	RttMs             *int64     `json:"rttMs"`
	RttAvgMs          *int64     `json:"rttAvgMs"`
	JitterMs          *int64     `json:"jitterMs"`
	LastSeenAt        *int64     `json:"lastSeenAt"`
	BuzzOffsetMs      int        `json:"buzzOffsetMs"`
	EffectiveOffsetMs int        `json:"effectiveOffsetMs"`
	Stats             AdminStats `json:"stats"`
}

type AdminStats struct {
	Correct        int    `json:"correct"`
	Wrong          int    `json:"wrong"`
	Buzzes         int    `json:"buzzes"`
	AvgReactionMs  *int64 `json:"avgReactionMs"`
	BestReactionMs *int64 `json:"bestReactionMs"`
}

type Result struct {
	PlayerID string `json:"playerId"`
	Correct  bool   `json:"correct"`
	Delta    int    `json:"delta"`
}

type MeView struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	Score       int    `json:"score"`
	CanSelect   bool   `json:"canSelect"`
	Buzzer      string `json:"buzzer"`
	BuzzOpensAt *int64 `json:"buzzOpensAt"`
	CanType     bool   `json:"canType"`

	CanGiveCat     bool `json:"canGiveCat"`
	CanBid         bool `json:"canBid"`
	CanRemoveTheme bool `json:"canRemoveTheme"`
	Finalist       bool `json:"finalist"`
	CanBet         bool `json:"canBet"`
	CanAnswerFinal bool `json:"canAnswerFinal"`
}

// Event is a one-shot cue (protocol GameEvent).
type Event map[string]any

// CmdError is a rejected command; Code is one of forbidden, wrong_phase,
// not_found, invalid.
type CmdError struct {
	Code    string
	Message string
}

func (e *CmdError) Error() string { return e.Code + ": " + e.Message }

func errForbidden(msg string) *CmdError { return &CmdError{"forbidden", msg} }
func errPhase(msg string) *CmdError     { return &CmdError{"wrong_phase", msg} }
func errNotFound(msg string) *CmdError  { return &CmdError{"not_found", msg} }
func errInvalid(msg string) *CmdError   { return &CmdError{"invalid", msg} }
