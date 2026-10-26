# Своя игра

A Jeopardy-style quiz for a room full of people and phones.

- One server runs **many games**. Anyone creates a game (choosing an admin PIN) and
  shares its link `…/g/<PIN>`; others join with the game PIN and pick a role.
- **Players** pick questions from the board (rounds × up to 10 categories × values
  100, 200, 300…). After a question appears, a 10-second timer runs; then the
  «Дать ответ» button opens on every device and the first to press answers.
- **Host** (one per game) sees the correct answer, judges and runs the game.
- **Admin** (admin PIN) chooses and edits question packs, manages the game file, sees the
  players: scores (can correct them), device, network latency, and shifts when each
  player's button appears.
- **Screen** (Android TV picks a game from the list, or a browser on a projector) shows the game.

| Dir | What |
|---|---|
| [`backend/`](backend/) | Go server — game engine, REST + WebSocket, pack library, LAN discovery |
| [`frontend/`](frontend/) | Vue 3 web client — player, host, pack editor, admin, screen |
| [`clients/`](clients/) | Flutter app for Android, Windows, Linux and macOS — same features as the web client |
| [`tv/`](tv/) | Flutter Android TV app — read-only screen |
| [`docs/`](docs/) | Documentation ([en](docs/en/02-table-of-contents.md), [ru](docs/ru/02-table-of-contents.md)) |

No database server: question packs are `.dub` files (ZIP of `pack.sqlite` + `media/`;
generating them: [docs/en/13-pack-format.md](docs/en/13-pack-format.md)),
each game is a JSON file. Both can be downloaded and uploaded by the admin.

## Quick start

```bash
cp backend/.env.example backend/.env
make backend                              # :3050 (+ UDP 3051 discovery)
make frontend                             # :3000 — open http://<your-ip>:3000, «Создать игру»
```

Or `docker compose up --build` — one ~13 MB image (root `Dockerfile`), everything on :3050. APKs: `make -C clients build-apk`,
`make -C tv build-apk`; desktop: `make -C clients build-linux` / `build-windows` / `build-macos`. Details: [Getting started](docs/en/03-getting-started.md).
