# CLAUDE.md — Backend (Go)

## Stack
- Go (see `go.mod`), standard library `net/http` (method + path patterns), `log/slog`.
- `modernc.org/sqlite` (pure Go, `CGO_ENABLED=0`) for pack files.
- `github.com/coder/websocket` for `/api/ws`.
- No database server, no ORM, no web framework. Keep dependencies minimal.

## Contract
`docs/en/05-protocol.md` is authoritative. Any change to an endpoint, a message, a view
field, the `.dub` schema or the game file changes that document (both languages) and
all three clients in the same change.

## Layout
```
main.go               config → app.Run, signal handling; operator commands `unlock-pack <id>`, `healthcheck`
app/server.go         wiring: store → game manager → hub → api → static SPA; build()/start() used by tests
app/config/           env config, Version
app/httpx/            JSON helpers and the error policy (Fail, Error)
app/ids/              random ids, tokens, PINs
app/packs/            shared pack library: SQLite schema, CRUD + reorder, lock/copy, media, .dub import/export, SplitBlocks
app/game/             manager.go: many games (create, PIN/token lookup, save loop, idle deletion);
                      engine: phases, timers, per-player buzzer, views by role;
                      identity.go: game PIN, admin PIN, role tokens, host slot, presence;
                      special.go: modifiers (cat, auction, no_risk, double); final.go: final round
app/ws/               websocket hub: auth by token, ping/pong RTT, per-receiver state push
app/api/              REST handlers
app/discovery/        UDP LAN discovery responder
```

## Commands
```
make development   # go run . (reads .env)
make test          # go test ./...  (app/server_test.go plays a full game over HTTP + WS, two games, restart)
make lint          # go vet
make build         # bin/svoy-igra (static binary)
docker compose up --build   # (repo root) one scratch image: server + built web client
```
Run `go test -race ./...` after touching `app/game` or `app/ws`.

## Error policy
- A failure the client can fix → `httpx.Error` with a `4xx` and a Russian message
  (`httpx.BadRequest`, `NotFound`, `Conflict`, `NewError`). Body:
  `{"error":{"code","message"}}`.
- Anything else → return the plain error; `httpx.Fail` logs it and answers an opaque
  `500 internal_error`. Never put `err.Error()` of a server-side failure in a response.
- WebSocket commands answer with `{"type":"error","data":{code,message}}` using
  `game.CmdError` codes `forbidden | wrong_phase | not_found | invalid`.

## Games and tokens
- One `game.Manager` holds every game; each `Engine` is one game with its own lock,
  file (`DATA_DIR/games/<id>.json`) and tokens. A token belongs to exactly one game and
  role; `Manager.Resolve(token)` finds both. No server-wide secrets or PINs.
- REST pack endpoints accept the admin token of **any** game (the library is shared);
  `/api/game/*` act on the token's own game.
- The game file export is content only — never put identity (admin PIN hash, tokens of
  admins/host/screens) in it.
- A locked pack refuses every mutation with `409 pack_locked` (`Store.writable`).

## Engine rules (app/game)
- All state is guarded by `Engine.mu`. Public methods go through `e.do(fn)`: hook calls
  (`changed`, `emit`, `revoke`) are collected under the lock and delivered after it is
  released — never call the hub while holding the lock.
- `Hooks.Revoke` takes **tokens**; `Hooks.Closed` deletes the game (manager) and closes
  its sockets with `4004` (hub).
- Every timer is created with `e.after(at, gen, fn)` and ignored when `e.gen` moved on.
  Bump `e.gen` on any transition that invalidates pending timers.
- Buttons open by **server push** at `readingEndsAt + effectiveOffset(player)`; clients
  never open them on their own clock.
- A role's view is built in `view.go`. The admin never receives board/question; players
  and screens receive the answer only in `reveal`; `typedAnswer` goes to the host only.
- `ScopeAdmins` changes (RTT, device info) re-render only admin sockets.
- Persisted fields live in `game.File`; runtime telemetry stays unexported on `Player`.
- Modifiers are placed at round start (`assignModifiers`) and stay secret until a cell
  opens. A solo question (`question.solo`) has no buttons; wrong goes straight to reveal.
- Visibility in the final: bets and answers go to the host and their owner, to everyone
  once judged or in `final_reveal` (`finalView`).

## Time
Store and send Unix milliseconds UTC. Never apply a time zone on the server.

## Git Worktrees — FORBIDDEN
- **Never use git worktrees** (no `git worktree …`, no worktree isolation modes). Work in
  the existing clone; switch branches in place with `git switch` on a clean tree.
