# CLAUDE.md — App clients (Flutter: Android, Windows, Linux, macOS)

## Rules

- **`docs/en/05-protocol.md` is authoritative.** REST, WebSocket messages, roles,
  phases, block splitting and LAN discovery follow it exactly. When the app and the
  protocol disagree, the app is wrong; protocol changes go through that file (and
  every implementation) first.
- **Theme = `DESIGN_MANIFEST.md`.** Colours, fonts and component rules live in
  `lib/core/theme.dart` (`AppColors`, `AppText`, `buildTheme`). Dark only. Never
  hard-code a colour outside the tokens.
- **No code generation.** Models are hand-written with lenient `fromJson`
  (`lib/data/models.dart`). No freezed / json_serializable / build_runner.
- **UI language is Russian.** All user-visible strings are Russian.
- Never show the answer on a player surface before the server sends it
  (`answerBlocks` is null for players until `reveal`).
- Times shown to people: device-local `YYYY-MM-DD HH:MM:SS` via `formatDateTime`
  (`lib/core/format.dart`); the server sends Unix ms UTC.
- One codebase for Android, Windows, Linux and macOS; every platform has every feature.
  Platform differences go through `lib/core/platform.dart` (`clientPlatform`, `isDesktop`,
  overridable in tests with `debugDefaultTargetPlatformOverride`) — never `dart:io`
  `Platform` checks scattered in features. Texts that name the device must read right
  on a computer too («компьютер» / «телефон»). Build with `make` (wraps `flutter`).
- Keep the Android app id `dev.svoyigra.mobile` (installed phones, `ANDROID_PACKAGE`,
  intent links); the desktop id is `dev.svoyigra.client`.
- One server runs many games. Every token belongs to one game + role and is stored
  per server + game + role (`Prefs.seats`, keyed by `GameSeat.key`: the PIN, or
  `id:<gameId>` for a screen watching from the public list).
- **The game PIN is the key to join** — never show or derive it where the server did
  not send it. `GET /api/games` and watch screens get `pin`/`link` = null; the public
  list only offers «Смотреть (экран)» (`POST /api/games/{id}/watch`). Never build a
  share link from missing data. «Выйти» always sends `leave` and
  forgets the token; the system back button only closes the screen (token kept).

## Stack

| Concern | Choice |
|---|---|
| State | `provider` + `ChangeNotifier` (`GameSocket`, `PackEditorModel`) |
| Navigation | plain `Navigator` / `MaterialPageRoute` |
| REST | `dio` (`lib/data/api.dart`; multipart upload progress, byte downloads) |
| WebSocket | `dart:io` `WebSocket` (`lib/data/socket.dart`) |
| Discovery | `RawDatagramSocket` UDP broadcast (`lib/data/discovery.dart`) |
| Markdown | `flutter_markdown_plus` with `ExtensionSet.commonMark` (raw HTML shown as text) |
| Media | `video_player` (+ `fvp` backend on Windows/Linux, auto-registered; its native libs are excluded from the APK), `audioplayers`, `Image.network` |
| Files | `file_picker` (pick + system “save as”) |
| Storage | `shared_preferences` (`lib/core/prefs.dart`: last/recent servers, `GameSeat`s) |
| Device info | `device_info_plus`, `package_info_plus` (`lib/data/device.dart`) |
| Deep links | `app_links` (`main.dart`), parsing in `lib/data/deeplink.dart`; desktop scheme registration in `lib/data/url_scheme.dart` (`win32_registry` / `.desktop` file) |
| Sharing | `share_plus` (share sheet; hidden on Linux), `qr_flutter` (game QR) |
| Avatars | `image_picker` (gallery/camera; desktop: file only), `image` (square crop ≤ 512 px, JPEG) |

## Layout

```
lib/
  main.dart                 app, theme, Russian locale, deep-link listener
  core/                     theme.dart, format.dart, prefs.dart (servers, seats), ui.dart,
                            platform.dart (android / windows / linux / macos)
  data/                     models, api, socket, blocks (splitter), discovery, deeplink,
                            device (hello per OS), files, url_scheme (desktop svoyigra://)
  features/
    connect/                server discovery / manual address → server screen (my games,
                            live games to watch, join by PIN, create game) → game role step
    game/                   session (socket lifetime, close codes, leave), board, scoreboard,
                            blocks_view (markdown + media), question_panel, timer_bar,
                            settings_card, special (modifier splash, cat transfer, auction),
                            final_panel (themes, bets, answer, judging, results)
    player/                 player screen, buzzer
    host/                   host screen (tabs: game / settings) — runs the game only
    screen/                 read-only screen role (autoplay media, lobby PIN + QR)
    admin/                  admin screen (tabs: game / players / packs), per-player card
    library/                shared pack library (lock, copy, import/export, load_pack)
    editor/                 pack editor (rounds → categories → questions), media manager
    avatar/                 Avatar widget (initials fallback, MediaBase URL prefix),
                            «Мой аватар» editor (pick → crop → POST /api/avatar)
test/                       splitter, models, deep links, timers, markdown toolbar, prefs,
                            special questions + final (FakeSocket records commands),
                            board layout (10×10, 6×5 at phone/tablet/desktop), avatars,
                            utils, widget smoke tests, desktop (platform, .desktop entry)
android/                    Gradle app (App Links host, fvp libs excluded)
windows/ linux/ macos/      runners: title «Своя игра», min window 400×560, single instance
                            (a second launch hands its svoyigra:// link to the open window),
                            icons from the web favicon; macOS entitlements + Info.plist scheme
```

