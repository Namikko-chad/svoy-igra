# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [6.3.0] - 2026-10-26

### Added

- **`LICENSE`** — the project is now MIT-licensed.
- **`README.md` rewritten for search** (what the game is, features, Docker quick start, downloads from Releases, FAQ, badges) and a Russian **`README.ru.md`**, linked to each other.
- **`llms.txt`** at the repository root: a short description and links to the key docs for AI assistants and crawlers.
- `CITATION.cff`, `CONTRIBUTING.md`, `SECURITY.md` and issue templates (`.github/ISSUE_TEMPLATE/`: bug report, feature request), so GitHub shows a complete community profile.
- The web client's `index.html` has a page description, Open Graph tags and a schema.org `WebApplication` block, so search results and shared links show a proper title and text; `frontend/public/robots.txt` allows indexing only the start page, not game pages (`/g/`) or `/api/`. Described in `docs/{en,ru}/09-frontend-structure.md`.

## [6.2.0] - 2026-10-26

### Added

- **Desktop apps for Windows, Linux and macOS** with every feature of the Android app (player, host, admin with pack library and editor, screen). They come from the same Flutter project (`clients/`): `make -C clients build-windows`, `build-linux`, `build-macos`, each built on its own OS.
  - Video plays on Windows and Linux through `fvp` (libmdk), on macOS through AVFoundation; LAN discovery, file import/export and avatars (picked from a file) work as on the phone.
  - Desktop apps register `svoyigra://` share links for the current user on start (Windows registry `HKCU\Software\Classes\svoyigra`; Linux `~/.local/share/applications/dev.svoyigra.client.desktop`, which also adds a menu entry with an icon; macOS `Info.plist`). A link opened while the app runs goes to the open window instead of starting a second copy.
  - Window «Своя игра», 1280 × 800 at start, at least 400 × 560; app icon from the web favicon.
  - `hello.platform` can now be `windows`, `linux` or `macos`, so the admin's player card shows the computer's OS, model and display size (`docs/{en,ru}/05-protocol.md` §4.1).
- Root `make linux` builds the Linux desktop app.
- **Builds on GitHub Actions** (`.github/workflows/builds.yml`), started by hand or by a `vX.Y.Z` tag (which also publishes a GitHub release): Windows `.zip`, macOS universal `.zip`, Linux `.tar.gz`, the phone APK and the TV APK, versioned with the server version. APKs are signed with the key from the `ANDROID_DEBUG_KEYSTORE` secret so installed apps update in place; the optional `APP_LINK_HOST` variable enables App Links in the phone APK. Described in `docs/{en,ru}/03-getting-started.md`.

### Changed

- **The `mobile/` directory is now `clients/`** (one app for phones and computers); the Dart package is `svoy_igra_client`, the root target `make apk-mobile` is now `make apk-clients`. The Android app id stays `dev.svoyigra.mobile`, so installed phones update in place.
- `docs/{en,ru}/11-mobile.md` is now `11-clients.md` and describes all four platforms; getting started, introduction, architecture, protocol and design-system pages name the apps instead of «mobile».
- Texts that named the phone read right on a computer: «Серверы не найдены. Проверьте, что компьютер в той же сети…», «Компьютер покажет табло…», «Выбрать файл» for the avatar, «Фото и видео» in the media upload menu.
- On Linux the admin's invite card shows only «Копировать» (there is no system share menu).
- `userAgent` in `hello` is now `svoy-igra-client/<version> (<os>; <model>)`.

## [6.1.4] - 2026-10-26

### Added

- **`docs/{en,ru}/13-pack-format.md`** is a complete guide to generating `.dub` packs for people and other agents. It covers:
  - the archive layout, the full `pack.sqlite` schema and the `meta` keys;
  - structure rules (≤ 10 categories, values, a final round with one question per theme);
  - markdown and `media:` references, media kinds by extension, media name rules and limits;
  - exactly what the importer checks and what it does not;
  - a tested Python reference generator using only the standard library, and a checklist.
- Linked from the table of contents, `07-game-and-packs.md`, `README.md` and the documentation map in `CLAUDE.md`.

## [6.1.3] - 2026-10-26

### Fixed

- The MikroTik instructions (`docs/{en,ru}/03-getting-started.md`) no longer set a Cyrillic `SERVER_NAME`. RouterOS keeps only the low byte of each character in `/container/envs`, so phones and TVs showed «!2>O 83@0» instead of «Своя игра». The docs now explain this and recommend leaving the name unset or using Latin letters.

## [6.1.2] - 2026-10-26

### Fixed

- **Pack import, pack export and game file import failed with `500` in the Docker/MikroTik image.** The `scratch` image has no `/tmp`, and the server staged those files there (`open /tmp/upload-…: no such file or directory`). Temporary files now go to `DATA_DIR/tmp` (created and cleaned on start, on the data disk); the image also sets `TMPDIR=/data/tmp`.
- `backend/app/server_test.go` now runs the full game with a nonexistent `TMPDIR`, so a return to the system temp dir fails the tests.

## [6.1.1] - 2026-10-26

### Fixed

- The MikroTik instructions in `docs/{en,ru}/03-getting-started.md` gave the container an address inside the router's default DHCP pool, which could clash with a client. They now use `192.168.88.5` (outside the pool) and also say that containers need an ext4 disk.

## [6.1.0] - 2026-10-26

### Added

- **Image for MikroTik routers** (RouterOS 7.21+, arm64): `make mikrotik` builds `build/svoy-igra-arm64.tar`.
  - It is a `docker save` archive of the `scratch` image, about 12 MB, running as `0:0` because RouterOS mounts are owned by root. Upload it and add it with `/container/add file=…`.
  - `docs/{en,ru}/03-getting-started.md` give the RouterOS commands: a veth in the LAN bridge (so LAN discovery works), env and mount lists, start-on-boot, and how to update.

### Changed

- The root `Dockerfile` cross-compiles: the build stages run on the build machine's platform (`--platform=$BUILDPLATFORM`), so non-native images build without emulation.
- The `APP_USER` build argument sets the uid:gid the server runs as; the default stays the unprivileged `10001:10001`.

## [6.0.0] - 2026-10-26

### Added

- `svoy-igra healthcheck` (`backend/main.go`) exits 0 when the local server answers `/api/health`. The container uses it as its health check because the image has no shell.

### Changed

- **BREAKING:** Docker now builds **one image** from the root `Dockerfile` (about 13 MB instead of 21 + 54 MB):
  - the web client is built with pnpm and the Go server is built statically;
  - the final stage is `scratch`, running as uid 10001, with `/data` as a volume;
  - the server serves the API, the WebSocket and the site on `:3050` (`STATIC_DIR=/app/web`).
- **BREAKING:** `docker-compose.yml` has a single `app` service on `:3050` (+ `3051/udp`); the web client is no longer on `:3000`.

### Removed

- **BREAKING:** `backend/Dockerfile`, `frontend/Dockerfile`, `frontend/nginx.conf.template` and the nginx image.

## [5.2.0] - 2026-10-25

### Added

- **Avatars for players and the host** (`backend/app/game/avatar.go`, `POST`/`DELETE /api/avatar`, `GET /api/games/{gameId}/avatars/{file}`):
  - Each player and the host uploads their own picture (PNG/JPEG/WebP/GIF, ≤ 2 MB). Clients crop it to a square of at most 512 px.
  - Avatars show in scoreboards, the answering highlight, auctions, the final and standings, with initials when there is none. The screen shows the host's avatar next to «Ведущий».
  - The admin can remove any avatar (`clear_avatar`). Files are stored per game and deleted with it; their URLs never contain the game PIN.
- The final answer timer has a start time, `final.answerStartsAt`, so every client draws the full timer bar.

### Changed

- **The board is rotated:** one row per category with the name in a fixed left column and values left to right, on the web, the phone and the TV. Values shrink to fit their cells, so 10×10 boards with four-digit values no longer overflow. On phones the value cells scroll sideways.

## [5.1.0] - 2026-10-25

### Added

- **Final round with bets** (`backend/app/game/final.go`, protocol §4.6):
  - A pack round can be marked `kind: "final"` (`rounds.kind`, added automatically to older packs). Each final theme holds exactly one question (`409 final_one_question`).
  - Players with a positive score take part. They strike out themes in turn, lowest score first, then make secret bets (1…score).
  - They type answers within `finalSeconds` (default 60). The host judges each finalist (±bet), then the correct answer and the results are shown to everyone.
  - New phases `final_themes`, `final_bets`, `final_question`, `final_judging` and `final_reveal`, and commands `final_remove_theme`, `final_bet`, `final_answer`, `final_close_bets`, `final_close_answers` and `final_judge`. The final's progress survives a server restart.
- **Random special questions** (`backend/app/game/special.go`, protocol §4.5): at the start of each normal round the server hides «Кот в мешке», «Аукцион», «Вопрос без риска» and «Двойная стоимость» in random cells. `settings.modifiers` sets 0–5 of each per round, default 1.
  - **Кот в мешке:** the question goes to another player, who answers alone; wrong loses the value.
  - **Аукцион:** players bid in turn with a raise, «Ва-банк» or «Пас»; the winner answers alone for the bid.
  - **Вопрос без риска:** only the chooser answers; ×2, nothing lost when wrong.
  - **Двойная стоимость:** ×2 with the usual buttons.
  - New phases `cat_transfer` and `auction`, the state fields `question.modifier`/`stake`, `soloPlayerId` and `auction`, and new events.
- **Public game list without PINs:** `POST /api/games/{id}/watch` lets a screen show a game picked from `GET /api/games` without the game PIN. Such a screen never receives the PIN or share link.
- **Markdown toolbar** in the pack editor (web and mobile) for the question, answer and comment: bold, italic, heading, lists, quote, link, and «Медиа» (pick or upload a file and insert it at the cursor of that field).
- Clients (web, mobile, TV) cover every new phase. Each has a modifier splash, an auction panel and final screens; the host can act on behalf of the chooser and close bidding, bets and answers. Settings now include the special-question counts and the final answer time, and the pack editor has a «Финал» switch per round.

### Changed

- Media in the answer and in the host comment plays like question media on every client. The screen autoplays it when the answer is revealed and stops the question's media; the editor preview plays media too.

### Security

- `GET /api/games` no longer returns game PINs or share links (`pin`/`link` are `null`; `GameInfo` gains `id`). The PIN stays the key for joining as player, host or admin.

## [5.0.0] - 2026-10-25

### Added

- **Many games on one server** (`backend/app/game/manager.go`, `identity.go`):
  - `POST /api/games` creates a game without any password. The creator picks an admin PIN (4–8 digits), becomes the game's admin and gets a 6-digit game PIN and a share link `<base>/g/<PIN>`.
  - `GET /api/games/{pin}` and `POST /api/games/{pin}/join` with role `player` (name), `host` (one at a time, `409 host_taken`), `screen` or `admin` (admin PIN).
  - `GET /api/auth/me` answers the token's game and role.
  - Each game is saved to `DATA_DIR/games/<id>.json` and restored on restart.
- **Idle games are deleted:** a game with nobody connected for `GAME_IDLE_MINUTES` (60) is deleted with its tokens. `MAX_GAMES` (100) caps simultaneous games.
- **`GET /api/games`** lists the live games; the TV app picks the game to show from it.
- **Locked packs:**
  - `POST /api/packs/{id}/lock` locks a pack for good; every change or deletion then answers `409 pack_locked`. The lock is stored in the pack and travels in `.dub`.
  - `POST /api/packs/{id}/copy` makes an editable copy, used by «Редактировать копию».
  - The operator command `svoy-igra unlock-pack <id>` removes the lock.
- **Commands for every role:**
  - all roles: `leave` gives up the seat; for the host it frees the host slot at once;
  - admin: `update_game` (rename, change the admin PIN) and `close_game`, which closes every socket with `4004`.
- **Share links open the mobile app:**
  - `svoyigra://join?server=…&pin=…` and the «Открыть в приложении» button on `/g/<PIN>`.
  - Android App Links for `APP_LINK_HOST`, set at build time (`make -C mobile build-apk APP_LINK_HOST=…`).
  - The server answers `/.well-known/assetlinks.json` from `ANDROID_PACKAGE` / `ANDROID_CERT_SHA256`.
