# CLAUDE.md — TV (Flutter, Android TV)

Read-only game display for Android TV. Protocol: `docs/en/05-protocol.md` (§1 games
and the `screen` role, §2.1 game lookup/join, §3 blocks + screen playback rules,
§4 WebSocket incl. §4.5 special questions and §4.6 final, §7 LAN discovery, §8 share link). Flow: **server → live games list
(or «Ввести PIN») → display**.
Visual language: `DESIGN_MANIFEST.md` (dark only, TV sizes). Code is **not** shared
with `../clients` on purpose.

## Stack

| Concern | Choice |
|---|---|
| Framework | Flutter 3.41 (Dart 3.11), Android only |
| State | plain `ChangeNotifier` + `ListenableBuilder` (no DI, no codegen) |
| Realtime | `web_socket_channel` (`GameSocket`) |
| Discovery | `dart:io` `RawDatagramSocket` UDP broadcast |
| HTTP | `http`: `GET /api/info`, `GET /api/games`, `POST /api/games/{id}/watch`, `GET /api/games/{pin}`, `POST /api/games/{pin}/join {role:"screen"}` |
| Storage | `shared_preferences` (last server; per server the screen token + game id, PIN only if joined by PIN) |
| Markdown | `flutter_markdown_plus` + `markdown` (`ExtensionSet.commonMark`; raw HTML shows as literal text) |
| Media | `video_player` (video), `audioplayers` (question audio + cue tones) |
| Misc | `qr_flutter` (join QR), `wakelock_plus`, `device_info_plus`, `package_info_plus` |
| Fonts | bundled in `assets/fonts` (Unbounded, Inter, JetBrains Mono) — the TV may be offline |

## Layout

```
lib/
  main.dart, app.dart        # bootstrap (wakelock, immersive, D-pad shortcuts), MaterialApp
  app_controller.dart        # AppStage connect → games (↔ pin) → display; owns GameSocket, rejoin/leave/4004
  core/
    config.dart              # ports, timeouts, 1920×1080 stage size
    theme/                   # AppColors (manifest tokens), AppText (type roles), AppTheme
    utils/                   # ServerAddress, ServerClock, questionCountdown, reconnectDelay
    widgets/                 # StageScaler, StageBackground, TvButton (focus ring), Avatar + ServerBase
  data/
    api/games_api.dart       # GamesApi: listGames(), watch(id), getGame(pin), joinAsScreen(pin); ApiError
    models/                  # hand-written fromJson: GameView(+GameRef), GameInfo/JoinResult/GameSession, Block, GameEvent, block_splitter
    ws/game_socket.dart      # /api/ws?token=…; welcome→hello, ping→pong, state, event, leave; backoff; 4001/4003/4004 end it
    discovery/               # LanDiscovery (UDP 3051), ServerProbe (/api/info)
    storage/server_store.dart # last server + GameSession per server
    device/device_hello.dart # hello payload (platform android_tv)
  features/
    connect/                 # server list + manual address
    games/                   # GamesController (unit-tested, 5 s refresh, watch by id) + GamesScreen: focusable game cards (no PINs)
    pin/                     # PinController (unit-tested) + PinScreen: D-pad digit pad, remote digits, game card
    display/                 # DisplayScreen, SoundCues, stage_key, widgets/ per phase: board, question_stage,
                             #   modifier_reveal (+ CatPainter), special_views (cat_transfer, auction), final_views,
                             #   standings, lobby; media/: MediaBlock, MediaPlayback, Equalizer
assets/fonts, assets/sounds  # generated tones (no third-party audio)
```

## Commands

```bash
make deps | analyze | test | run | build-apk | build-apk-debug | clean
```

## Conventions

- **Fixed stage.** Everything is laid out on a 1920×1080 canvas (`StageScaler` in
  `MaterialApp.builder`) and scaled to the screen, so manifest pixel sizes are
  literal (board values 72 px). Never read the real `MediaQuery` size for layout.
- **D-pad first.** Every interactive element is focusable with a visible accent
  ring (`TvButton`); OK/Select maps to `ActivateIntent`. Text fields get explicit
  ↑/↓ traversal shortcuts. The PIN screen also takes the remote's number keys
  (and Backspace). The display itself has no focusable content: Back / Menu / OK
  open the menu («Продолжить показ», «Сменить игру», «Сменить сервер»).
