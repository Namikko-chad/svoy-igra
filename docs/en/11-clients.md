# App clients (Android, Windows, Linux, macOS)

One Flutter app in `clients/`, built for Android phones and for Windows, Linux and macOS
desktops. Every build has the same features as the web client: create or join games;
player, host, admin (pack library, full pack editor, game file import/export) and screen
roles. It opens share links. Project rules live in `clients/CLAUDE.md`.

## Platforms

| | Android | Windows | Linux | macOS |
|---|---|---|---|---|
| `hello.platform` | `android` | `windows` | `linux` | `macos` |
| Video | `video_player` | `fvp` (libmdk) | `fvp` (libmdk) | `video_player` (AVFoundation) |
| Avatar | gallery or camera | image file | image file | image file |
| Share button | share sheet | system share | — (copy only) | share sheet |
| `svoyigra://` | manifest | registered on start (current user) | registered on start (`.desktop` file) | `Info.plist` |
| `https://…/g/<PIN>` | App Links | — | — | — |

Desktop differences, all in the platform layer:

- `lib/core/platform.dart` (`clientPlatform`, `isDesktop`) is the only switch; texts that
  name the device say «компьютер» instead of «телефон», the avatar sheet offers a file
  instead of gallery + camera.
- `lib/data/device.dart` fills `hello` per OS: Windows — computer name and edition
  (build 22000+ is reported as Windows 11); Linux — DMI vendor + product and the
  distribution name; macOS — model name and version. `screen` is the display size.
- `lib/data/url_scheme.dart` registers `svoyigra://` on every start, for the current user
  and the copy that was started last: Windows writes `HKCU\Software\Classes\svoyigra`;
  Linux writes `~/.local/share/applications/dev.svoyigra.client.desktop` (menu entry with
  icon) and runs `xdg-mime default`. macOS declares the scheme in `Info.plist`.
- Single instance: opening a link while the app runs hands it to the open window
  (Windows: `SendAppLink` in `windows/runner/main.cpp`; Linux: unique `GApplication` in
  `linux/runner/my_application.cc`; macOS: the system does it). On Linux the link that
  starts the app arrives as the first argument of `main`.
- Window: title «Своя игра», 1280 × 800 at start, at least 400 × 560 (the phone layout
  still works). macOS runs sandboxed with network client/server (UDP discovery) and
  user-selected file access; `NSAllowsArbitraryLoads` allows plain-HTTP LAN media.
- The Android APK leaves out the `fvp` native libraries (`android/app/build.gradle.kts`).


## Flow

1. **Server** — the app broadcasts a discovery probe (UDP 3051, re-sent every 700 ms for
   2.5 s), lists found and recently used servers, and accepts a typed address. Every
   address is checked with `GET /api/info`.
2. **Game** — on the server screen:
   - «Мои игры»: seats this device holds on that server (validated with `/api/auth/me`;
     dead ones are forgotten);
   - «Игры на сервере»: the live games (`GET /api/games`, without PINs) — only «Смотреть»
     (a screen without PIN) is offered; playing needs the PIN from the admin;
   - «Войти в игру»: a 6-digit game PIN;
   - «Создать игру»: optional title and an admin PIN (4–8 digits, entered twice) → the
     admin screen of the new game.
3. **Role** — the game card, «Продолжить как …», then Игрок (name), Ведущий (disabled while
   taken), Экран, Администратор (admin PIN).
4. **Session** — one WebSocket per screen (`GameSocket`). «Выйти» sends `leave` (a player
   confirms first: the seat and score are removed) and forgets the token; the system Back
   button only closes the screen. Close codes `4001`/`4003`/`4004` forget the token and
   return with a message («Игра закрыта» for `4004`); `4009` offers «Продолжить здесь».

## Share links

- `svoyigra://join?server=<base>&pin=<PIN>` — always handled (the web page `/g/<PIN>`
  offers it as «Открыть в приложении» on Android).
