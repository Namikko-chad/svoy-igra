# Своя игра — open-source Jeopardy-style quiz game for parties, classrooms and pub quizzes

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Builds](https://github.com/Namikko-chad/svoy-igra/actions/workflows/builds.yml/badge.svg)](https://github.com/Namikko-chad/svoy-igra/actions/workflows/builds.yml)
[![Release](https://img.shields.io/github/v/release/Namikko-chad/svoy-igra)](https://github.com/Namikko-chad/svoy-igra/releases/latest)
![Go](https://img.shields.io/badge/server-Go-00ADD8)
![Vue 3](https://img.shields.io/badge/web-Vue%203-42b883)
![Flutter](https://img.shields.io/badge/apps-Flutter-02569B)

**English** · [Русский](README.ru.md)

**Своя игра** («Svoya Igra», «Own Game») is a free, self-hosted **Jeopardy!-style quiz
game** for a group of people in one room or on one network. A small Go server runs the
games; players buzz in from their **phones, laptops or the web browser**, a host judges
the answers, and a **TV, projector or Android TV** shows the board. No accounts, no
cloud, no database server — one ~13 MB Docker image or a single binary.

Use it for a party quiz night, a team-building game, a classroom review, a pub quiz or
a «Своя игра» / «Что? Где? Когда?»-style club evening.

## Features

- **Buzzer system that is fair on Wi-Fi**: the «Дать ответ» (buzz) button opens on every
  device at the same moment; the server measures each player's latency and can
  compensate for it. The admin sees reaction times and can shift any player's button.
- **Many games on one server**, each with its own 6-digit PIN and share link `…/g/<PIN>`
  and a QR code to join.
- **Four roles**: player, host (sees the answer, judges, runs the game), admin (packs,
  scores, players, latency) and screen (board for a TV or projector).
- **Classic rules**: rounds × up to 10 categories × values 100, 200, 300…; special
  questions — «Кот в мешке» (cat in the bag), «Аукцион» (auction), no-risk and double
  questions; a final round with bets.
- **Built-in question pack editor** with markdown, images, audio and video; packs are
  portable `.dub` files (ZIP of SQLite + media) you can import, export and
  [generate with a script or an AI](docs/en/13-pack-format.md).
- **Clients for every device**: web site (Vue 3), app for **Android, Windows, Linux and
  macOS** (Flutter), **Android TV** screen app. LAN discovery finds the server
  automatically.
- **Self-hosted and offline-friendly**: runs on a laptop, a Raspberry Pi-class box,
  Docker, or even a **MikroTik router** container. Games and packs are plain files.
- Russian interface.

## Quick start

### Docker (recommended)

```bash
git clone https://github.com/Namikko-chad/svoy-igra.git
cd svoy-igra
docker compose up -d --build
```

Open `http://<your-ip>:3050`, press «Создать игру», share the link or QR with the players.

### From source

```bash
cp backend/.env.example backend/.env
make backend                              # Go server on :3050 (+ UDP 3051 LAN discovery)
make frontend                             # web client on :3000 — open http://<your-ip>:3000
```

### Apps

Ready builds — Windows `.zip`, macOS `.zip`, Linux `.tar.gz`, Android phone APK and
Android TV APK — are on the [Releases](https://github.com/Namikko-chad/svoy-igra/releases/latest)
page. Build them yourself: `make -C clients build-apk`, `make -C tv build-apk`,
`make -C clients build-linux` / `build-windows` / `build-macos`.
Details: [Getting started](docs/en/03-getting-started.md).

## How a question plays

1. The chooser picks a category and a value on the board.
2. The question appears on every screen; a common reading timer runs (10 s by default).
3. The buzz button opens on every player's device at once; the first press wins.
4. The player answers aloud (or types); the host marks it right or wrong.
5. Right: the value is added and that player chooses next. Wrong: the others may buzz.

Full rules: [Game rules and packs](docs/en/07-game-and-packs.md).

## Repository layout

| Dir | What |
|---|---|
| [`backend/`](backend/) | Go server — game engine, REST + WebSocket, pack library, LAN discovery |
| [`frontend/`](frontend/) | Vue 3 web client — player, host, pack editor, admin, screen |
| [`clients/`](clients/) | Flutter app for Android, Windows, Linux and macOS — same features as the web client |
| [`tv/`](tv/) | Flutter Android TV app — read-only screen |
| [`docs/`](docs/) | Documentation ([en](docs/en/02-table-of-contents.md), [ru](docs/ru/02-table-of-contents.md)) |

No database server: question packs are `.dub` files (ZIP of `pack.sqlite` + `media/`),
each game is a JSON file. Both can be downloaded and uploaded by the admin. The
[protocol](docs/en/05-protocol.md) (REST, WebSocket, pack format) is documented, so
you can write your own client.

## FAQ

**Is it free?** Yes, MIT-licensed, no ads, no accounts, no telemetry.

**Does it need the internet?** No. Everything works inside one local network; the
server, phones and TV only need to see each other.

**How many players?** As many as fit in the room — every player uses their own device.

**Where do I get questions?** Write them in the built-in editor, import a `.dub` pack, or
generate one from a spreadsheet or with an AI assistant following
[the pack format guide](docs/en/13-pack-format.md).

**Is it the same as SIGame?** No. It is an independent project with its own server,
clients and `.dub` pack format.

## Contributing

Issues and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).
Changes are listed in [CHANGELOG.md](CHANGELOG.md).

## License

[MIT](LICENSE)