## Roles in the app

- **Admin** (creates the game or joins with the admin PIN): PIN, share link (copy,
  share sheet, QR), `update_game`, `close_game`, `load_pack`, all settings, game file
  export/import, players (scores, offsets, metrics, kick), pack library + editor.
- **Host**: `start_game` and running the game; waits for the admin to load a pack.
- **Player**, **Screen**: as in the protocol. Locked packs: no edit/delete, only
  «Редактировать копию» (`POST /packs/{id}/copy`).

## Share links / App Links

- `svoyigra://join?server=<base>&pin=<PIN>` always works. Desktop: Windows and Linux
  register the scheme for the current user on every start (`registerUrlScheme`); on
  Linux the starting link is `main(args)`'s first argument, later ones come from
  `app_links` (`GApplication` `command-line`). Window titles must stay «Своя игра» —
  the Windows runner finds the running instance by it.
- `http(s)://<APP_LINK_HOST>/g/<PIN>` is an App Links filter whose host comes from the
  Gradle property / env `APP_LINK_HOST` (`make build-apk APP_LINK_HOST=igra.example.com`).
  Unset → `app-links.invalid`, which never matches.
- Verification: the server serves `/.well-known/assetlinks.json` from
  `ANDROID_CERT_SHA256`. Get the fingerprint of the signing key with `make cert-sha256`
  (debug keystore) or `keytool -list -v -keystore <release.jks> -alias <alias>`.

## Conventions

- `GameSocket` holds the latest `GameView`; screens `context.watch<GameSocket>()` and
  render by `phase`. Commands go through `socket.command(type, data)`; server `error`
  messages surface as toasts in `SessionScreen`.
- Countdowns use server time: `socket.serverNow` (clock offset from every `state`).
  The buzzer never opens on the client clock.
- Editor mutations apply the server's response to the local `Pack` tree
  (`PackEditorModel`); they never re-fetch the whole pack.
- The editor preview uses `splitBlocks` (`lib/data/blocks.dart`), which mirrors the
  server's rule exactly; keep `test/blocks_test.dart` in sync with it.
- Relative media URLs are prefixed with the server base URL (`Api.absolute`).
- Media playback (protocol §3) is decided by `MediaMode` in `game/blocks_view.dart`
  and is the same for question, answer and comment blocks: `host` (and the editor
  preview) — controls, no autoplay; `player` — muted autoplay video with controls,
  audio chip with play; `screen` — autoplay with sound (answer media mount at
  `reveal`, so they start then). `BlocksView.scope` keys the players per question and
  block list so they are disposed when the blocks change.
- Special questions and the final (protocol §4.5–4.6) are rendered by shared widgets
  in `game/special.dart` and `game/final_panel.dart`; player, host and screen only
  choose the role flags (`me`, `host`, `canGive`, `hostControls`). Every `switch` over
  `Phase` is exhaustive — a new phase must be handled in the player, host and screen
  views. Solo questions (`soloPlayerId`) show no buzzer, only «Отвечает …».
- The board is rotated (DESIGN_MANIFEST «Board»): one row per category with a fixed
  name column; geometry comes from the pure `BoardLayout.of` (tested). Values sit in a
  `FittedBox(scaleDown)` capped at 45 % of the cell height — never let a value overflow.
- Avatars: relative URLs are resolved by `MediaBase` (provided by `SessionScreen`);
  always render `Avatar` (initials fallback) — never a bare `Image.network` for people.
  Cropping/scaling is the pure `squareAvatar` (`data/avatar_image.dart`), run via `compute`.
- `GameView.final` is `finalView` in Dart (`final` is a keyword).
- Markdown toolbar logic lives in pure functions (`editor/markdown_format.dart`,
  tested in `test/markdown_format_test.dart`); the widgets only call them.

## Commands

```bash
make deps | analyze | test | run | build-apk | build-apk-debug | cert-sha256
make build-apk APP_LINK_HOST=igra.example.com   # with App Links for that host
make build-linux | build-windows | build-macos  # each on its own OS
make run DEVICE=linux                           # or windows / macos / an Android id
```

CI: `.github/workflows/builds.yml` (repo root) builds Windows, macOS, Linux and the APK;
keep its paths (`build/windows/x64/runner/Release`, `SvoyIgra.app`, Linux `bundle`) in
sync with the runners and `Makefile`.

## Git Worktrees — FORBIDDEN

- **Never use git worktrees.** Do not run `git worktree add` / `list` / `remove` / `prune`, do not create or work inside a separate worktree directory, and never suggest a worktree as a way to isolate work.
- Do not use any tool or agent "worktree" isolation mode (e.g. the `EnterWorktree` / `ExitWorktree` tools, or `isolation: "worktree"` when spawning an agent).
- Work directly in the existing repository clone. If another branch is needed, verify the tree is clean and switch in place with `git switch`.