- **Web client** (`frontend/`): game-scoped routes `/g/:pin`, `/g/:pin/{play,host,admin,screen}` and `/g/:pin/admin/packs[/:id]`. Game creation and the role step, «Выйти», and an admin share card with PIN, link, QR and Web Share.
- **Mobile app** (`mobile/`): server screen with «Мои игры», «Игры на сервере», «Войти в игру» and «Создать игру»; the role step; the screen role; deep links; an admin share link with share sheet and QR.
- **TV app** (`tv/`): a live games list refreshed every 5 s and PIN entry with a D-pad digit pad. It reconnects to the saved game after a restart, returns to the list on `4004`/`4001`, and has a «Сменить игру» / «Сменить сервер» menu.

### Changed

- **BREAKING:** pack selection (`load_pack`), the pack library and editor, and game file export/import (`/api/game/*`) belong to the **admin**. Pack endpoints accept the admin token of any game, because the library is shared. The host starts and runs the game; both host and admin may change timers.
- **BREAKING:** WebSocket auth is token-only (`/api/ws?token=…`, no `?role=screen`). Every `state` carries `game {pin, title, link, hostTaken, hostConnected}`, and the admin's view now includes the pack and round but still no board or question.
- **BREAKING:** the game file export holds only game content; the game's identity and admin secrets stay on the server.
- Share links use `WEB_URL`, else the creating page's `Origin`, else the request host. nginx and the Vite dev proxy pass the browser's `Host` / `X-Forwarded-Host` through and proxy `/.well-known/`.
- The web client's Docker build disables Node's network-family autoselection, so `pnpm install` no longer times out on slow networks.

### Removed

- **BREAKING:** the server-wide `HOST_PIN`, `ADMIN_PIN` and `SECRET` settings, `POST /api/auth/login`, `POST /api/players/join` and the single `DATA_DIR/game.json`.

## [4.0.0] - 2026-10-25

The repository is now «Своя игра», a Jeopardy-style quiz game, instead of the
generic service template.

### Added

- **Game server** (`backend/app/game`, `backend/app/ws`): one in-memory game with phases lobby → board → question → answering → reveal → round_end → finished. The server pushes each player's «Дать ответ» button open at the end of the reading timer (default 10 s); the first press to reach the server answers. The host judges; a wrong answer reopens the buttons for the others; an optional penalty subtracts the value. Every socket gets its own state view: players and the screen never see the answer before reveal, the admin sees players only. The protocol is in `docs/{en,ru}/05-protocol.md`.
- **Roles:** player (joins by name, `POST /api/players/join`), host and admin (PIN, `POST /api/auth/login`; env `HOST_PIN`, `ADMIN_PIN`), screen (`/api/ws?role=screen`, no login).
- **Admin tools** (WebSocket): `adjust_score`/`set_score`, a per-player button shift `set_buzz_offset` (−5000…10000 ms), optional automatic latency compensation, kick. The admin sees per-player device info, RTT last/avg/jitter (ping every 2 s), last-seen time and reaction statistics.
- **Question packs without a database server** (`backend/app/packs`): a pack is `DATA_DIR/packs/<id>/pack.sqlite` + `media/`, imported and exported as `.dub` (a ZIP of both; `POST /api/packs/import`, `GET /api/packs/{id}/export`). REST endpoints create, edit, reorder and delete rounds (≤ 10 categories each), categories, questions and media for the pack editor. Media is served with HTTP Range by `GET /api/packs/{id}/media/{name}`.
- **Markdown questions with media:** `![](media:file)` becomes an image, video or audio block depending on the file extension. The server sends questions already split into blocks.
- **Game file** (`DATA_DIR/game.json`): players, scores, devices, button shifts, statistics, played questions, settings and history. Saved within a second of every change and restored on start; the host downloads it with `GET /api/game/export` and uploads it with `POST /api/game/import`.
- **LAN discovery** (`backend/app/discovery`): the server answers the UDP broadcast `SVOY_IGRA_DISCOVER` on `DISCOVERY_PORT` (3051) with its name and port.
- `GET /api/info` returns the server name, version and `webUrl` (env `WEB_URL`), which screens use for the join link/QR. `STATIC_DIR` serves a built web client from the backend port.
- **Web client** (`frontend/`, Vue 3 + Vite):
  - routes `/` (join), `/play`, `/host` (game control, settings, game file), `/host/packs` (library), `/host/packs/:id` (pack editor with live preview and media manager), `/admin`, `/screen` (big screen with QR);
  - nginx Docker image that proxies `/api` and the WebSocket.
- **Mobile app** (`mobile/`, Flutter, Android `dev.svoyigra.mobile`): the same features as the web client — player, host with the full pack editor and file import/export, admin. It finds servers on the LAN or takes a typed address.
- **TV app** (`tv/`, Flutter, Android TV `dev.svoyigra.tv`): a read-only screen with a leanback launcher banner. It shows the lobby with QR, the board, questions with autoplayed video/audio, timers, scores and standings. It auto-connects to a discovered or saved server and is driven with the D-pad.
- `DESIGN_MANIFEST.md`: the game's visual language (deep-blue stage, gold values, buzzer states), implemented by all three clients.
- Docs (`docs/{en,ru}`): getting started, architecture, protocol, backend structure, game rules and pack authoring, web/mobile/TV structure, design system.
- Backend integration test `backend/app/server_test.go` plays a full game over HTTP + WebSocket.

### Changed

- **BREAKING:** the backend uses only the Go standard library HTTP server, `modernc.org/sqlite` and `coder/websocket`. The Go module is `svoy-igra`, the binary is `bin/svoy-igra`, and the configuration is in `backend/.env.example`.
- **BREAKING:** the web client is plain Vue 3 + Vite (`pnpm dev` on :3000 proxies `/api` to :3050) instead of Nuxt.
- `docker-compose.yml` runs the backend (data in the `game-data` volume) and the web client; the root `Makefile` has `backend`, `frontend`, `test`, `apk-mobile`, `apk-tv`, `up`, `down`.
- `CLAUDE.md` files of the repository and of every app describe the game project.

### Removed

- **BREAKING:** the template backend is removed: PostgreSQL, Redis, RabbitMQ, migrations, Swagger, auth-gateway/RBAC, settings, events, notifications, messengers-gateway clients, scheduler.
- **BREAKING:** the Nuxt frontend and the `@bloodheaven/frontend-shared` design layer are removed, along with `DESIGN_SPECIFICATION.md`.
- The template Flutter code (auth, FCM, socket.io) and the non-Android platform folders of `mobile/` and `tv/` are removed.
- Template docs `07-backend-modules`, `28-roles-and-permissions`, `31-rest-api`, `32-swagger`, `33-webhooks` are removed.

## [3.0.1] - 2026-10-17

### Fixed

- **Design system: frontend-shared v0.10.0** ([frontend/package.json](frontend/package.json)). Every control now has one of the manifest's heights: form fields (`UiFormInput`, `UiFormSelect` at any size, `UiHmSelect`) are 36 px with 12 px mono type and an 8 px radius, the same as a bare `.hm-input` beside them (they were 38 px, or 48 px at size `sm`, and `UiHmSelect` used 13 px sans type); segmented controls are 30 px (26 px at `sm`) instead of 32/28 px, so they line up with the 30 px buttons; the table's column toggle is 30 × 30. On a phone every field is exactly 48 px and set in 16 px type.

## [3.0.0] - 2026-10-17

### Changed

- **BREAKING: the gateway used by notification integrations is configured as `MESSENGERS_GATEWAY_URL`, `MESSENGERS_GATEWAY_API_KEY` and `MESSENGERS_GATEWAY_TIMEOUT` only** ([backend/app/config/config.go](backend/app/config/config.go): `config.MessengersGateway`, used by [backend/app/notifications/service/service.go](backend/app/notifications/service/service.go); `backend/.env.example`). The `NOTIFIER_TELEGRAM_URL` / `NOTIFIER_SLACK_URL` / `NOTIFIER_*_API_KEY` overrides are no longer read, and `NOTIFIER_REQUEST_TIMEOUT` is now `MESSENGERS_GATEWAY_TIMEOUT` (same default, `5000` ms). Telegram and Slack integrations keep working unchanged when `MESSENGERS_GATEWAY_URL` / `_API_KEY` were set; a deployment that relied on the `NOTIFIER_*` names must rename them.
- **The "Show toast for every backend request" setting now defaults to off** ([frontend/composables/use-request-toast-preference.ts](frontend/composables/use-request-toast-preference.ts)). It shipped defaulting to on, so a loader-then-checkmark toast popped up for every backend call on every page for anyone who had never touched the Settings toggle. A choice already saved in the browser is kept; only the un-set default flips.

### Removed

- **BREAKING: the env-configured `notifier` module** (`backend/app/notifier`, `NotifierPackage`). It sent every system event to one Telegram chat and one Slack channel set by `NOTIFIER_TELEGRAM_CHAT_ID` / `NOTIFIER_SLACK_CHANNEL`, and logged "telegram/slack channel disabled" at every boot where they were unset. Alerts are delivered by the `notifications` module's integrations through messengers-gateway; system events are still recorded and broadcast live by `app/events`, which lost its notifier hook (`SetNotifier`) ([backend/app/server.go](backend/app/server.go), [backend/app/events/service](backend/app/events/service)). `NOTIFIER_TELEGRAM_CHAT_ID`, `NOTIFIER_SLACK_CHANNEL` and the other `NOTIFIER_*` variables are ignored.
- **`SITE_URL` (backend)**: only the notifier read it, to build deep links in its messages. The frontend's `NUXT_PUBLIC_SITE_URL` is unaffected.
- **The `notifier_telegram_disabled_types` / `notifier_slack_disabled_types` setting keys** ([backend/app/settings/interfaces/interfaces.go](backend/app/settings/interfaces/interfaces.go), [frontend/api/settings.api.ts](frontend/api/settings.api.ts)): the per-channel blacklists the notifier read. Rows already stored stay in the settings table and are read by nothing.
- **Docs**: `33-webhooks.md` rewritten around what the code does (event history + broadcast, the notification integrations, the gateway env, the real REST routes), and the notifier dropped from `01-introduction.md`, `02-table-of-contents.md`, `04-architecture.md` and `06-backend-structure.md` in both languages, the in-app copy under [frontend/public/docs](frontend/public/docs) included; `README.md` and the docs map in `CLAUDE.md` follow.

### Fixed

- **`PORT` now sets the frontend's port in every mode, not only under `pnpm development`** ([frontend/nuxt.config.ts](frontend/nuxt.config.ts), [frontend/server/plugins/listen-port.ts](frontend/server/plugins/listen-port.ts), [frontend/Dockerfile](frontend/Dockerfile), [frontend/.env.example](frontend/.env.example)). The built server (`node .output/server/index.mjs`) reads `PORT` only from its own environment and otherwise listens on `3000`, so a build made with another `PORT` in `.env` still answered on `3000`. `pnpm build` now saves the build-time `PORT` as `runtimeConfig.listenPort`, and a Nitro plugin uses it as the default before the server starts listening. The Dockerfile takes `PORT` as a build arg (default `3000`) for both the build and production stages and `EXPOSE`s it. A `PORT` or `NITRO_PORT` set on the running process still takes precedence. The compose stack is unchanged: it pins `PORT: "3000"`, which the nginx upstream and the published `3000:3000` mapping expect.
- **Coming back to an idle tab no longer signs you out** ([frontend/stores/auth.store.ts](frontend/stores/auth.store.ts)). After an idle spell the access token has expired, so the first request or WebSocket reconnect refreshes it, and any failure of that refresh dropped the tokens: a laptop waking up before its network is back, a `502` during a deploy, an opaque `422`. Now only a `401` from the refresh endpoint ends the session. Any other failure keeps the tokens, and the next request retries the refresh.
- **A request is replayed after a `401` only when the refresh it triggered succeeded** ([frontend/plugins/01.api.ts](frontend/plugins/01.api.ts)), as auth-gateway already does. With the tokens now surviving a failed refresh, the old replay would have repeated the same `401`.
- Tests: network error, `422`/`502`/`503` and `401` on refresh in [frontend/tests/unit/stores/auth.store.test.ts](frontend/tests/unit/stores/auth.store.test.ts).
- **`utils` bumped to v0.17.1** ([backend/go.mod](backend/go.mod)): an auth gateway that cannot answer — unreachable, throttled, failing — is no longer reported as a rejected token. Authenticated routes answer `503` instead of `401`, and `POST /api/auth/oauth2/refresh` answers the opaque `422` instead of `401` unless the gateway actually refused the grant, so neither signs the user out over an outage.