- **Sessions.** Join once — from the list `POST /api/games/{id}/watch`, by PIN
  `POST /api/games/{pin}/join {role:"screen"}` — store `{token, gameId, pin?}` per
  server, and from then on only reconnect the WebSocket with the token — also after
  an app restart. Close code 4001/4003/4004 is terminal: forget the token, return to
  the games list with a notice («Игра закрыта» for 4004). Leaving a game («Сменить
  игру» → games list, «Сменить сервер» → connect) sends `leave` first. Back walks
  up: PIN → games list → connect.
- **Read-only.** The screen never sends commands other than `hello`, `pong` and `leave`.
  Never show the answer before phase `reveal` (the server already withholds it).
- **Time.** Countdowns use the server clock: `ServerClock.sync(serverNow)` on every
  `state`; `questionCountdown` draws reading = `readingStartsAt → readingEndsAt`
  and the buzz window = `buzzStartsAt → buzzEndsAt` straight from the view. No
  wall-clock timestamps are displayed.
- **Join link.** The public list never carries PINs and a watch screen never gets
  `game.pin`/`game.link`. The lobby shows QR + link + PIN only when the view has
  them (screen joined by PIN); otherwise «Ссылку для входа раздаёт администратор».
  Never build a link or show a PIN from anything else.
- **Media.** URLs are server-relative; resolve with `ServerAddress.resolve`. Question,
  answer and comment media all render through `MediaBlock` (video/audio) behind the
  `MediaPlayback` interface (`MediaPlaybackScope` lets tests inject a fake). Each block
  belongs to a display stage (`stageKeyOf`: `q-<id>` for question+answering,
  `reveal-<id>`): it autoplays once with sound when it appears in the current stage
  and stops at once when `MediaStage` moves on — the question's media stops the
  moment `reveal` starts, while the answer/comment media start. Widgets are keyed by
  stage + block index, so unrelated `state` rebuilds never restart playback.
- **Board.** One row per category (name in a fixed 340 px left column, 24 px,
  2 lines), value cells left → right ascending, rows share the height equally.
  `BoardCell` sizes the value to ≤ 45 % of the cell height and `FittedBox`-shrinks
  it to the cell width, so 10×10 with 4–5-digit values never overflows (tested).
- **Avatars.** `Avatar` (circle; initials on `surface-2` when `avatarUrl` is null or
  fails) resolves the relative URL against `ServerBase` (provided by `DisplayScreen`).
  Sizes: 32–48 lists/chips, 56 scoreboard, 64 answering/standings/final tiles, 96+
  lobby/podium; rings follow the scoreboard (gold chooser, accent answering). The
  host shows as `HostBadge` (avatar + «Ведущий», dimmed when offline) in the top
  bar and lobby.
- **Special questions & final.** A cell with `question.modifier` gets a full-screen
  `ModifierReveal` (3.2 s, once per question id; `event modifier` only adds the
  sound); while it covers the screen `MediaStage` is `modifier-<id>`, so the
  question's media starts only after it. The header shows the modifier chip and
  `question.stake` (what a correct answer earns). Solo questions (`soloPlayerId`)
  show «Отвечает <имя>» and only the reading bar (`buzz*` are null). `cat_transfer`,
  `auction` and every `final_*` phase have their own stage (`stageKeyOf`) and view;
  the final answer ring runs `answerStartsAt → answerEndsAt`; bets/answers appear
  only once the server reveals them (judged). The view field `final` is
  `GameView.finalView` (keyword). New events map to generated tones in `SoundCues`.
- **Models** are hand-written and tolerant (`data/models/json.dart` helpers): a
  missing field falls back to a default instead of crashing the TV.
- UI text is Russian; dark theme only.

## Git Worktrees — FORBIDDEN

- **Never use git worktrees.** Do not run `git worktree add` / `list` / `remove` / `prune`, do not create or work inside a separate worktree directory, and never suggest a worktree as a way to isolate work.
- Do not use any tool or agent "worktree" isolation mode (e.g. the `EnterWorktree` / `ExitWorktree` tools, or `isolation: "worktree"` when spawning an agent).
- Work directly in the existing repository clone. If another branch is needed, verify the tree is clean and switch in place with `git switch`.
