# Architecture

```
 apps / browsers ────┐  REST /api/*        ┌──────────────── backend ─────────────────┐
 (player/host/admin) ├────────────────────►│ api ──► packs.Store ──► DATA_DIR/packs/  │
                     │  WS /api/ws?token=  │  │                                        │
 Android TV / screen ├────────────────────►│ ws.Hub ◄─► game.Manager ─► games/*.json │
                     │  UDP 3051 probe     │                                          │
 apps / TV  ─────────┴────────────────────►│ discovery                                │
                                           └──────────────────────────────────────────┘
```

## Components (wired in `backend/app/server.go`)

| Component | Responsibility |
|---|---|
| `packs.Store` | the pack library on disk; CRUD for the editor; `.dub` import/export; media files |
| `game.Manager` | every live game: create, find by PIN or token, save changed games each second, delete games idle for `GAME_IDLE_MINUTES` |
| `game.Engine` | one game: identity (PIN, admin PIN, role tokens, host slot, presence), phases, timers, per-player buttons, scores, role views; persisted to `games/<id>.json` |
| `ws.Hub` | authenticates sockets into roles, relays commands to the engine, pushes each socket its own state, measures RTT |
| `api` | REST: create/list/join games, pack library and editor (lock, copy), media, game file download/upload, `assetlinks.json` |
| `discovery` | answers UDP broadcast probes with the server's name and port |
| SPA handler | optional: serves the built web client when `STATIC_DIR` is set |

## Data flow

1. A client creates a game (`POST /api/games`, becomes its admin) or joins one by PIN
   and role (`POST /api/games/{pin}/join`) and keeps the token. A token belongs to one
   game and one role.
2. It opens `/api/ws?token=…`; the hub resolves the token to its game and role and sends
   `welcome` and a full `state`.
3. Commands go over the socket. The engine validates them against role and phase,
   changes state and records history.
4. After every change the hub re-renders the view **per receiver** — the role decides
   what is visible (the answer only for the host until reveal; the admin never sees
   questions) — and pushes it. There is no diffing: every `state` is a full snapshot.
5. Timers (reading time, each player's button, the buzz window) run in the engine. When
   a player's button opens, the server pushes that moment; clients only render it.
6. Every 2 s the hub pings each socket; the pong gives the RTT the admin sees and the
   automatic latency compensation uses.

## Lifecycle

- **Start:** read config → ensure `DATA_DIR` → open the pack library → load every
  `games/*.json` (a question in progress is restored as the board; a missing pack sends
  that game to the lobby) → start the hub, the manager loop and discovery → listen.
- **Running:** an engine marks itself dirty on every change; the manager writes changed
  games atomically at most once per second and, every 15 s, deletes games that have had
  no sockets for `GAME_IDLE_MINUTES` (file and tokens; sockets of a closed game get `4004`).
- **Stop (SIGINT/SIGTERM):** sockets are closed, every game is written one last time,
  the HTTP server shuts down, pack databases are closed.

## Concurrency

Each engine has its own mutex; games never share state except the pack library. Hook calls (state changed, event, revoke tokens) are collected
while it is held and delivered after release, so the hub can read views without
deadlocks. Each timer carries a generation number and is ignored once the game moved on.
Each socket has its own write queue; a client that cannot keep up is disconnected.
