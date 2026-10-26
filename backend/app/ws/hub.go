// Package ws serves /api/ws: it resolves a socket's token to a game and role,
// relays commands to that game's engine and pushes each receiver its own view.
package ws

import (
	"context"
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/coder/websocket"

	"svoy-igra/app/game"
)

const (
	pingEvery    = 2 * time.Second
	maxMissed    = 3
	sendBuffer   = 64
	readLimit    = 64 << 10
	writeTimeout = 5 * time.Second

	CloseInvalidToken = 4001
	CloseKicked       = 4003
	CloseGameClosed   = 4004
	CloseReplaced     = 4009
)

type Hub struct {
	games *game.Manager

	mu      sync.Mutex
	conns   map[*conn]struct{}
	byToken map[string]*conn // the single live socket of a player or host token

	signal  chan struct{}
	pmu     sync.Mutex
	pending map[*game.Engine]game.Scope
}

type conn struct {
	ws       *websocket.Conn
	engine   *game.Engine
	role     game.Role
	playerID string
	token    string
	limited  bool // a screen from the public list: no PIN in its views
	ip       string
	send     chan []byte
	missed   atomic.Int32
	stale    atomic.Bool
	cancel   context.CancelFunc
	once     sync.Once
}

func New(games *game.Manager) *Hub {
	h := &Hub{
		games:   games,
		conns:   map[*conn]struct{}{},
		byToken: map[string]*conn{},
		signal:  make(chan struct{}, 1),
		pending: map[*game.Engine]game.Scope{},
	}
	games.SetWire(h.wire)
	return h
}

// wire connects one game's outputs to the hub.
func (h *Hub) wire(e *game.Engine) {
	e.SetHooks(game.Hooks{
		Changed: func(s game.Scope) { h.changed(e, s) },
		Event:   func(ev game.Event) { h.event(e, ev) },
		Revoke:  func(tokens []string, code int) { h.revoke(tokens, code) },
		Closed:  func() { h.closeGame(e) },
	})
}

// Run delivers state broadcasts until ctx ends.
func (h *Hub) Run(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			for _, c := range h.snapshot(nil) {
				c.close(websocket.StatusGoingAway, "server shutdown")
			}
			return
		case <-h.signal:
			h.pmu.Lock()
			batch := h.pending
			h.pending = map[*game.Engine]game.Scope{}
			h.pmu.Unlock()
			for e, scope := range batch {
				for _, c := range h.snapshot(e) {
					if scope == game.ScopeAll || c.role == game.RoleAdmin {
						h.sendState(c)
					}
				}
			}
		}
	}
}

func (h *Hub) changed(e *game.Engine, scope game.Scope) {
	h.pmu.Lock()
	if cur, ok := h.pending[e]; !ok || scope == game.ScopeAll {
		h.pending[e] = scope
	} else {
		h.pending[e] = cur
	}
	h.pmu.Unlock()
	select {
	case h.signal <- struct{}{}:
	default:
	}
}

// snapshot lists the sockets of one game (or all with nil).
func (h *Hub) snapshot(e *game.Engine) []*conn {
	h.mu.Lock()
	defer h.mu.Unlock()
	out := make([]*conn, 0, len(h.conns))
	for c := range h.conns {
		if e == nil || c.engine == e {
			out = append(out, c)
		}
	}
	return out
}

func (h *Hub) sendState(c *conn) {
	c.push(message("state", c.engine.View(c.role, c.playerID, c.limited), ""))
}

func (h *Hub) event(e *game.Engine, ev game.Event) {
	msg := message("event", ev, "")
	for _, c := range h.snapshot(e) {
		c.push(msg)
	}
}

func (h *Hub) revoke(tokens []string, code int) {
	want := map[string]bool{}
	for _, t := range tokens {
		want[t] = true
	}
	var victims []*conn
	h.mu.Lock()
	for c := range h.conns {
		if want[c.token] {
			victims = append(victims, c)
		}
	}
	h.mu.Unlock()
	reason := "token revoked"
	switch code {
	case CloseKicked:
		reason = "kicked"
	case 1000:
		reason = "left"
	}
	for _, c := range victims {
		c.close(websocket.StatusCode(code), reason)
	}
}

func (h *Hub) closeGame(e *game.Engine) {
	for _, c := range h.snapshot(e) {
		c.close(CloseGameClosed, "game closed")
	}
}

func message(typ string, data any, reqID string) []byte {
	m := map[string]any{"type": typ}
	if data != nil {
		m["data"] = data
	}
	if reqID != "" {
		m["reqId"] = reqID
	}
	b, _ := json.Marshal(m)
	return b
}

// push queues a frame; a client too slow to drain its queue is dropped.
func (c *conn) push(b []byte) {
	select {
	case c.send <- b:
	default:
		go c.close(websocket.StatusPolicyViolation, "too slow")
	}
}

func (c *conn) close(code websocket.StatusCode, reason string) {
	c.once.Do(func() {
		_ = c.ws.Close(code, reason)
		c.cancel()
	})
}