## [2.0.0] - 2026-09-27

Ships with `utils` bumped to **v0.17.0** ([backend/go.mod](backend/go.mod)) — the `rbac`
package without role bindings.

### Changed

- **BREAKING: no role holds any permission by default.** Only `superAdmin` and `service` pass every check; `admin`, `default`, `guest` and any custom role hold exactly the grants an operator gives them, starting from none. After deploy every route answers `403` to everyone but a superAdmin until the roles are granted what they need on the permissions page — and at first only a superAdmin can do that. Rights the roles used to get from the catalog are **not** migrated into grants; grants operators already created stay as they are.
- **BREAKING: the permissions editor and the grants API require `access.manage`** instead of the `admin`/`superAdmin` role ([backend/app/server.go](backend/app/server.go): `rbac.RegisterRoutes(server.Router)` with no role guard). `GET · POST · DELETE /api/permissions/grants` and `GET /api/permissions/users` answer `403` to an `admin` who was not granted it; `GET /api/permissions/me` and `GET /api/permissions/roles` stay open to any signed-in principal. The key is declared by the `utils/rbac` package for every catalog, so a service never declares it itself.
- **The frontend gates the permissions page, its nav link and its route on `access.manage`** ([frontend/stores/permissions.store.ts](frontend/stores/permissions.store.ts), [frontend/constants/route-gates.ts](frontend/constants/route-gates.ts), [frontend/utils/route-access.ts](frontend/utils/route-access.ts), new `ACCESS_MANAGE` in [frontend/constants/permissions.ts](frontend/constants/permissions.ts)). Every route gate is now a permission key; the role-based `GRANT_MANAGER_ROLES` gate is gone, so revoking the grant moves the person off the open page live.
- **Every cell of the permission matrix is a plain, editable grant** ([frontend/components/permissions/PermissionMatrix.vue](frontend/components/permissions/PermissionMatrix.vue), [frontend/pages/admin/permissions.vue](frontend/pages/admin/permissions.vue)). The locked "from role" state is gone with the bindings it showed. On the Users tab a person whose primary role is a bypass role (superAdmin, service) gets a note that their grants change nothing, instead of a matrix that looked all-held.
- **Permission copy rewritten in every locale** ([frontend/i18n/locales](frontend/i18n/locales)): the page description says no role holds anything until granted, and the forbidden message names `access.manage` instead of "administrators".
- **Docs teach the grants-only model** ([docs/en/28-roles-and-permissions.md](docs/en/28-roles-and-permissions.md), [docs/ru/28-roles-and-permissions.md](docs/ru/28-roles-and-permissions.md), `09-frontend-structure.md` in both languages, the module route template in [backend/CLAUDE.md](backend/CLAUDE.md), now `rbac.Require(rbaccatalog.…)`), and the in-app copy under [frontend/public/docs](frontend/public/docs) is refreshed to match, changelog included.

### Removed

- **Role bindings in the catalog** ([backend/app/rbaccatalog/catalog.go](backend/app/rbaccatalog/catalog.go)): the `Bindings` map that gave `default` and `admin` their rights is gone; the catalog declares only what the service enforces, and its doc comment tells a new service never to gate on a role name. The `bindings` field left `GET /api/permissions/roles` and the frontend's `PermissionRoleDTO`, and the `permissions.matrix.fromRole` string left every locale.

## [1.2.3] - 2026-09-27

### Fixed

- **A user's role in another product no longer decides what they may do here** (`utils` bumped to `v0.16.1`, [backend/go.mod](backend/go.mod)). auth-gateway narrows a token's roles to the System Access role of the service it was issued for, and `goauth` cached that narrowed answer in the platform-wide `bh:user:<userId>` record, which every service reads. A `guest` seat in one product therefore turned into a 403 on every guarded route here (a `default` user was refused `projects/list`), and an `admin` seat into admin rights here, for up to 15 minutes. The roles now live in the token's own cache entry; the account record only marks the cache as still valid, so a role change in auth-gateway still applies on the next request.

## [1.2.2] - 2026-09-18

### Changed

- **`utils` bumped to `v0.16.0`, and the RBAC package is told which events exchange to use** ([backend/go.mod](backend/go.mod), [backend/app/server.go](backend/app/server.go)). The release is what makes the grants page work end to end: a grant with no `resourceId` now satisfies `rbac.Require` (it only satisfied `RequireOn` before, so a granted permission answered 403 on the route behind it), role subjects are validated, a repeat create is idempotent, `GET /permissions/roles` carries `bypass`/`bindings` so the matrix can lock what a role already gives, and `GET /permissions/users` moved behind the admin guard. `rbac.Init` now receives `config.Rabbit.EventsExchange`: the package defaults to `events`, so a non-default `EVENTS_EXCHANGE` would have sent permission events to an exchange nobody consumes. New services copied from this template inherit both.
### Fixed

- **A permission change in another product no longer makes this app re-read `/permissions/me`**
  ([frontend/stores/permissions.store.ts](frontend/stores/permissions.store.ts), the new
  [frontend/utils/permission-events.ts](frontend/utils/permission-events.ts) and
  [frontend/constants/permissions.ts](frontend/constants/permissions.ts); docs 28 in both
  languages, mirrored into `frontend/public/docs`). A role-level grant change is broadcast
  platform-wide, and the store reloaded on any `permissions::` event without reading the
  payload — so an operator ticking twenty checkboxes in another dashboard fired twenty
  `/api/permissions/me` requests in every open tab of this one. The store now reads the
  event: an addressed `permissions::updated::{userId}` always reloads (the gateway delivers
  it to that account alone), a broadcast naming a `serviceSlug` reloads only when the slug
  is this service's (`RBAC_SERVICE_SLUG`, equal to `ServiceSlug` in
  `backend/app/rbaccatalog/catalog.go`) or `*`, and a broadcast naming no service —
  auth-gateway's own `{role}` payload — still reloads, because a role change can alter what
  any binding means here. A reload that does happen still re-applies the route gates to the
  open page. Covered by `frontend/tests/unit/utils/permission-events.test.ts` and three new
  cases in `frontend/tests/unit/stores/permissions.store.test.ts`.

## [1.2.1] - 2026-09-17

### Security

- **A duplicated permission grant can no longer survive being un-ticked**
  ([backend/migrations/000002_permission_grants_unique.up.sql](backend/migrations/000002_permission_grants_unique.up.sql)).
  `permission_grants` was created without a uniqueness rule, so the same grant could be
  stored twice — two clicks on one checkbox, or two concurrent `POST`s that both miss the
  handler's read-before-write. The matrix ticks the box once however many rows are behind
  it, while `DELETE /api/permissions/grants/:id` removes exactly one id: un-ticking it
  deleted one row and left its twin granting the same access, which an administrator had
  every reason to believe was gone. A grant with no `resourceId` satisfies an unscoped
  check as well as a scoped one, so the leftover row is live authorization, not a stale
  display. The migration deletes the duplicates already stored — keeping the oldest row of
  each `(subjectType, subjectId, resourceType, action, resourceId)` group, `"createdAt"`
  deciding and `id` breaking a tie — and then adds the unique index the other services
  already carry, with `COALESCE("resourceId", '00000000-0000-0000-0000-000000000000')` so
  that the "every object of this kind" scope collides with itself instead of slipping
  past on `NULL`. The down migration drops the index only: it does not resurrect the
  duplicates. The fix is in the template, so a service scaffolded from it starts with the rule rather than the bug. Docs 28 in both languages now state it.

## [1.2.0] - 2026-09-17

### Added

- **Permissions can be granted to a role, not only to a person** ([frontend/pages/admin/permissions.vue](frontend/pages/admin/permissions.vue), [frontend/components/permissions/](frontend/components/permissions/)). The page has a Roles tab fed by `GET /api/permissions/roles` and a Users tab with the directory picker; both edit the same matrix (`PermissionMatrix.vue`), one row per catalog resource and one `<UiCheckbox>` per action. A key the subject already holds through its role binding is checked and locked with a "from role" hint, and a `bypass` role (superAdmin, service) is shown as full access and cannot be selected — the backend refuses a grant to it anyway.
- **The page is open to admins** ([frontend/stores/permissions.store.ts](frontend/stores/permissions.store.ts), [frontend/layouts/default.vue](frontend/layouts/default.vue)): the new `canManageGrants` (superAdmin, or any held `admin` role) gates the nav link and the page, matching the `RequireRoles(admin, superAdmin)` guard the backend puts on the grants routes. It used to demand the primary role be `superAdmin`, so an admin saw no link and an empty page.
- **A permission change applies to the open page** ([frontend/stores/permissions.store.ts](frontend/stores/permissions.store.ts), [frontend/utils/route-access.ts](frontend/utils/route-access.ts), [frontend/constants/route-gates.ts](frontend/constants/route-gates.ts)). On a `permissions::` event the store re-reads `/api/permissions/me` and re-applies the route gates to the current path, navigating to `/` when access has just been taken away instead of leaving a page the visitor may no longer open painted until their next click. The gates moved out of the middleware into `constants/route-gates.ts` so navigation and the live re-check read one list, and a change announced during a read in flight schedules one more read after it.
- **Grants UI tests** ([frontend/tests/](frontend/tests/)): the API payload shape, the store (flat keys, single-object grants, admin detection, coalesced reloads, route re-check), `use-permission-grants.ts` and the matrix component, plus fixtures in `tests/fixtures/permissions.ts`.

### Fixed

- **Granting a permission no longer answers `400`** ([frontend/api/permissions.api.ts](frontend/api/permissions.api.ts)). `POST /api/permissions/grants` takes one flat `permission: "resource.action"` key (plus an optional `resourceId`); the frontend was still sending the long-gone `{resourceType, action}` pair and matching stored grants on those two fields, which the API never returns — so every checkbox rendered unchecked and every toggle was refused. The key is assembled and split in exactly one place now, [frontend/utils/permission-keys.ts](frontend/utils/permission-keys.ts).
- **A non-bypass user is no longer denied everything** ([frontend/stores/permissions.store.ts](frontend/stores/permissions.store.ts), [frontend/composables/use-permissions.ts](frontend/composables/use-permissions.ts)). `accountCanDo` read a `me.wildcard` map and a nested `specific[resource][id]` shape that `GET /api/permissions/me` stopped serving; every check fell through to `false` for anyone who was not superAdmin or service. It now matches the served `permissions: string[]` and `specific: Record<key, id[]>`.
- **The route gates name permissions this service declares** ([frontend/constants/route-gates.ts](frontend/constants/route-gates.ts)). They listed servers, projects, environments, secrets and audit logs — pages and permissions the template does not have — and gated the permissions page on a `__superAdmin__` sentinel. They are now `/admin/permissions` (grant managers), `/notifications` (`integration.read`) and `/monitor-settings` (`settings.read`), and a prefix matches only on a path boundary.

### Changed

- **The permissions page is translated and split into components** ([frontend/i18n/locales/en.json](frontend/i18n/locales/en.json), [de.json](frontend/i18n/locales/de.json), [ru.json](frontend/i18n/locales/ru.json)): a new `permissions.*` group and `nav.admin` / `nav.permissions` in all three locales replace the hardcoded English of the page and of the Admin nav group. The page itself is now a shell over `RolePicker`, `UserPicker`, `SubjectOption` and `PermissionMatrix`, and the matrix boxes are `<UiCheckbox>` rows (DESIGN_MANIFEST § 13.6) rather than bare inputs.
- Docs 28 and 09 in both languages describe the two tabs, the flat key, the locked bindings, the live re-check and the new `constants/route-gates.ts` / `composables/use-permission-grants.ts`.

## [1.1.0] - 2026-09-16

### Added

