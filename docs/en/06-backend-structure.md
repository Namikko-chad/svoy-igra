# Backend structure

```
backend/
  main.go                 config.Load → app.Run; SIGINT/SIGTERM → graceful stop;
                          operator commands `svoy-igra unlock-pack <id>`, `svoy-igra healthcheck`
  app/server.go           build() wires components; start() runs loops; Run() serves
  app/server_test.go      a full game over real HTTP + WebSocket
  app/config/             environment config, Version
  app/httpx/              JSON helpers, error type and policy
  app/ids/                random ids, tokens, PINs
  app/packs/              pack library
    store.go              library dir, per-pack SQLite handle, create/delete/list, lock
    tree.go               types, full tree, CRUD + reorder for rounds/categories/questions
    media.go              media names, MIME, save/delete
    archive.go            .dub export (VACUUM INTO + zip), import (validated unzip), copy
    blocks.go             SplitBlocks: question markdown → text/image/video/audio blocks
  app/game/               the games
    manager.go            all games: create, lookup by PIN/token, save loop, idle deletion
    identity.go           game PIN, admin PIN, role tokens, host slot, presence, leave/close
    types.go              phases, settings, players, history, game file, views
    engine.go             lock/hook discipline, players, timers, question mechanics
    commands.go           player/host/admin commands
    special.go            modifiers: random placement, cat, auction, solo answers
    final.go              final round: finalists, theme removal, bets, written answers, judging
    avatar.go             player/host avatars: set, clear (admin moderation), URLs, file cleanup
    view.go               role-filtered views
    persist.go            games/<id>.json record (identity + content), export/import, restore
  app/ws/hub.go           socket auth, read/write loops, ping/pong, broadcast
  app/api/api.go          REST handlers
  app/discovery/          UDP discovery responder
```

## Packages

**httpx.** `Error{Status, Code, Message}` is a failure the client can fix; `Fail` writes it
as `{"error":{code,message}}`. Any other error is logged and answered with an opaque
`500 internal_error`.

**ids.** Tokens are 16 random bytes in hex; game PINs are 6 digits (unique among live
games); admin PINs are stored as salted SHA-256. A wrong admin PIN costs 500 ms.

**packs.** Each pack is a directory `DATA_DIR/packs/<12-hex id>/` with `pack.sqlite` and
`media/`. Each pack database has one cached connection with foreign keys on. Positions
are renumbered `0..n-1` after every move or delete. A round holds at most 10 categories.
`rounds.kind` (`normal`/`final`) is added to older pack files on open; a final theme holds
exactly one question (`409 final_one_question`).
A pack with `meta.locked = '1'` refuses every change and deletion (`409 pack_locked`);
`Copy` duplicates database and media into a new unlocked pack.
Import accepts only `pack.sqlite` and `media/<valid name>`, checks the total unpacked
size, verifies `meta.format_version = 1` and the tables, and deletes everything on any
failure. Export snapshots the database with `VACUUM INTO` and stores media uncompressed.

**game.** See the engine rules in `backend/CLAUDE.md`. Screens come in two kinds: joined
with the PIN (`screenTokens`) and watching from the public list (`watchTokens`); the hub
marks a watcher's socket `limited`, and `View`/`info` then leave out the PIN and link. The host slot is held while a
socket uses the host token and for 30 s after it drops; `leave` frees it at once.
Presence counts every socket of the game; when it reaches 0 the idle clock starts.
Notable details:
- a player who joins during a question gets a button for the current window;
- removing the answering player (kick) reopens the buttons for the others;
- `reset_game` without `keepPlayers` revokes every player token (sockets closed with `4001`);
- `close_game` and idle deletion remove the game file and close its sockets with `4004`;
- importing a game keeps sockets of players whose id and token are unchanged and
  closes the others with `4001`.

**Temporary files.** Uploads and exports are staged in `DATA_DIR/tmp` (`Config.TempDir`), never
in the system temp dir — the container image has none. The directory is emptied on start.

**Avatars.** `POST /api/avatar` sniffs the bytes (PNG/JPEG/WebP/GIF, ≤ 2 MiB) and writes
`DATA_DIR/avatars/<gameId>/<random>.<ext>`; a new upload or a clear deletes the previous file,
leaving the game deletes a player's file, and closing the game removes the directory. Files
are served with an immutable cache header because names change on every upload.

**ws.** The token of `/api/ws?token=` picks the game and role. One live socket per player
token and per host token (a newer one closes the older with `4009`). Pings every
2 s; three unanswered pings mark the player disconnected until the next pong. Changes
scoped to admins (RTT, device info) re-render only admin sockets.

**discovery.** Answers the datagram `SVOY_IGRA_DISCOVER` with
`{"name","port","version"}`.