// ServeHTTP upgrades the request and runs the connection until it ends.
func (h *Hub) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ws, err := websocket.Accept(w, r, &websocket.AcceptOptions{InsecureSkipVerify: true})
	if err != nil {
		return
	}
	ws.SetReadLimit(readLimit)

	token := r.URL.Query().Get("token")
	e, role, playerID, ok := h.games.Resolve(token)
	if !ok {
		_ = ws.Close(CloseInvalidToken, "invalid token")
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	c := &conn{ws: ws, engine: e, role: role, playerID: playerID, token: token, ip: clientIP(r),
		limited: e.IsWatcher(token), send: make(chan []byte, sendBuffer), cancel: cancel}

	h.register(c)
	defer h.unregister(c)

	go c.writeLoop(ctx)
	go h.pingLoop(ctx, c)

	welcome := map[string]any{"role": role, "serverNow": time.Now().UnixMilli()}
	if !c.limited {
		welcome["pin"] = e.PIN()
	}
	if playerID != "" {
		welcome["playerId"] = playerID
	}
	c.push(message("welcome", welcome, ""))
	h.sendState(c)

	h.readLoop(ctx, c)
	c.close(websocket.StatusNormalClosure, "")
}

func exclusive(role game.Role) bool { return role == game.RolePlayer || role == game.RoleHost }

func (h *Hub) register(c *conn) {
	h.mu.Lock()
	h.conns[c] = struct{}{}
	var old *conn
	if exclusive(c.role) {
		old = h.byToken[c.token]
		h.byToken[c.token] = c
	}
	h.mu.Unlock()
	if old != nil {
		old.close(CloseReplaced, "replaced by a newer connection")
	}
	c.engine.Attach(c.role, c.token)
	if c.playerID != "" {
		c.engine.SetConnected(c.playerID, true)
	}
	slog.Debug("ws connected", "game", c.engine.PIN(), "role", c.role, "player", c.playerID, "ip", c.ip)
}

func (h *Hub) unregister(c *conn) {
	h.mu.Lock()
	delete(h.conns, c)
	current := exclusive(c.role) && h.byToken[c.token] == c
	if current {
		delete(h.byToken, c.token)
	}
	h.mu.Unlock()
	c.engine.Detach(c.role, c.token)
	if current && c.playerID != "" {
		c.engine.SetConnected(c.playerID, false)
	}
	slog.Debug("ws disconnected", "game", c.engine.PIN(), "role", c.role, "player", c.playerID)
}

func (c *conn) writeLoop(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case b := <-c.send:
			wctx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.ws.Write(wctx, websocket.MessageText, b)
			cancel()
			if err != nil {
				c.close(websocket.StatusGoingAway, "write failed")
				return
			}
		}
	}
}

func (h *Hub) pingLoop(ctx context.Context, c *conn) {
	t := time.NewTicker(pingEvery)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			if c.missed.Add(1) > maxMissed && c.playerID != "" && !c.stale.Swap(true) {
				c.engine.SetConnected(c.playerID, false)
			}
			c.push(message("ping", map[string]int64{"t": time.Now().UnixMilli()}, ""))
		}
	}
}

type inbound struct {
	Type  string          `json:"type"`
	Data  json.RawMessage `json:"data"`
	ReqID string          `json:"reqId"`
}

func (h *Hub) readLoop(ctx context.Context, c *conn) {
	for {
		typ, b, err := c.ws.Read(ctx)
		if err != nil {
			return
		}
		if typ != websocket.MessageText {
			continue
		}
		var m inbound
		if err := json.Unmarshal(b, &m); err != nil || m.Type == "" {
			c.push(message("error", map[string]string{"code": "invalid", "message": "Некорректное сообщение"}, ""))
			continue
		}
		switch m.Type {
		case "pong":
			h.pong(c, m.Data)
		case "hello":
			h.hello(c, m.Data)
		default:
			if err := c.engine.Command(c.role, c.playerID, c.token, m.Type, m.Data); err != nil {
				code, msg := "invalid", err.Error()
				if ce, ok := err.(*game.CmdError); ok {
					code, msg = ce.Code, ce.Message
				}
				c.push(message("error", map[string]string{"code": code, "message": msg}, m.ReqID))
			}
		}
	}
}

func (h *Hub) pong(c *conn, data json.RawMessage) {
	var p struct {
		T int64 `json:"t"`
	}
	if json.Unmarshal(data, &p) != nil || p.T == 0 {
		return
	}
	c.missed.Store(0)
	if c.playerID == "" {
		return
	}
	if c.stale.Swap(false) {
		c.engine.SetConnected(c.playerID, true)
	}
	rtt := time.Now().UnixMilli() - p.T
	if rtt >= 0 && rtt < 60_000 {
		c.engine.RecordRTT(c.playerID, rtt)
	}
}

func (h *Hub) hello(c *conn, data json.RawMessage) {
	if c.playerID == "" {
		return
	}
	var d game.Device
	if json.Unmarshal(data, &d) != nil {
		return
	}
	clip := func(s string, n int) string {
		if len(s) > n {
			return s[:n]
		}
		return s
	}
	d.Platform, d.Model, d.OS = clip(d.Platform, 32), clip(d.Model, 100), clip(d.OS, 100)
	d.AppVersion, d.UserAgent, d.Screen = clip(d.AppVersion, 32), clip(d.UserAgent, 400), clip(d.Screen, 32)
	d.IP = c.ip
	c.engine.SetDevice(c.playerID, d)
}

func clientIP(r *http.Request) string {
	if xf := r.Header.Get("X-Forwarded-For"); xf != "" {
		return strings.TrimSpace(strings.Split(xf, ",")[0])
	}
	if xr := r.Header.Get("X-Real-IP"); xr != "" {
		return xr
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}