- **`@bloodheaven/frontend-shared` bumped to `v0.8.0`** ([frontend/package.json](frontend/package.json)). The layer now ships the platform's boolean controls — `<UiCheckbox>` (`.hm-check`, DESIGN_MANIFEST § 13.6) for a flag committed with a form and `<UiToggle>` (`.hm-toggle-row`, § 13.1–13.2) for a setting that applies at once — and this template consumes them everywhere, so every service copied from it starts on the canonical pattern.
- **Every form flag explains itself** ([frontend/i18n/locales/en.json](frontend/i18n/locales/en.json), [de.json](frontend/i18n/locales/de.json), [ru.json](frontend/i18n/locales/ru.json)): new `healthMonitor.form.isActiveHint` / `isMaintenanceHint`, `healthMonitor.selectResource` (the selection box's accessible name) and `generalSettings.showRequestToasts` / `showRequestToastsHint` keys in all three locales.

### Changed

- **Resource form flags are `<UiCheckbox>` rows** ([frontend/components/resource/Form.vue](frontend/components/resource/Form.vue)). Active, Send full error text and Maintenance Mode now sit in one `.hm-check-group`, each with a one-line hint of what the box does when it is on; Maintenance Mode uses `variant="warning"`. The page-local `.rf-checkbox` label style and the browser-drawn native boxes are gone.
- **Monitor list selection uses the shared `.hm-check__input`** ([frontend/components/resource/Table.vue](frontend/components/resource/Table.vue); docs 09 in both languages). The selection box is a real checkbox with an `aria-label` naming the monitor, and takes the row's status colour through the manifest's tone modifiers (`--ok` / `--error` / `--warning` / `--muted`) instead of the local `.hm-checkbox` copy. Clicking the box or the cell toggles the selection exactly once; the row itself still opens the monitor.
- **Incident "internal" flag and the permission matrix are real checkboxes** ([frontend/pages/incidents.vue](frontend/pages/incidents.vue), [frontend/pages/admin/permissions.vue](frontend/pages/admin/permissions.vue)). The incidents column was a `<button>` drawn as a box with no checked state or keyboard access; both are now bare `.hm-check__input` cells with `aria-label`s, keyboard-reachable, styled by the shared base.
- **Notification channel and request-toast switches are `<UiToggle>` rows** ([frontend/pages/notifications.vue](frontend/pages/notifications.vue), [frontend/pages/settings/index.vue](frontend/pages/settings/index.vue)). The hand-rolled `<button class="hm-toggle">` markup is replaced by the shared component (hidden `role="switch"` input, clickable label, focus ring); the integration's config label/value is the toggle's label/hint, and the request-toast setting's text is now translated.

### Removed

- The per-page checkbox CSS (`.rf-checkbox`, `.hm-checkbox*`, `.hm-checkbox-inline*`) and the `.nt-config__label` / `.nt-config__value` styles the shared primitives make redundant.

## [1.0.0] - 2026-09-13

### Changed

- **BREAKING: the frontend's realtime gateway variable is now `MESSENGERS_GATEWAY`** ([frontend/nuxt.config.ts](frontend/nuxt.config.ts), [frontend/utils/gateway-env.ts](frontend/utils/gateway-env.ts), [frontend/server/middleware/messengers-gateway-env.ts](frontend/server/middleware/messengers-gateway-env.ts), [frontend/Dockerfile](frontend/Dockerfile), [docker-compose.yml](docker-compose.yml), [frontend/.env.example](frontend/.env.example); docs 09 in both languages). It is the one name for the messengers-gateway origin the browser opens its events WebSocket against. `nuxt.config.ts` bakes it at build time and the server middleware applies it at runtime. `NUXT_PUBLIC_MESSENGERS_GATEWAY` and the misspelled `MESSANGERS_GATEWAY` are no longer read anywhere, with no fallback and no warning. **Migration:** rename the variable to `MESSENGERS_GATEWAY` in every `.env`, build arg and container environment. If you don't, nothing errors: the browser dials the `http://localhost:3050` default (or whatever was baked at build) and realtime stops arriving.

## [0.9.1] - 2026-09-13

### Changed

- **`@bloodheaven/frontend-shared` bumped to `v0.7.0`** ([frontend/package.json](frontend/package.json), [frontend/pnpm-lock.yaml](frontend/pnpm-lock.yaml)). The layer's `DatePicker` and `DateRangeFilter` now take `weekStart` / `locale` and render their calendar, input and label in that locale, and it carries the `Form` / `Table` typecheck fixes that were never tagged. `pnpm typecheck` stays clean; all 51 tests pass.

### Security

- **Access tokens no longer leak into the log and Loki** ([backend/app/server.go](backend/app/server.go); docs 06 in both languages). The request logger printed gin's `param.Path`, which is the path with the raw query appended. A WebSocket handshake authenticates with `?token=<JWT>`, so every handshake wrote a live access token into the backend log and shipped it to Loki. Each line now carries `param.Request.URL.Path` only, without the query string, and every service copied from this template inherits that. Method, status, latency and client address are unchanged.

## [0.9.0] - 2026-09-13

### Added

- **Timezone and formatting locale come from the account** ([frontend/stores/user-preferences.store.ts](frontend/stores/user-preferences.store.ts), [frontend/services/user-preferences.service.ts](frontend/services/user-preferences.service.ts), [frontend/api/user-preferences.api.ts](frontend/api/user-preferences.api.ts), [frontend/plugins/02.user-preferences.client.ts](frontend/plugins/02.user-preferences.client.ts), [frontend/constants/user-preferences.ts](frontend/constants/user-preferences.ts), [frontend/utils/user-preferences.ts](frontend/utils/user-preferences.ts)). Both are per-account preferences owned by auth-gateway and edited once on its profile page for every product. The frontend reads them before the first paint from the gateway's OIDC userinfo (`zoneinfo` / `locale` claims) with its own access token, reloads them on a later sign-in and resets them on sign-out. With auth disabled, a local ADMIN_LOGIN session or an unset claim, the browser's zone and locale apply. date-fns `weekStartsOn` follows the locale's first day of the week.
- **Preference changes apply live** ([frontend/app.vue](frontend/app.vue)). The app subscribes to `userPreferences::updated::{userId}`, so changing the timezone or locale on the profile page re-renders every open tab without a reload.
- **Read-only "Timezone and formats" card on `/settings`** ([frontend/components/settings/DisplayPreferences.vue](frontend/components/settings/DisplayPreferences.vue), [frontend/i18n/locales/en.json](frontend/i18n/locales/en.json), [de.json](frontend/i18n/locales/de.json), [ru.json](frontend/i18n/locales/ru.json)). It shows the timezone and locale in effect, marks a browser default, previews the locale's number separators, and links to `${authGatewayUrl}/profile` to change them.
- **`useFormatNumber()` / `formatNumber`** ([frontend/composables/use-format-number.ts](frontend/composables/use-format-number.ts), [frontend/utils/format-number.ts](frontend/utils/format-number.ts)). Numbers render with the separators of the account's locale; a missing or non-finite value renders as `-`.

### Changed

- **Timestamps render in the account's timezone** ([frontend/composables/use-format-date.ts](frontend/composables/use-format-date.ts)). `useFormatDate()` reads the user-preferences store instead of the service's settings. The output stays ISO 8601 `YYYY-MM-DD HH:MM:SS` whatever the locale.
- **Uptime percentages follow the account's locale** ([frontend/pages/uptime-report.vue](frontend/pages/uptime-report.vue)). They keep two decimals but take their decimal separator from the locale (`99,95%` for `de-DE`).
- **The CLAUDE.md time rules name auth-gateway as the timezone's source** ([CLAUDE.md](CLAUDE.md), [frontend/CLAUDE.md](frontend/CLAUDE.md), [backend/CLAUDE.md](backend/CLAUDE.md)), and [docs/en/09-frontend-structure.md](docs/en/09-frontend-structure.md) / [docs/ru/09-frontend-structure.md](docs/ru/09-frontend-structure.md) describe the flow. Services generated from the template no longer grow a timezone setting of their own.

### Removed

- **The per-service "Display timezone" setting.** The select on `/settings` is gone, along with `SETTING_KEYS.TIMEZONE` ([frontend/api/settings.api.ts](frontend/api/settings.api.ts)), the settings store's `timezone` and `DEFAULT_TIMEZONE` ([frontend/stores/settings.store.ts](frontend/stores/settings.store.ts)), `frontend/constants/timezones.ts`, and the backend's `KeyTimezone` ([backend/app/settings/interfaces/interfaces.go](backend/app/settings/interfaces/interfaces.go)). A `timezone` row left in the settings table is simply no longer read.
- **`frontend/plugins/02.settings.client.ts`.** It preloaded the global settings only so the timezone was known before the first paint; nothing else read them. The settings page no longer fetches or streams settings either, because it no longer renders any.

### Fixed

- **`pnpm test` starts again in `frontend/`** ([frontend/package.json](frontend/package.json), [frontend/vitest.config.ts](frontend/vitest.config.ts)). The `pnpm.overrides` block aliased `h3-next` to `npm:h3@1.15.11`, so `@nuxt/test-utils` resolved its optional `h3-next` peer (h3 **v2**) to h3 v1. Its environment module carries both code paths and picks one at runtime from the installed h3 version, but vite still has to resolve the branch it will not take — and `h3-next/generic` does not exist in v1, so every worker died with `Failed to start forks worker` before a single test ran. The alias is gone; with no `h3-next` in the tree at all the unused dynamic import is simply left external, which is how `auth-gateway` was passing all along. `hookTimeout` is also raised to 120s, because each worker builds its own Nuxt environment and that never fit the default 10s `beforeAll` budget.
- **The auth store's sign-out test actually watches the request it asserts on** ([frontend/tests/unit/stores/auth.store.test.ts](frontend/tests/unit/stores/auth.store.test.ts)). It stubbed `$fetch` with `vi.stubGlobal`, but `$fetch` is a Nuxt auto-import: the store binds it at module scope, so the stub sat on `globalThis` unused while the real call went to the network and the assertion saw zero calls. Replaced with `mockNuxtImport('$fetch', …)`, which replaces the binding the store resolves.
- **`goauth`'s log lines join the platform log format** ([backend/go.mod](backend/go.mod)). Bumped `github.com/BloodHeavenDevelop/utils` to `v0.15.0`. Until then `utils/goauth` was the one shared package still writing to `log/slog`, so its startup and token-validation lines arrived unframed — no `[App] <pid>` prefix, no level colour and no Loki shipping — sitting in the middle of a stream every other package logs through `utils/logger`. They now go out under the `GoAuth` prefix like `Redis` and `Database` do, and a token-validation failure carries the request's trace id.

## [0.8.1] - 2026-09-11

### Fixed

- **`pnpm typecheck` in `frontend/` is clean again** ([frontend/nuxt.config.ts](frontend/nuxt.config.ts)). `@nuxtjs/i18n` 10 no longer has the `lazy` and `bundle.optimizeTranslationDirective` options — locale files are always loaded on demand now — so both are gone from the config, and the `getFavicons()` link list is declared `as const` so its `rel` values satisfy the `app.head.link` type. The rest of the red baseline (`UiForm`'s state / `validate-on` binding, `UiTable`'s row typing that rejected every `row as Incident` cast in `pages/incidents.vue`) is fixed in `@bloodheaven/frontend-shared` 0.6.2; it goes green once `package.json` is bumped to that tag.

## [0.8.0] - 2026-09-09

### Added

- **Realtime entity events now actually reach the browser** ([backend/app/server.go](backend/app/server.go), [backend/app/config/config.go](backend/app/config/config.go), [docker-compose.yml](docker-compose.yml)). The backend opens a supervised AMQP connection and builds its `broadcast` func with `rabbitmq.NewFanoutBroadcaster`, publishing every entity event to the platform's `EVENTS_EXCHANGE` fanout — the exchange `messengers-gateway` consumes and forwards to the browser's single WebSocket. Until now the template broadcast into an in-process WebSocket hub at `/api/ws` that no client ever dialled, so the frontend's realtime subscriptions received nothing and every list had to be re-fetched by hand to see a change. RabbitMQ joins the health-check set, and the compose file wires `RABBITMQ_URL` / `EVENTS_EXCHANGE` plus a `rabbit` dependency.
- **Settings broadcast on save** ([backend/app/settings/service/service.go](backend/app/settings/service/service.go), [backend/app/settings/service/secrets.service.go](backend/app/settings/service/secrets.service.go), [backend/app/settings/settings.package.go](backend/app/settings/settings.package.go)). `PATCH /settings/{key}` publishes `settings::updated::{key}` with the response DTO; `PUT /settings/secrets/{key}` publishes `settings-secrets::updated::{key}` carrying **presence only** (`{key, hasValue}`) — the encrypted value never goes on a fan-out that reaches every connected client. A second admin's timezone or S3 change now appears without a reload.
- **Notification integrations broadcast on create/update/delete** ([backend/app/notifications/service/integrations.service.go](backend/app/notifications/service/integrations.service.go), [backend/app/notifications/notifications.package.go](backend/app/notifications/notifications.package.go)) as `notification-integrations::created` / `::updated::{id}` / `::deleted::{id}`, and marking alerts read publishes one `notifications::updated::{id}` per row it actually changed ([backend/app/notifications/service/notifications.service.go](backend/app/notifications/service/notifications.service.go), [backend/app/notifications/repositories/repositories.go](backend/app/notifications/repositories/repositories.go) — new `RetrieveMany`). The endpoint answers with a count, which no list can be updated from, so the rows are read back and sent as full DTOs instead of leaving the client to re-list.
- **`useEntityArrayStream`** ([frontend/composables/use-entity-stream.ts](frontend/composables/use-entity-stream.ts)) — the collection-stream helper for the other shape this codebase uses, a plain array in a Pinia store, alongside the existing `useEntityListStream` for paginated `{ rows, count }` payloads. The file now opens with the full two-mechanism contract (apply your own response; receive everyone else's) and the idempotency rule that makes an actor's own echoed event a no-op.
- **`NUXT_PUBLIC_MESSENGERS_GATEWAY`** ([frontend/nuxt.config.ts](frontend/nuxt.config.ts), [frontend/Dockerfile](frontend/Dockerfile), [docker-compose.yml](docker-compose.yml), [frontend/utils/ws-client.ts](frontend/utils/ws-client.ts), new [frontend/utils/gateway-env.ts](frontend/utils/gateway-env.ts) and [frontend/server/middleware/messengers-gateway-env.ts](frontend/server/middleware/messengers-gateway-env.ts)). The realtime hub's URL was seeded from `process.env.MESSANGERS_GATEWAY` — a misspelled, build-time-only variable no deployment set — so every browser shipped with the `http://localhost:3050` default and opened its events socket against the visitor's own machine. Nothing errored: plain HTTP kept working while realtime was dead. The value now comes through the standard `NUXT_PUBLIC_*` mechanism (build arg and runtime env), and the old spelling is still honoured at runtime, deprecated, with a warning.
- **RBAC change hints are consumed** ([backend/app/server.go](backend/app/server.go), [backend/app/config/config.go](backend/app/config/config.go)). Now that the service has an AMQP connection, `rbac.AttachBroker` subscribes to auth-gateway's `rbac` fanout (`RBAC_EXCHANGE`, default `rbac`), shortening the window in which a stale permission binding is enforced from the five-minute resync ticker to under a second. The ticker remains the correctness guarantee.

### Changed

- **Saving an entity no longer re-fetches the page's data.** A mutation applies the DTO its own response carried, and anything changed by someone else arrives over the stream. Removing the post-save refetch is what stops `loading` flipping back on and repainting the surface from its skeleton — the "page reloaded" the user reported — and stops the duplicate GET that followed every save.
  - [frontend/stores/resource.store.ts](frontend/stores/resource.store.ts): `create()`, `remove()` and `batchUpdate()` no longer `await fetchAll()`. `applyResourceUpdate` becomes an idempotent upsert-by-id that also maintains the `total`/`active`/`paused` counters (and respects the active group filter), and `removeById` maintains them on the way down — so the stats bar stays correct without the list call it used to come from.
  - [frontend/pages/index.vue](frontend/pages/index.vue): both `refreshNuxtData(RESOURCE_LIST_QUERY)` calls are gone. `resource::created` upserts the row; an incident no longer re-lists the dashboard, because whatever it changed about a monitor already arrives as `resource::status-updated`.
  - [frontend/pages/resource/[id].vue](frontend/pages/resource/%5Bid%5D.vue): editing applies the saved DTO through the popup's new `onSaved` callback instead of `refresh()`; the incident handler no longer re-reads the monitor. The recent-checks log keeps its refresh — it is server-side history with no event stream of its own, and that is a re-query for genuinely new data, not a page reloading after a save.
  - [frontend/pages/admin/permissions.vue](frontend/pages/admin/permissions.vue): toggling a grant splices the created grant in / filters the deleted one out instead of re-listing, and no longer re-reads the user directory (a grant changes none of `{userId, email, role}`). The one remaining call, `GET /permissions/me`, stays: it describes the *caller* to themselves, which the grant DTO says nothing about.
  - [frontend/stores/notifications.store.ts](frontend/stores/notifications.store.ts) and [frontend/stores/settings.store.ts](frontend/stores/settings.store.ts) expose their merge rule as one `applyX` / `removeXById` pair, called by both the mutation path and the stream, so re-applying an echoed event cannot duplicate or corrupt a row.
- **Two more surfaces are now live for other people's edits**: [frontend/pages/notifications.vue](frontend/pages/notifications.vue) subscribes to `notification-integrations::…`, and [frontend/pages/settings/index.vue](frontend/pages/settings/index.vue) to `settings::…` and `settings-secrets::…`.
- **Mobile marks notifications read locally** ([mobile/lib/presentation/notifications/notifications_cubit.dart](mobile/lib/presentation/notifications/notifications_cubit.dart)). `markAsRead` emitted the new state from the effect the call is defined to have instead of calling `load()`, which had been re-fetching the page and the unread count, flashing the loading state and discarding the scroll position.
- **The module-generation guides teach the pattern** ([backend/CLAUDE.md](backend/CLAUDE.md), [frontend/CLAUDE.md](frontend/CLAUDE.md), [mobile/CLAUDE.md](mobile/CLAUDE.md)). The backend service/package/`server.go` templates now carry the `broadcaster` field, the `EntityPlural` constant and the `s.broadcaster(websocket.Event…)` call in create/update/delete, so a generated module is realtime by construction; the checklist gained the matching items. The frontend guide documents apply-the-response and `useEntityStream` in place of a post-save refetch. Because this repository is the scaffold every new service is copied from, the trap does not propagate.
- Documentation updated in **both languages** ([docs/en](docs/en), [docs/ru](docs/ru)): `01-introduction`, `04-architecture` (new Real-Time section: the contract, the transport, and what must never be broadcast), `06-backend-structure`, `07-backend-modules`, `09-frontend-structure` (the no-refetch rule and the three stream helpers), `28-roles-and-permissions`, `31-rest-api` (§ 12 now describes the gateway socket, not a local one) and `33-webhooks` (the full event table).

### Removed

- **The in-process WebSocket hub and its `/api/ws` endpoint** ([backend/app/server.go](backend/app/server.go), [backend/swagger/](backend/swagger)). It was unreachable by design: a browser holds exactly one socket and it is to `messengers-gateway`, so everything this hub broadcast went nowhere. Keeping it next to the AMQP fan-out would have meant two implementations of one job, and would have taught every service cloned from this template to broadcast into the void. No client used it.

## [0.7.4] - 2026-09-08

### Fixed

- **Icons resolved from the server no longer 404 behind the platform proxy** ([frontend/nuxt.config.ts](frontend/nuxt.config.ts)). `@nuxt/icon` runs with `provider: 'server'` and serves icon data from its own Nitro route, whose default path is `/api/_nuxt_icon/:collection.json` — but every vhost on this platform gives the whole `/api/` prefix to the Go backend, so those requests were proxied to a backend that has no such route and came back `404`. Any icon outside the small `clientBundle.icons` list — the whole `my-icons` collection, since `includeCustomCollections` is `false` — therefore rendered blank in a deployed service. The endpoint moves to `/_nuxt_icon`, out from under the proxied prefix, so a service scaffolded from this template does not inherit the bug.

## [0.7.3] - 2026-09-08

### Fixed

- **The rows-per-page select in a table's pagination bar no longer draws its chevron over the value** ([frontend/package.json](frontend/package.json)) — `@bloodheaven/frontend-shared` moves to **v0.6.1**. The shared `UiTable` handed the trigger a hand-rolled skin that set `pr-[18px]`, overriding the inline-end padding Nuxt UI reserves for the chevron it positions *absolutely* at the trigger's end; the control then shrank to its text and the arrow landed on top of the last digit. The select now takes the design system's own control skin from the layer's `app.config.ts` — accent on hover and focus again, one ring instead of a ring plus a border, and a panel that tracks the trigger's width — and keeps only its 32px height and a fixed width, so it lines up with the page buttons and does not jump between "10" and "100".

## [0.7.2] - 2026-09-07

### Changed

- **The frontend moves to Tailwind 4 and Nuxt UI 4, closing the last open advisory** ([frontend/package.json](frontend/package.json), [frontend/nuxt.config.ts](frontend/nuxt.config.ts), [frontend/app.config.ts](frontend/app.config.ts)). `@nuxt/ui` was pinned to `^2.x` with a moderate advisory whose fix is `>=4.8.1`, and v4 requires Tailwind 4 — so the two were one migration, and it had to happen in the shared design system first. `@bloodheaven/frontend-shared` is bumped to **v0.6.0**, which carries the Tailwind 4 entry, the `hm-*` colour scale in an `@theme` block, a `--ui-* → --hm-*` bridge that hands every Nuxt UI component the design system's palette, and the platform's Nuxt UI theme in the layer's own `app.config.ts`. `pnpm audit` now reports **no known vulnerabilities**.
- **This app's ~220-line `ui:` theme block is gone** ([frontend/app.config.ts](frontend/app.config.ts)). Nuxt merges a layer's app config underneath the application's, so the design system is now described once for every frontend instead of copied into each; what is left here is only what is genuinely this app's. Most of the removed block never rendered anything in the first place: the `typo-*` and `rounded-corner-radius-*` classes it named are defined nowhere on the platform, and it themed seven Nuxt UI components this codebase does not use.
- **The `tailwindcss` block is out of [frontend/nuxt.config.ts](frontend/nuxt.config.ts).** Tailwind 4 configures itself from CSS and the `@nuxtjs/tailwindcss` module is gone with Nuxt UI 2; the `hm-*` colour registration it held moved to the layer, next to the tokens it points at.
- `esbuild` is pinned past its own advisory through `pnpm.overrides`.

## [0.7.1] - 2026-09-07

### Security

- **The dead GitHub PAT is gone from [frontend/.npmrc](frontend/.npmrc).** The private `@bloodheavendevelop` scope authenticated with a token committed in plain text; it has been revoked for a while, so `pnpm install` against this template failed with `ERR_PNPM_FETCH_401` anyway. It now reads `_authToken=${GITHUB_TOKEN}` from the environment, the spelling the Dockerfile already declares as a build arg and every other frontend on the platform uses. The token remains in git history and must be revoked at the org level if that has not happened.

### Changed

- **Every frontend dependency carrying a published advisory is updated** ([frontend/package.json](frontend/package.json), `frontend/pnpm-lock.yaml`). `pnpm audit` reported **136 advisories, 6 of them critical**; one is left. Nuxt moves 4.1 → 4.5.2, which alone closes the critical `seroval`, `shell-quote`, `simple-git`, `tar` and `@nuxt/devtools` findings inside its own tree; `lodash` → 4.18.1, `swagger-typescript-api` → 13.12.6, and the eslint / vite / rollup / postcss tail moves with them. `@nuxtjs/seo` goes 3.1.0 → 5.3.14, which forces `@nuxtjs/i18n` 9 → 10 (seo v5 refuses to load against an older i18n and fails the build outright) and pulls `nuxt-og-image` 5 → 6.7.8 — the v6 line dropped its `image-size` dependency, and `image-size` has an advisory with **no published fix**, so the only way to be rid of it was to stop depending on it. The `sharp` override rises 0.33.4 → 0.35.4: it pins what the whole tree resolves to, and 0.33.4 was the vulnerable version.
- **`@nuxt/ui` is the one advisory that remains** (moderate). Its fix is `>=4.8.1` — two majors above the pinned `^2.x` — and v4 requires Tailwind 4, while the platform's design system (`hm-base.css` in `@bloodheaven/frontend-shared`) is Tailwind 3 and still uses `@tailwind base/components/utilities`. Closing it is a design-system migration across every frontend at once, not a dependency bump, so it is deliberately left open here.
- **`utils/ws-client.ts`: the parsed-message variable no longer carries a dead initializer.** The newer ESLint enables `no-useless-assignment`, which correctly points out that the `= null` is never read — the `catch` returns before anything can observe it. Behaviour is unchanged; `pnpm lint` passes with no errors again.

## [0.7.0] - 2026-09-07

### Added

- **`POST /api/auth/sign-out`** ([backend/app/server.go](backend/app/server.go), [docs/en/31-rest-api.md](docs/en/31-rest-api.md), [docs/ru/31-rest-api.md](docs/ru/31-rest-api.md)). An un-gated endpoint that forwards the caller's access token to the auth gateway's session-termination endpoint and drops the shared `bh:auth:token:*` cache entry, so every service on the platform stops honouring the token at once instead of each waiting out its own TTL. It answers `204` even when the gateway already rejects the token — a client asking to be signed out has got what it wanted either way, and a `401` there would strand a browser holding a token it can neither use nor shed; only an unreachable or broken gateway is reported, as an opaque `422`. Mounted on `publicRouter` for the same reason refresh is: a client whose access token has already lapsed still has to be able to end its session. The handler ships from `authkit` in the shared `github.com/BloodHeavenDevelop/utils` module, bumped here to `v0.13.0` ([backend/go.mod](backend/go.mod)).
- **`useAuthStore().signOut()`** ([frontend/stores/auth.store.ts](frontend/stores/auth.store.ts)) — posts that endpoint with the current access token, then clears local state and storage whatever the answer was, so an unreachable backend cannot leave the browser signed in.

### Fixed

- **Sign Out actually signs the user out** ([frontend/layouts/default.vue](frontend/layouts/default.vue), [frontend/stores/auth.store.ts](frontend/stores/auth.store.ts)). The button cleared `localStorage` and sent the browser to the auth gateway's root. The gateway session survived untouched, so the next visit to the consent screen re-authenticated silently and the user was never actually signed out — and with `authGatewayUrl` unset the click did nothing visible at all, because clearing the tokens does not re-render a page that is already drawn. It now ends the session server-side first and navigates to this app's own `/auth`, which is the sign-in screen in both OAuth2 and local-login mode.

## [0.6.2] - 2026-09-07

### Fixed

- **The app is no longer painted for signed-out visitors before the redirect to `/auth`** ([frontend/nuxt.config.ts](frontend/nuxt.config.ts), [frontend/middleware/auth.global.ts](frontend/middleware/auth.global.ts), [frontend/spa-loading-template.html](frontend/spa-loading-template.html), docs 09 + [frontend/CLAUDE.md](frontend/CLAUDE.md) in both languages). Opening the site without a session server-rendered the page, shipped it to the browser and only then let the client-side gate replace it with the sign-in screen — a full paint of a signed-in UI, and its HTML, handed to an anonymous visitor. The session lives in `localStorage`, which the server cannot read, so it never had grounds to render those pages at all: `routeRules: { '/**': { ssr: false } }` now makes every route client-rendered, the server answers with the SPA shell (the new `spa-loading-template.html` — a dark splash on the design system's own background) and `middleware/auth.global.ts` decides before the first paint. The gate also re-reads the token from storage itself instead of relying on plugin order, and keeps its public routes in one named list. A page that ever needs SSR opts back in with a rule of its own plus an entry in that list.

## [0.6.1] - 2026-09-06

### Changed

- **The frontend image is built on Node 24** ([frontend/Dockerfile](frontend/Dockerfile)). Both stages move from `node:22-alpine` to `node:24-alpine`, so the container finally runs the major that [frontend/.nvmrc](frontend/.nvmrc) has been pinning for local development — until now a build could pass on the developer's Node 24 and ship on Node 22. The expected-Dockerfile block in [frontend/CLAUDE.md](frontend/CLAUDE.md) still described `node:20-alpine` and now names the same image the Dockerfile uses.

## [0.6.0] - 2026-09-03

### Added

- `frontend/layouts/default.vue`, `frontend/package.json`, `docs/en/10-design-system.md`, `docs/ru/10-design-system.md`: phone layout for the frontend, per the new root `DESIGN_MANIFEST_MOBILITY.md`. Below the 768 px breakpoint the viewport bezel is dropped (16 px of a 360 px viewport, and it cannot coexist with the safe-area insets), gutters fall to 16 px, the header goes sticky and sheds its nav links while keeping the `#header-actions` teleport target, the footer hides, `<UiTable>` renders one card per row instead of a column grid — reusing the table's own `${key}-data` slots, so pages need no second template — with an explicit sort control replacing clickable column headers and compact pagination, buttons land on 44 px and form controls on 48 px at 16 px type (below 16 px iOS Safari zooms the page on focus and never zooms back), stat cards become a horizontally scrolling strip, every `.hm-modal` renders as a bottom sheet with a drag handle and a stacked action row (primary on top, so the reflex tap at the bottom edge is not the destructive one), and toasts move to the bottom edge above the tab bar. Navigation moves into the new `<UiMobileNav>` — three tabs plus a *More* sheet carrying the remaining routes, the dropdown groups, the identity anchors and the hidden footer's version/build/online/env slots. Everything except mounting that one component ships from `@bloodheaven/frontend-shared`, bumped here to `v0.5.0`. Previously the only mobile handling was a 20-line block that reduced padding, so on a phone data tables scrolled sideways, toolbar controls stayed 30 px tall and the entire navigation was off-screen.

### Changed

- `mobile/lib/core/theme/typography.dart`, `mobile/lib/presentation/common/widgets/status_badge.dart`, `mobile/lib/presentation/dashboard/widgets/search_filter_bar.dart`: bring the Flutter app in line with the mobility manifest's native appendix. Badge type rises from 9 px to the 10 px floor (9 px is decoration, not text, at arm's length), the status badge uses the manifest's 0.15 tint instead of 0.10, the search field lands on the 48 px control height with autocorrect off and a search action key, and the status/type filter chips become a horizontally scrolling strip of 36 px chips inside 48 px targets — previously a fixed `Row` with a `Spacer`, which overflows at 360 px once the labels grow.

## [0.5.1] - 2026-08-30

### Fixed
- **An idle tab no longer hammers the realtime endpoint with an expired token** ([frontend/utils/ws-client.ts](frontend/utils/ws-client.ts), new [frontend/utils/ws-auth.ts](frontend/utils/ws-auth.ts), [frontend/composables/use-entity-stream.ts](frontend/composables/use-entity-stream.ts), [frontend/composables/use-resource-stream.ts](frontend/composables/use-resource-stream.ts), [frontend/stores/permissions.store.ts](frontend/stores/permissions.store.ts); docs 09 in both languages). The WebSocket handshake carries the token in the query string, which makes it the one request the `$api` interceptor never sees — so nothing refreshed it, and the client captured the token once at `configure()` time. An access token lives ~15 minutes; after that every reconnect handed messengers-gateway a long-dead token and got a `401` back, three seconds apart, forever — the loop visible in the gateway's log as a wall of `401 GET /api/events/ws?token=…`. The token is now resolved on **every** (re)connect through `ensureFreshWsToken()`, which refreshes before the handshake instead of after it.
- **A rejected handshake now repairs the session instead of repeating it** ([frontend/utils/ws-client.ts](frontend/utils/ws-client.ts)). The browser never exposes the handshake's status code — a `401` surfaces only as a socket that closed before it ever opened — so the client treats the first such failure as a spent token and forces a refresh on the next attempt, then backs off exponentially (3 s → 60 s, jittered) until a socket actually opens. Only the first failure of a streak forces a refresh, so a gateway that is simply down does not become a refresh storm; a socket that opened resets both the counter and the delay, so an ordinary drop still reconnects after 3 s.

## [0.5.0] - 2026-08-30

### Added
- **A share card and a product icon set for the frontend** ([frontend/public/og-image.svg](frontend/public/og-image.svg) → `og-image.png`, [frontend/public/favicon.svg](frontend/public/favicon.svg), and the PNG/ICO sizes derived from it). The card is the dark canvas of the design manifest — the 40 px grid, the `--paused` accent stripe of § 8.2, the product mark at 160 px, the title in Syne 800, a capability badge row and a hairline footer. The badges name capabilities and never metrics: a share card must not carry numbers the product did not produce. The SVG is the authored source; the PNG ships because no social platform renders an SVG `og:image`. Regenerate both, and the whole icon set, with `node scripts/gen-brand-assets.mjs` from the workspace root.
- **`og:image` and the Twitter card are declared in [frontend/nuxt.config.ts](frontend/nuxt.config.ts)** (`getOpenGraphMeta()`): `og:image` plus `type`/`width`/`height`/`alt`, `twitter:card=summary_large_image` and `twitter:image`, all as **absolute** URLs built from `NUXT_PUBLIC_SITE_URL`. A link pasted into Slack, Telegram, LinkedIn or a social post now renders the card instead of nothing. `nuxt-seo-utils` would find `public/og-image.png` by itself, but the URL it emits is relative and the plugin that absolutises it is server-only; declaring the tag also makes that scan stand down, so exactly one `og:image` ships.
- **`<link rel="manifest">`** — `site.webmanifest` existed but nothing pointed at it, so the `android-chrome-*` icons in `public/` were unreachable.

### Changed
- **The favicon is the template's own mark** — an empty frame with one new element in it — on the shared `--hm-surface` tile with a `--hm-border` edge, replacing the deploy-arrow glyph copied from the deployer frontend. The 16/32/96 px PNGs, `favicon.ico`, `apple-touch-icon.png` and the two `android-chrome` sizes are regenerated from it; the touch and Android icons are opaque full-bleed squares, because iOS and Android composite them onto their own background and a transparent rounded tile shows black corners on both.
- **`frontend/public/site.webmanifest` carries a name and the dark theme colour** (`#080c10`) instead of empty strings and `#ffffff`, so an installed app no longer flashes a white splash ahead of the dark canvas.

### Removed
- **`frontend/public/og-image2.png`** — a 73 KB stock "Tokenizer.Estate" dashboard screenshot inherited from the starter template. Nothing referenced it, and its name could never have matched what `nuxt-seo-utils` scans for.

## [0.4.4] - 2026-08-30

### Removed
- **`frontend/CLAUDE.md`: the cross-repo `BACKEND_REPO` / `GH_TOKEN` instructions.** The
  "What the user can ask" / "How the assistant should use these variables" section told
  the assistant to read the backend through `gh api` with a personal access token — a
  leftover from when backend and frontend lived in separate repositories. Both
  directories sit side by side in this repo, so the variables were never set and the
  instructions only described a dead path.

### Changed
- **`frontend/package.json`: the package is now `ai-template-frontend`** (was
  `project-template-frontend`, inherited from the starter template).

## [0.4.3] - 2026-08-23

### Documentation
- Documented the permission system in `docs/en` and `docs/ru` (both languages in the
  same change): where a permission comes from, how a route is guarded, what happens when
  auth-gateway is unreachable, and which key namespace the caches use. Repointed the
  remaining references to the removed per-service `app/permissions` package.

### Fixed
- **A failed request showed `Fetch error` instead of the message the backend sent** ([frontend/utils/extract-error-message.ts](frontend/utils/extract-error-message.ts), [frontend/plugins/01.api.ts](frontend/plugins/01.api.ts), [frontend/tests/unit/utils/extract-error-message.test.ts](frontend/tests/unit/utils/extract-error-message.test.ts)): the API client read `response._data.message` inline and fell back to the literal `Fetch error` the moment that path was empty — which is every failure the backend did not write as a JSON envelope: a gin router `404 page not found` (plain text, so `_data` is a string), an nginx `429`/`502` error page, and any request that never got a response at all, since ofetch reports those as a `FetchError` with no `response` and the client's own "Network error" branch was therefore unreachable. The toast now goes through `extractErrorMessage()`, which reads the platform error envelope (`{statusCode, error, message}`) first — including when it arrives as text — then a short plain-text body, then the response status (`429` reads as "Too many requests — try again in a moment"), and only calls a request that got no response a network error. The helper is unchanged in name and signature, so every call site that already used it (stores, popups, pages) inherits the same fallbacks; it is now identical in every frontend.

## [0.4.2] - 2026-08-01

### Changed
- **The design-system CSS moved into the shared layer.**
  `frontend/assets/styles/main.css` no longer carries its own copy of the `.hm-*`
  primitives, the `--hm-*` tokens, the `@font-face` declarations or the Tailwind
  directives — it imports them from
  `@bloodheaven/frontend-shared/assets/styles/hm-base.css` (layer `v0.3.0`) and keeps
  only project-local rules. Since this repository is the scaffold for new services, a
  service copied from it now inherits the design system from one versioned place
  instead of forking a 1100-line stylesheet on day one.
- **Web fonts are served by the layer.** `frontend/public/fonts/` was deleted; the three
  `.woff2` files ship with `@bloodheaven/frontend-shared` and Nitro serves them at the
  same `/fonts/…` URLs.
- **Form controls share one height.** Part of the extracted base: `.hm-select` now
  matches `.hm-input` as one control family — 12 px type (was 13 px), 8 px radius (was
  6 px), 8/14 px padding — with both floored on the new `--hm-control-height` token, so
  a select and the input beside it line up. Toolbar controls keep their own 30 px height.

## [0.4.1] - 2026-07-30

### Removed
- **The API keys section is gone.** API keys are owned platform-wide by **auth-gateway**,
  so a service scaffolded from this template must not ship its own. The backend module had
  already been dropped, leaving a UI that called endpoints nothing serves. Deleted
  `pages/api-keys/`, `stores/api-keys.store.ts`, `services/api-keys.service.ts`,
  `api/api-keys.api.ts` and `components/popups/CreateApiKeyPopup.vue`, with the `/api-keys`
  nav entry, the `CREATE_API_KEY_POPUP` popup type and its props.
- **`api_keys` table removed from `000001_init`** — the template no longer creates a table
  no code reads. Edited in place rather than shipping a create-then-drop pair, since a new
  project runs this migration from scratch.
- **API-key paths and definitions stripped from the committed Swagger artifacts**
  (`swagger.json`, `swagger.yaml`, `docs.go`) and from `frontend/generated/types.ts`:
  `/api-keys`, `/api-keys/list`, `/api-keys/{apiKeyId}`, the five `IApiKey*` interfaces,
  `models.ApiKeyStatus` and `types.Patchable-models_ApiKeyStatus`. All three artifacts
  still agree (32 paths / 60 definitions) and `docs.go` compiles.

### Changed
- **`docs/{en,ru}/28-api-keys-and-roles.md` → `28-roles-and-permissions.md`**, rewritten to
  cover RBAC only: the API-key chapter, the `/api-keys` UI section, the API-key REST block,
  the `ci-bot` role row, the `api_key` resource constant and the API-key troubleshooting row
  are gone, and remaining sections are renumbered. Slugs and titles in
  `frontend/public/docs/manifest.json`, both tables of contents and every cross-reference
  follow.
- **Docs corrected to the real template** — `01-introduction` and `04-architecture` drop the
  `api-keys` package from the RBAC bullet and the package catalog, `06-backend-structure`
  drops `api-keys/` from the tree and states the real middleware chain (`authkit` session,
  not an API key), `31-rest-api` loses its "API key (machine access)" auth mode, its
  `/api/api-keys/list` search row and its API-key URI-parameter examples. `README.md` no
  longer advertises `api-keys` in the auth stack.
- **`backend/CLAUDE.md` module template no longer generates API-key auth** — the stale
  `auth.CheckApiKeyMiddleware` (a symbol that does not exist in this codebase) is replaced
  by the `permissions.Require(...)` route guards the real modules use.

### Fixed
- **Error toasts were swallowed by an open modal's backdrop blur.** `frontend/app.vue`
  rendered `<ToastsContainer />` *before* `<PopupContainer />`; both sit on z-index layer
  100 (DESIGN_MANIFEST section 2.4), so the later sibling won and the toast stack ended up
  underneath the overlay's `backdrop-filter: blur(4px)` — unreadable exactly when it
  matters, since error toasts never auto-dismiss. The containers are now ordered popups
  first, toasts last; the rule is written into DESIGN_MANIFEST sections 2.4, 5.5 and 15.3.

## [0.4.0] - 2026-07-27

### Changed
- **Notification emails now use the platform's shared dark email template.** The embedded
  light-themed `app/notifications/templates/alert.html` / `test.html` are gone;
  `templates.go` composes the alert and test messages from `utils/emailtemplate` blocks
  (label/value fields, tone-coloured status pills, a monospace details box) so a service
  scaffolded from this template sends mail that matches the rest of the platform. Set the
  `productName` constant to the new service's name when starting a project. Requires
  `utils v0.8.0`; `RenderAlert`/`RenderTest` return an `emailtemplate.Email` instead of
  `(string, error)`.
- **`app/auth` removed — the service uses the shared `utils/authkit` directly.** The
  whole authentication layer (request-gating middleware, `RequireRoles`, the public
  `/auth/config` · `/auth/local/*` · `/auth/oauth2/*` endpoints, and the local
  ADMIN_LOGIN JWT fallback) now lives in `github.com/BloodHeavenDevelop/utils/authkit`.
  `app/server.go` wires it with `authkit.Init(authkit.Config{…})` and call sites use the
  package-level `authkit.*` helpers (a process singleton, mirroring `logger.Logger`), so
  no per-service auth package remains. Bumped `utils` to `v0.5.0`. No behavior change.
- **`goauth` moved to the shared `utils` module.** The local `app/goauth` package
  (auth-gateway token-validation client — Gin middleware, JWT introspect / OAuth2
  userinfo, Redis token cache, users-list client) was removed; the backend now imports
  it from `github.com/BloodHeavenDevelop/utils/goauth`. Bumped `utils` to `v0.3.0`. No
  behavior change — one canonical shared copy instead of a per-service vendored one.
- `app/config` no longer redeclares the shared logger settings: dropped `LokiConfig`
  and the `LogLevel`/`Loki` globals. The shared `utils` logger now reads
  `MODE`/`LOG_LEVEL`/`LOKI_URL`/`LOKI_USER`/`LOKI_PASSWORD` from the environment itself
  via the no-argument `logger.Init()`. Bumped `utils` to `v0.2.0`, consumed as a
  published tag.

### Added
- `docker-compose.yml` describing the `ai-template-backend` (host `3050`) and
  `ai-template-frontend` (host `3000`) services. It builds both images, loads each
  repo `.env` (optional) and overrides the infra endpoints (`DATABASE_URL`/`REDIS_URL`)
  to the shared Postgres/Redis, and joins the shared `bloodheaven` network. Pulled into
  the workspace-root compose via `include`; run `docker compose up -d ai-template-backend
  ai-template-frontend` from the repo root. A one-shot `ai-template-migrate` service
  (golang-migrate) applies pending migrations and exits before the backend starts
  (gated via `service_completed_successfully`), using a per-service
  `x-migrations-table` so version counters don't collide in the shared database. The
  backend receives the shared MinIO S3 config (`S3_ENDPOINT`/creds/`S3_BUCKET`, default
  bucket `bloodheaven`) provisioned once by the root `minio-init` one-shot; the env is
  inert until the backend is wired to read S3 from env (it currently reads from settings).

### Changed
- Frontend now consumes the shared UI layer `@bloodheaven/frontend-shared` from its
  published git tag `v0.1.1` (`github:BloodHeavenDevelop/frontend-shared#v0.1.1`)
  instead of the local `link:../../frontend-shared` symlink (`frontend/package.json`).
  Run `pnpm install` to regenerate the lockfile.

### Fixed
- Docker builds can now resolve the private BloodHeaven dependencies. Added `GOPRIVATE`
  and a `github_token` BuildKit secret (written to a throwaway `~/.netrc`, never baked
  into a layer) so `go mod download` fetches the private `utils` module, and the same
  secret to the frontend `pnpm install` for the private `github:` `frontend-shared`
  dependency. Both compose services declare `build.secrets: [github_token]`, sourced
  from the host `GITHUB_TOKEN` env — build with
  `GITHUB_TOKEN=<PAT with repo read> docker compose up --build`.
- Frontend Docker build reworked in `frontend/Dockerfile`. Added `git` to the base
  image (required to resolve the `github:` `@bloodheaven/frontend-shared` dependency,
  which previously made `pnpm install` fail), split into the CLAUDE-prescribed
  `base → deps → build → production` stages with a pnpm store cache mount, and pinned
  `node:22-alpine`. Dropped the stale `NUXT_PUBLIC_AUTH_DISABLED` build arg (auth has no
  frontend env vars) and wired the real public build args
  (`NUXT_PUBLIC_SITE_URL`/`APP_NAME`/`DEFAULT_LOCALE`/`BUILD_SHA`). Production stage now
  sets `NODE_ENV=production` and runs as the non-root `node` user. Expanded
  `frontend/.dockerignore` to exclude `.env`, `.nuxt`, `.output`, tests, and VCS/docs
  (keeping `.npmrc` for private-registry auth).
- Backend Docker build no longer fails. `backend/Dockerfile` pinned `golang:1.24`
  while `backend/go.mod` requires Go `1.25.0`, and it copied nonexistent `manifests/`
  and `patches/` directories — both broke the build. Bumped the builder to
  `golang:1.25-alpine`, dropped the phantom COPY lines, and switched the runtime stage
  from the full `golang` image to `alpine:3.21` (ca-certificates + tzdata), running as
  a non-root `app` user. Added buildx module/build cache mounts and `TARGETOS`/
  `TARGETARCH` cross-compilation args, plus a `backend/.dockerignore` that excludes
  `.env`, compiled binaries, and VCS/docs from the build context.
- Frontend SSR no longer 500s on every request with `event.req.headers.get is not a
  function`. The `@nuxtjs/seo` stack pulled h3 v2 (`h3@2.0.1-rc.20`) in through the
  `h3-next` alias for `nuxt-site-config`'s server middleware, while Nitro still runs h3
  v1 — so `getNitroOrigin`/`getRequestHost` received a v1 event and crashed. Pinned h3
  to the v1 line in `frontend/package.json`: added a direct `h3@1.15.11` dependency and
  `pnpm.overrides` entries `"h3": "1.15.11"` and `"h3-next": "npm:h3@1.15.11"` (matching
  Health Monitor). Run `pnpm install` to regenerate the lockfile.
- Timestamps now render in strict ISO 8601 `YYYY-MM-DD HH:MM:SS` regardless of the
  visitor's browser locale. `frontend/composables/use-format-date.ts` previously called
  `Intl.DateTimeFormat(undefined, …)`, which produced locale-specific output (e.g.
  `06/15/2026, 14:30:05` on an en-US runtime, with slashes and a stray comma); it now
  assembles the value from `formatToParts` under a fixed locale with `hourCycle: 'h23'`,
  so the user's configured timezone is still applied (midnight as `00:00:00`) but the
  format is deterministic.

## [0.3.1] - 2026-06-29

### Changed
- Frontend sign-in now uses the shared `@bloodheavendevelop/auth-ui` Nuxt layer
  (as in Health Monitor) instead of hand-rolled pages/composables. Registered via
  `extends` in `frontend/nuxt.config.ts`; the private package is pulled from GitHub
  Packages (`frontend/.npmrc`). Token persistence is wired in `frontend/app.config.ts`
  (`authUi.onAuthenticated` → `useAuthStore().setTokens`). Auth/OAuth config
  (`authDisabled` / `authGatewayUrl` / `oauth2ClientId`) is now read from
  `useAuthUiConfig()` — populated by the layer from `GET /api/auth/config` — across
  `stores/{auth,permissions}.store.ts`, `middleware/{auth,permissions}.global.ts`,
  `plugins/{01.api,03.permissions.client}.ts` and `layouts/default.vue`, replacing the
  `NUXT_PUBLIC_*` runtime values.

### Removed
- Frontend OAuth2/local auth duplicates now provided by the layer:
  `frontend/composables/{use-oauth2,use-local-auth}.ts` and
  `frontend/pages/auth/{index,callback}.vue`. Dropped the
  `authGatewayUrl` / `oauth2ClientId` / `authDisabled` public runtime config from
  `frontend/nuxt.config.ts` and the `NUXT_PUBLIC_AUTH_GATEWAY_URL` /
  `NUXT_PUBLIC_OAUTH2_CLIENT_ID` / `NUXT_PUBLIC_AUTH_DISABLED` entries from
  `frontend/.env.example` — auth config is backend-sourced via `/api/auth/config`.

## [0.3.0] - 2026-06-29

### Added
- OAuth2.0 authorization-code login wired through the Go backend (by analogy with
  Health Monitor). New public endpoints under `/api`: `GET /auth/config`
  (`{ authDisabled, authGatewayUrl, oauth2ClientId }` for the login UI),
  `POST /auth/oauth2/token` (`{ code, redirectUri }` → token pair) and
  `POST /auth/oauth2/refresh` (`{ refreshToken }` → fresh pair). New backend files
  `backend/app/auth/oauth2.go` and `backend/app/auth/config.go`; new env vars
  `AUTH_GATEWAY_PUBLIC_URL`, `OAUTH2_CLIENT_ID`, `OAUTH2_CLIENT_SECRET` plus a
  `PublicURL`/`OAuth2ClientID`/`OAuth2ClientSecret` `AuthConfig` and a `trimURL`
  normaliser (`backend/app/config/config.go`, `backend/.env.example`). Documented
  in `docs/{en,ru}/31-rest-api.md`.

### Security
- The confidential OAuth2 `code→token` / `refresh` exchange moved off the Nuxt
  frontend into the Go backend. Removed the Nuxt BFF routes
  `frontend/server/api/auth/{token,refresh}.post.ts`, the server-only
  `oauth2ClientSecret` runtime config and the unused `authGatewayApiUrl`
  (`frontend/nuxt.config.ts`), and dropped `NUXT_OAUTH2_CLIENT_SECRET` /
  `NUXT_PUBLIC_AUTH_GATEWAY_API_URL` from `frontend/.env.example`. The
  `OAUTH2_CLIENT_SECRET` now lives only in the backend env and never ships to the
  browser. (Also fixes the exchange, which posted `x-www-form-urlencoded` while the
  gateway binds `/oauth2/token` as JSON.)

### Changed
- Frontend OAuth2 code exchange (`composables/use-oauth2.ts`) and token refresh
  (`stores/auth.store.ts`) now call the backend (`${apiUrl}/auth/oauth2/token` and
  `/auth/oauth2/refresh`) instead of the removed Nuxt server routes.

### Fixed
- Frontend dev server no longer fails with `WebSocket server error: Port 24678 is
  already in use` when a second frontend runs at the same time. The Vite HMR
  WebSocket port is now derived from the dev-server `PORT` (`24678 + (PORT - 3001)`)
  instead of Vite's fixed `24678`, and can be overridden with a new `HMR_PORT` env
  var (`frontend/nuxt.config.ts`, `frontend/.env.example`).

### Added
- Migrated the full Health Monitor backend domain onto the Go (Gin + GORM) template.
  New modules under `backend/app/`:
  - `resource/` — the monitoring engine and CRUD. Endpoints (all under `/api`):
    `POST /resource`, `POST /resource/list`, `PATCH /resource/batch`,
    `GET /resource/uptime-report`, `GET /resource/:resourceId`,
    `PATCH /resource/:resourceId`, `DELETE /resource/:resourceId`,
    public `POST|GET /resource/webhook/:token` (heartbeat) and
    `GET /resource/:resourceId/status` (public status). Three 60s/5m scheduler tasks:
    HTTP/Heartbeat/Server health checks with consecutive-failure counting and
    maxFailures incident thresholds, weekly+one-shot maintenance windows (incl.
    overnight), and the buffered call-flush. Uptime report sorted by downtime impact.
  - `resource/` incidents sub-module: `POST /resource/incidents/list`,
    `.../list/csv`, `.../list/pdf`, `GET|PATCH /resource/incidents/:incidentId`.
    Incident lifecycle (open on threshold, append `detailsHistory`, close on ok),
    current-vs-previous-period statistics for the PDF.
  - `resource/` calls sub-module: `POST /resource/:resourceId/calls/list` backed by
    an in-memory buffer (flush every 5 min or at 5000 items, on shutdown, re-queue on failure).
  - `global-settings/` — global thresholds at `GET /settings` and `PATCH /settings`,
    defaults seeded on bootstrap; coexists with the key-value `settings` package.
  - `notifications/` — persisted alerts (`POST /notifications/list`,
    `PATCH /notifications/read`, `GET /notifications/unread-count`), integrations
    (`GET|POST /notification-integrations`, `PATCH|DELETE /notification-integrations/:id`,
    `POST /notification-integrations/:id/test`), device tokens
    (`POST|DELETE /device-tokens`), and a 4-transport alert dispatcher
    (Email via SMTP + html/template, Telegram HTML, Slack Block Kit with per-resource
    channel override, FCM multicast) ported 1:1 from the legacy service.
  - Websocket events `resource::status-updated` and `incident::updated` broadcast on
    status/incident changes; collection `resources::*` events on CRUD.
- SQL migration `backend/migrations/000002_monitoring.{up,down}.sql` for resources,
  incidents, calls, global_settings, notifications, notification_integrations, device_tokens.
- `MAIL_*` / `SMTP_*` config (`backend/app/config/config.go`) driving the email sender.
- Migrated the full Health Monitor frontend domain onto the design-system template
  (`frontend/`): dashboard (`pages/index.vue`), incidents (`pages/incidents.vue`),
  uptime report (`pages/uptime-report.vue`), resource detail (`pages/resource/[id].vue`),
  global monitor thresholds (`pages/monitor-settings.vue`), and notification integrations
  (`pages/notifications.vue`), all linked from the header nav in `layouts/default.vue`.
- Data layers following the `api → service → store` pattern: `resource`, `incidents`,
  `monitor-settings`, and `notifications` `*.api.ts` / `*.service.ts` / `*.store.ts`.
- Health-monitor components under `components/resource/` (`Table`, `StatsBar`, `Card`,
  `Form`, `DeleteConfirm`, `MaintenanceRules`) and `components/ui/` (`WeekdayPicker`,
  `DateTimePickerUtc`); `RESOURCE_FORM_POPUP` registered in the popup system.
- `constants/resource.ts` and `constants/maintenance.ts`; utils `extract-error-message`,
  `utc-datetime`, `format-maintenance`, `download-blob`.
- `composables/use-resource-stream.ts` subscribing to `resource::status-updated`,
  `resource::created|updated|deleted`, and `incident::updated` over the shared WS client.
- All monitor/incident/notification/settings i18n keys added to `en.json`, `de.json`,
  and `ru.json` in sync.

### Changed
- Extracted the shared infrastructure packages (`crypto`, `csv`, `interfaces`,
  `trace`, `types`, `utils`, `logger`, `health-check`, `scheduler`, `websocket`,
  `redis`, `database`) out of `backend/app/` into the external
  `github.com/BloodHeavenDevelop/utils` module (consumed via a local `replace`).
  These were byte-duplicated across services; there is now a single source of
  truth. `logger` no longer imports the service `config`: `server.go` wires it at
  startup via `logger.Init(logger.Config{…})`.
- The dashboard monitors list keeps its exact legacy appearance: `components/resource/Table.vue`
  and `StatsBar.vue` port the legacy CSS verbatim (grouped collapsible table, pulsing
  per-status status dots with their glow + pulse durations, colored left row-border,
  status checkboxes, inline server-metrics badge). Every other surface is rebuilt on the
  `.hm-*` design system and `components/ui/*` primitives.
- Synced `docs/en|ru/09-frontend-structure.md` with the Health Monitor domain layout.
- Frontend build-mode gating now reads `NUXT_PUBLIC_APP_ENV` instead of a separate
  `APP_ENV`: `frontend/nuxt.config.ts` skips the `@nuxt/eslint` module and stamps the
  `__APP_BUILD__` vite define from `NUXT_PUBLIC_APP_ENV`. The Dockerfile already exports
  `NUXT_PUBLIC_APP_ENV` before `pnpm build`, so production/staging builds now actually
  take that branch (the old `APP_ENV` was never passed at build time, so it never did).

### Removed

- Frontend `NUXT_PUBLIC_ADMIN_URL` — dropped from `nuxt.config.ts` `runtimeConfig.public`,
  `frontend/.env.example` and the frontend `CLAUDE.md` env table. It was never read (no
  admin-split frontend exists); reintroduce it if/when the client+admin split lands.
- Frontend `APP_ENV` — removed from `frontend/.env.example`, folded into the single
  canonical `NUXT_PUBLIC_APP_ENV`.

## [0.2.0] - 2026-05-31

### Added
- Frontend i18n via `@nuxtjs/i18n` with three locales shipped from the start —
  English, German, Russian (`frontend/i18n/locales/{en,de,ru}.json`), lazy-loaded,
  `prefix_except_default` strategy; all three files must stay in sync.
- Frontend test stack installed and wired: Vitest (`environment: 'nuxt'`,
  `frontend/vitest.config.ts`) with helpers/fixtures/setup under `frontend/tests/`,
  example unit and store tests, and Playwright (`frontend/playwright.config.ts`) with
  an e2e smoke spec; `pnpm test` now passes.
- `frontend/.nvmrc` pinning Node 24 (current LTS).

### Changed
- Frontend now renders **SSR by default** (`ssr: true`) with SEO that works: `site.url`
  reads `NUXT_PUBLIC_SITE_URL`, indexing/robots are gated to `NUXT_PUBLIC_APP_ENV=production`,
  and the global auth middleware only enforces the redirect on the client so SSR keeps working.
- Standardized public env vars to `NUXT_PUBLIC_API_URL` and `NUXT_PUBLIC_SITE_URL`
  (dropped the `*_BASE_URL`/`*_ENVIRONMENT` variants); added `NUXT_PUBLIC_ADMIN_URL`
  for split client+admin deployments. Updated `frontend/.env.example`, `runtimeConfig`,
  and `frontend/CLAUDE.md`.
- Renamed generated Swagger output `frontend/generated/deploy-crm.ts` →
  `frontend/generated/types.ts` and updated the `swagger:generate` script and post-processor.
- Renamed all `camelCase` composables to `kebab-case` and `stores/popup.ts` →
  `stores/popup.store.ts`; updated explicit imports. Documented the file-naming rule
  (kebab-case + `.dot-case` role suffix) in `frontend/CLAUDE.md`.
- Cleaned project-specific defaults out of `runtimeConfig.public` (removed `brandColor`,
  `logo*`, `recaptchaKey`, `ogImage`, `sseUrl`, `installMode`) and the hardcoded
  `admin.stage.tokenizer.estate` site URL.
- Synced `docs/en|ru/09-frontend-structure.md` with i18n, tests, SSR, and the
  `generated/types.ts` rename.

### Removed
- All Sentry references from `frontend/CLAUDE.md` and the Sentry `.gitignore` entry
  (the SDK was documented but never installed).
- Analytics (Google Tag Manager) and the mandatory CI-pipeline rule from
  `frontend/CLAUDE.md`; replaced stale Cypress `.gitignore` entries with Playwright ones.

### Fixed
- `pnpm lint` is green again: resolved pre-existing ESLint errors in
  `composables/use-entity-stream.ts` (`void` in union), `directives/v-account-can-see.ts`
  (dynamic delete), and `utils/parse-ansi.ts` (intentional ANSI control-char regex).
- Excluded the root `generated/` output from Prettier (matching the existing ESLint ignore).

## [0.1.0] - 2026-05-31

### Added
- Initial extraction of a reusable full-stack starter template: Go (Gin + GORM +
  PostgreSQL + Redis) backend and a Nuxt 4 + `@nuxt/ui` frontend with a dark
  dashboard design system.
- Backend skeleton keeps the cross-cutting infrastructure and auth stack only:
  `auth` (local login/refresh + JWT + OAuth2 gateway), `api-keys`, `permissions`
  (RBAC roles/grants), `events` + `notifier` + `messengergw`, `settings`,
  `websocket`, `scheduler`, `health-check`, plus `config`, `database`, `redis`,
  `logger`, `crypto`, `utils`, `csv`, `types`, `interfaces`.
- Single baseline migration `backend/migrations/000001_init.{up,down}.sql`
  creating only the kept tables (`api_keys`, `permission_grants`, `events`,
  `event_reads`, `settings`).
- Frontend skeleton keeps the UI component library (`components/ui/`), design
  system (`assets/styles/main.css`, `DESIGN_MANIFEST.md`), auth/RBAC stores,
  plugins, middleware, generic composables/utils, and the settings / api-keys /
  admin (RBAC) pages. Generated API types regenerated from the slimmed backend
  swagger.
- Documentation reduced to the generic set under `docs/en` and `docs/ru`.

### Changed
- `api-keys` and `events` list endpoints now use the standard `types.IListParam`
  (limit/offset/search) in place of the removed `querymanager` filter primitives.
- Root tooling reset for a template: `docker-compose.yaml` runs only Postgres +
  Redis; root `Makefile` exposes `up`/`down`/`backend`/`frontend`/`migrate`;
  `README.md` documents how to start a new project from the template.

