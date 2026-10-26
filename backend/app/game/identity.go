package game

import (
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"regexp"
	"strings"
	"unicode/utf8"

	"svoy-igra/app/httpx"
	"svoy-igra/app/ids"
)

// hostGraceMs keeps the host slot for a host whose socket dropped, so a
// reconnect does not lose it to someone else.
const hostGraceMs = 30_000

// identity is who may enter a game and who is in it right now.
type identity struct {
	id        string
	pin       string
	title     string
	linkBase  string
	createdAt int64

	adminSalt    string
	adminHash    string
	adminTokens  map[string]bool
	hostToken    string
	screenTokens map[string]bool // screens that joined with the game PIN
	watchTokens  map[string]bool // screens from the public list: no PIN, no link

	hostAvatar string // file in avatarDir
	avatarDir  string // DATA_DIR/avatars/<id>

	sockets     int   // open sockets of every role
	adminConns  int   // open admin sockets
	hostSockets int   // open sockets holding hostToken
	hostGoneAt  int64 // last moment the host slot was occupied
	emptySince  int64 // when sockets dropped to 0 (0 while someone is connected)
	closed      bool
}

// GameInfo describes a game (protocol §2.3). PIN and Link are nil in public
// listings and for screens that came from the list.
type GameInfo struct {
	ID        string   `json:"id"`
	PIN       *string  `json:"pin"`
	Title     string   `json:"title"`
	Link      *string  `json:"link"`
	Phase     Phase    `json:"phase"`
	Pack      *PackRef `json:"pack"`
	Players   int      `json:"players"`
	HostTaken bool     `json:"hostTaken"`
	CreatedAt int64    `json:"createdAt"`
}

// JoinResult answers create/join/me.
type JoinResult struct {
	Token    string   `json:"token,omitempty"`
	Role     Role     `json:"role"`
	PlayerID string   `json:"playerId,omitempty"`
	Name     string   `json:"name,omitempty"`
	Game     GameInfo `json:"game"`
}

var adminPinRe = regexp.MustCompile(`^[0-9]{4,8}$`)

var (
	ErrInvalidAdminPin = httpx.NewError(401, "invalid_admin_pin", "Неверный PIN администратора")
	errHostTaken       = httpx.Conflict("host_taken", "Ведущий в этой игре уже есть")
	ErrGameNotFound    = httpx.NewError(404, "game_not_found", "Игра не найдена или уже закрыта")
)

// ValidateAdminPin checks the admin PIN format.
func ValidateAdminPin(pin string) error {
	if !adminPinRe.MatchString(pin) {
		return httpx.BadRequest("invalid_admin_pin", "PIN администратора — от 4 до 8 цифр")
	}
	return nil
}

// ValidateTitle normalises a game title (empty is allowed).
func ValidateTitle(t string) (string, error) {
	t = strings.Join(strings.Fields(t), " ")
	if utf8.RuneCountInString(t) > 60 {
		return "", httpx.BadRequest("invalid_title", "Название игры — не длиннее 60 символов")
	}
	return t, nil
}

func hashPin(salt, pin string) string {
	sum := sha256.Sum256([]byte(salt + ":" + pin))
	return hex.EncodeToString(sum[:])
}

func (e *Engine) setAdminPin(pin string) {
	e.adminSalt = ids.Hex(8)
	e.adminHash = hashPin(e.adminSalt, pin)
}

func (e *Engine) hostTaken() bool {
	return e.hostToken != "" && (e.hostSockets > 0 || e.ms()-e.hostGoneAt < hostGraceMs)
}

func (e *Engine) link() string { return e.linkBase + "/g/" + e.pin }

// info describes the game; full adds the PIN and the share link.
func (e *Engine) info(full bool) GameInfo {
	gi := GameInfo{
		ID: e.id, Title: e.title, Phase: e.phase,
		Players: len(e.players), HostTaken: e.hostTaken(), CreatedAt: e.createdAt,
	}
	if full {
		gi.PIN, gi.Link = ptr(e.pin), ptr(e.link())
	}
	if e.pack != nil {
		gi.Pack = &PackRef{ID: e.pack.ID, Title: e.pack.Title}
	}
	return gi
}

// Info describes the game with its PIN and link (for callers who know the PIN).
func (e *Engine) Info() GameInfo {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.info(true)
}

// PublicInfo describes the game without its PIN and link.
func (e *Engine) PublicInfo() GameInfo {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.info(false)
}

// IsWatcher reports whether token is a screen that joined from the public list.
func (e *Engine) IsWatcher(token string) bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.watchTokens[token]
}

// Watch adds a screen without the PIN (from the public game list).
func (e *Engine) Watch() (JoinResult, error) {
	var res JoinResult
	err := e.do(func() error {
		if e.closed {
			return ErrGameNotFound
		}
		res = JoinResult{Role: RoleScreen, Token: ids.Token()}
		e.watchTokens[res.Token] = true
		e.dirty = true
		res.Game = e.info(false)
		return nil
	})
	return res, err
}