- `http(s)://<APP_LINK_HOST>/g/<PIN>` — Android App Links, the host is fixed at build time:
  `make build-apk APP_LINK_HOST=igra.example.com`. Unset, the filter uses the host
  `app-links.invalid`, which never matches. `make cert-sha256` prints the debug-key
  fingerprint for the server's `ANDROID_CERT_SHA256`.

A link opens the role step for that server and game (`app_links`, parsing in
`lib/data/deeplink.dart`).

## Screens

| Role | Screen |
|---|---|
| Player | scoreboard, board (tappable on my turn), question blocks, timer bar, buzzer, typed answer, reveal, round/final standings; landscape uses a side panel |
| Host | tabs **Игра** (start once the admin loaded a pack, every host command, answer + comment always visible, judge bar, typed answer, chooser/kick per player, rounds, reset) and **Настройки** (timers, penalty) |
| Admin | tabs **Игра** (PIN, share link with copy / share sheet / QR, phase, host status, pack choice, all settings incl. latency compensation, game file export/import, rename, admin PIN, reset, close game), **Игроки** (score ±100 / custom / set, RTT last/avg/jitter coloured by the latency scale, last seen, button shift −5000…10000 ms and effective shift, stats, device, kick), **Пакеты** (library: create, import `.dub`, export, delete, lock, «Редактировать копию» for locked packs) |
| Pack editor | meta; rounds → categories (≤ 10, warning when ≠ 10) → questions; drag to reorder; question form with value, reading-time override, markdown fields with live preview; media manager (gallery/audio/any file upload with progress, preview, delete, insert at cursor); a banner on locked packs |
| Screen | read-only display; video and audio autoplay with sound; lobby with PIN, link and QR |

## Special questions and the final

`features/game/special.dart` shows the modifier splash, the cat transfer and the auction
(amount with ±100 steps, «Ставка», «Ва-банк», «Пас»); `features/game/final_panel.dart` covers
theme removal, bets, the timed written answer and judging. The host acts on behalf of the
chooser or remover and closes bids, bets and answers. Solo questions show no buzzer.
The pack editor has a «Финал» switch per round (one question per theme, no value) and a
markdown toolbar (`features/editor/markdown_format.dart`) with «Медиа» on every field.

## Media

Images via `Image.network`; video via `video_player` — on Windows and Linux backed by
`fvp`, registered automatically (players: muted autoplay, host:
controls, screen: autoplay with sound); audio via `audioplayers` (players: «звучит на
экране» chip with manual play). Markdown via `flutter_markdown_plus` (CommonMark; raw
HTML is shown as text). Relative URLs are prefixed with the server address.

## Build

```bash
make -C clients analyze test
make -C clients build-apk-debug   # build/app/outputs/flutter-apk/app-debug.apk
make -C clients build-apk         # release APK, signed with the debug key
make -C clients build-apk APP_LINK_HOST=igra.example.com
make -C clients build-linux       # build/linux/x64/release/bundle/svoy_igra
make -C clients build-windows     # build\windows\x64\runner\Release\svoy_igra.exe
make -C clients build-macos       # build/macos/Build/Products/Release/SvoyIgra.app
make -C clients run DEVICE=linux  # or windows / macos / an Android device id
```

Each desktop build runs on its own OS: Flutter does not cross-compile desktop apps.
GitHub Actions builds all of them, and both APKs, in one run (`.github/workflows/builds.yml`,
see [Getting started](03-getting-started.md#builds-on-github-actions)).
Requirements: Linux — `clang`, `cmake`, `ninja`, GTK 3 and GStreamer development
packages (`fvp` downloads its libmdk at build time); Windows — Visual Studio 2022 with
«Desktop development with C++»; macOS — Xcode. Ship the whole output folder (Linux,
Windows) or the `.app` (macOS); desktop builds are not signed.

Android app id `dev.svoyigra.mobile` (kept so installed phones update in place); desktop
id `dev.svoyigra.client`. Cleartext HTTP is allowed (LAN servers). Fonts are bundled.
