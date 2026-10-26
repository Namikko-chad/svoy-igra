package game

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"svoy-igra/app/httpx"
	"svoy-igra/app/ids"
	"svoy-igra/app/packs"
)

var errTooManyGames = httpx.NewError(503, "too_many_games", "На сервере слишком много игр — попробуйте позже")

// Manager owns every running game.
type Manager struct {
	store    *packs.Store
	dir      string
	idle     time.Duration
	maxGames int
	// sweepTicks: idle games are checked every sweepTicks seconds.
	sweepTicks int
	// wire attaches outputs (the hub) to a new or loaded game.
	wire func(*Engine)

	mu    sync.Mutex
	games map[string]*Engine // by id
	byPin map[string]*Engine
}

// NewManager loads the saved games from dataDir/games.
func NewManager(store *packs.Store, dataDir string, idle time.Duration, maxGames int) (*Manager, error) {
	dir := filepath.Join(dataDir, "games")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	m := &Manager{store: store, dir: dir, idle: idle, maxGames: maxGames, sweepTicks: 15,
		games: map[string]*Engine{}, byPin: map[string]*Engine{}}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	for _, en := range entries {
		if en.IsDir() || !strings.HasSuffix(en.Name(), ".json") || strings.HasPrefix(en.Name(), ".") {
			continue
		}
		path := filepath.Join(dir, en.Name())
		e, err := loadEngine(store, path)
		if err != nil {
			slog.Warn("game file skipped", "path", path, "err", err)
			continue
		}
		if m.byPin[e.pin] != nil {
			slog.Warn("duplicate game PIN, file skipped", "path", path)
			continue
		}
		m.games[e.id] = e
		m.byPin[e.pin] = e
	}
	slog.Info("games loaded", "count", len(m.games))
	return m, nil
}

// SetWire sets the function that connects every game to the hub; it is also
// applied to the games already loaded.
func (m *Manager) SetWire(wire func(*Engine)) {
	m.mu.Lock()
	m.wire = wire
	games := m.all()
	m.mu.Unlock()
	for _, e := range games {
		m.attachHooks(e, wire)
	}
}

func (m *Manager) attachHooks(e *Engine, wire func(*Engine)) {
	if wire != nil {
		wire(e)
	}
	// Deleting from the manager rides on the engine's Closed hook.
	prev := e.hooks.Closed
	e.hooks.Closed = func() {
		m.remove(e)
		if prev != nil {
			prev()
		}
	}
}

func (m *Manager) all() []*Engine {
	out := make([]*Engine, 0, len(m.games))
	for _, e := range m.games {
		out = append(out, e)
	}
	return out
}

// Create starts a new game; the caller becomes its first admin.
func (m *Manager) Create(title, adminPin, linkBase string) (JoinResult, error) {
	if err := ValidateAdminPin(adminPin); err != nil {
		return JoinResult{}, err
	}
	title, err := ValidateTitle(title)
	if err != nil {
		return JoinResult{}, err
	}
	m.mu.Lock()
	if len(m.games) >= m.maxGames {
		m.mu.Unlock()
		return JoinResult{}, errTooManyGames
	}
	pin := ids.Digits(6)
	for m.byPin[pin] != nil {
		pin = ids.Digits(6)
	}
	id := "g_" + ids.Hex(6)
	e := newEngine(m.store, filepath.Join(m.dir, id+".json"))
	e.id, e.pin, e.linkBase, e.createdAt = id, pin, strings.TrimRight(linkBase, "/"), e.ms()
	e.avatarDir = filepath.Join(filepath.Dir(m.dir), "avatars", id)
	e.title = title
	if e.title == "" {
		e.title = "Игра " + pin
	}
	e.emptySince = e.createdAt
	e.setAdminPin(adminPin)
	token := ids.Token()
	e.adminTokens[token] = true
	e.dirty = true
	m.attachHooks(e, m.wire)
	m.games[id] = e
	m.byPin[pin] = e
	m.mu.Unlock()

	e.Save(true)
	slog.Info("game created", "pin", pin, "id", id)
	return JoinResult{Token: token, Role: RoleAdmin, Game: e.Info()}, nil
}

// ByPIN finds a live game.
func (m *Manager) ByPIN(pin string) (*Engine, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if e := m.byPin[pin]; e != nil {
		return e, nil
	}
	return nil, ErrGameNotFound
}

// ByID finds a live game by its public id.
func (m *Manager) ByID(id string) (*Engine, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if e := m.games[id]; e != nil {
		return e, nil
	}
	return nil, ErrGameNotFound
}

// List describes every live game, newest first.
func (m *Manager) List() []GameInfo {
	m.mu.Lock()
	games := m.all()
	m.mu.Unlock()
	out := make([]GameInfo, 0, len(games))
	for _, e := range games {
		out = append(out, e.PublicInfo())
	}
	sort.Slice(out, func(i, j int) bool { return out[i].CreatedAt > out[j].CreatedAt })
	return out
}

// Resolve finds the game and role a token belongs to.
func (m *Manager) Resolve(token string) (*Engine, Role, string, bool) {
	if token == "" {
		return nil, "", "", false
	}
	m.mu.Lock()
	games := m.all()
	m.mu.Unlock()
	for _, e := range games {
		if role, pid, ok := e.Resolve(token); ok {
			return e, role, pid, true
		}
	}
	return nil, "", "", false
}

// PackInUse reports whether any game has the pack loaded.
func (m *Manager) PackInUse(packID string) bool {
	m.mu.Lock()
	games := m.all()
	m.mu.Unlock()
	for _, e := range games {
		e.mu.Lock()
		used := e.pack != nil && e.pack.ID == packID
		e.mu.Unlock()
		if used {
			return true
		}
	}
	return false
}

func (m *Manager) remove(e *Engine) {
	m.mu.Lock()
	if m.games[e.id] == e {
		delete(m.games, e.id)
		delete(m.byPin, e.pin)
	}
	m.mu.Unlock()
	if err := os.Remove(e.path); err != nil && !os.IsNotExist(err) {
		slog.Error("remove game file", "path", e.path, "err", err)
	}
	if err := os.RemoveAll(e.avatarDir); err != nil {
		slog.Error("remove avatars", "dir", e.avatarDir, "err", err)
	}
	slog.Info("game closed", "pin", e.pin, "id", e.id)
}

// Run saves changed games every second and deletes idle ones, until ctx
// ends; then it saves everything once more.
func (m *Manager) Run(ctx context.Context) {
	t := time.NewTicker(time.Second)
	defer t.Stop()
	sweep := 0
	for {
		select {
		case <-ctx.Done():
			m.mu.Lock()
			games := m.all()
			m.mu.Unlock()
			for _, e := range games {
				e.Save(true)
			}
			return
		case <-t.C:
			m.mu.Lock()
			games := m.all()
			m.mu.Unlock()
			sweep++
			for _, e := range games {
				if sweep%m.sweepTicks == 0 && time.Duration(e.IdleFor())*time.Millisecond >= m.idle {
					slog.Info("game idle, deleting", "pin", e.pin)
					e.Close()
					continue
				}
				e.Save(false)
			}
		}
	}
}