// ID and PIN are immutable after creation.
func (e *Engine) ID() string  { return e.id }
func (e *Engine) PIN() string { return e.pin }

// Resolve maps a token of this game to its role.
func (e *Engine) Resolve(token string) (role Role, playerID string, ok bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.resolve(token)
}

func (e *Engine) resolve(token string) (Role, string, bool) {
	if token == "" || e.closed {
		return "", "", false
	}
	switch {
	case token == e.hostToken:
		return RoleHost, "", true
	case e.adminTokens[token]:
		return RoleAdmin, "", true
	case e.screenTokens[token], e.watchTokens[token]:
		return RoleScreen, "", true
	}
	for _, p := range e.players {
		if p.Token == token {
			return RolePlayer, p.ID, true
		}
	}
	return "", "", false
}

// Me describes a token's seat (GET /api/auth/me).
func (e *Engine) Me(token string) (JoinResult, bool) {
	e.mu.Lock()
	defer e.mu.Unlock()
	role, pid, ok := e.resolve(token)
	if !ok {
		return JoinResult{}, false
	}
	r := JoinResult{Role: role, PlayerID: pid, Game: e.info(!e.watchTokens[token])}
	if p := e.player(pid); p != nil {
		r.Name = p.Name
	}
	return r, true
}

// Join enters the game in a role and returns a new token.
func (e *Engine) Join(role Role, name, adminPin string) (JoinResult, error) {
	var res JoinResult
	err := e.do(func() error {
		if e.closed {
			return ErrGameNotFound
		}
		res = JoinResult{Role: role}
		switch role {
		case RolePlayer:
			p, err := e.joinPlayer(name)
			if err != nil {
				return err
			}
			res.Token, res.PlayerID, res.Name = p.Token, p.ID, p.Name
		case RoleHost:
			if e.hostTaken() {
				return errHostTaken
			}
			if e.hostToken != "" {
				e.revoke([]string{e.hostToken}, 4001)
			}
			e.hostToken = ids.Token()
			e.hostGoneAt = e.ms() // grace until the new host's socket connects
			res.Token = e.hostToken
		case RoleScreen:
			res.Token = ids.Token()
			e.screenTokens[res.Token] = true
		case RoleAdmin:
			if subtle.ConstantTimeCompare([]byte(hashPin(e.adminSalt, adminPin)), []byte(e.adminHash)) != 1 {
				return ErrInvalidAdminPin
			}
			res.Token = ids.Token()
			e.adminTokens[res.Token] = true
		default:
			return httpx.BadRequest("invalid_role", "Неизвестная роль")
		}
		e.dirty = true
		e.changed(ScopeAll)
		res.Game = e.info(true)
		return nil
	})
	return res, err
}

// Attach and Detach track open sockets; the hub calls them.
func (e *Engine) Attach(role Role, token string) {
	_ = e.do(func() error {
		e.sockets++
		e.emptySince = 0
		switch {
		case role == RoleAdmin:
			e.adminConns++
		case role == RoleHost && token == e.hostToken:
			e.hostSockets++
		}
		e.changed(ScopeAll)
		return nil
	})
}

func (e *Engine) Detach(role Role, token string) {
	_ = e.do(func() error {
		e.sockets = max(0, e.sockets-1)
		if e.sockets == 0 {
			e.emptySince = e.ms()
			e.dirty = true
		}
		switch {
		case role == RoleAdmin:
			e.adminConns = max(0, e.adminConns-1)
		case role == RoleHost && token == e.hostToken:
			e.hostSockets = max(0, e.hostSockets-1)
			if e.hostSockets == 0 {
				e.hostGoneAt = e.ms()
			}
		}
		e.changed(ScopeAll)
		return nil
	})
}

// IdleFor reports how long the game has had no sockets (0 while someone is in).
func (e *Engine) IdleFor() int64 {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.sockets > 0 || e.emptySince == 0 {
		return 0
	}
	return e.ms() - e.emptySince
}

// Close deletes the game: timers stop, every socket gets 4004 via Hooks.Closed.
func (e *Engine) Close() {
	_ = e.do(func() error {
		e.closeLocked()
		return nil
	})
}

func (e *Engine) closeLocked() {
	if e.closed {
		return
	}
	e.closed = true
	e.gen++
	if h := e.hooks.Closed; h != nil {
		e.pending = append(e.pending, h)
	}
}

// leave gives up the caller's seat.
func (e *Engine) leave(role Role, playerID, token string) {
	switch role {
	case RolePlayer:
		if e.player(playerID) != nil {
			e.removePlayer(playerID)
			e.log(HistoryEntry{Kind: "player_left", By: "player", PlayerID: playerID})
		}
	case RoleHost:
		if token == e.hostToken {
			e.hostToken = ""
			e.hostGoneAt = 0
			e.hostSockets = 0
		}
	case RoleAdmin:
		delete(e.adminTokens, token)
	case RoleScreen:
		delete(e.screenTokens, token)
		delete(e.watchTokens, token)
	}
	e.revoke([]string{token}, 1000)
	e.dirty = true
	e.changed(ScopeAll)
}
