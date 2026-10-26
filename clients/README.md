# Своя игра — app (Android, Windows, Linux, macOS)

One Flutter client for Android phones and Windows / Linux / macOS computers with every
role of the game: **player**, **host** (runs the game), **screen** (read-only display)
and **admin** (creates the game, chooses the pack, settings, players' scores/latency/
offsets, pack library with a full editor, game file import/export, share link + QR).
Speaks the protocol in [`docs/en/05-protocol.md`](../docs/en/05-protocol.md).
Details per platform: [`docs/en/11-clients.md`](../docs/en/11-clients.md).

## Requirements

- Flutter 3.41+ (Dart 3.11+)
- Android: Android SDK (API 36 platform + build tools), JDK 17
- Linux: `clang`, `cmake`, `ninja`, `pkg-config`, GTK 3 and GStreamer development packages
- Windows: Visual Studio 2022 with «Desktop development with C++»
- macOS: Xcode

Desktop apps are built on their own OS.

## Commands

```bash
make deps             # flutter pub get
make analyze          # flutter analyze
make test             # flutter test
make run              # run on a connected device / emulator (DEVICE=linux|windows|macos|<id>)
make build-apk-debug  # build/app/outputs/flutter-apk/app-debug.apk
make build-apk        # build/app/outputs/flutter-apk/app-release.apk (debug-signed)
make build-apk APP_LINK_HOST=igra.example.com   # also open https://igra.example.com/g/<PIN>
make build-linux      # build/linux/x64/release/bundle/ (svoy_igra + lib/ + data/)
make build-windows    # build\windows\x64\runner\Release\ (svoy_igra.exe + DLLs + data\)
make build-macos      # build/macos/Build/Products/Release/SvoyIgra.app
make cert-sha256      # SHA-256 of the debug signing key → server env ANDROID_CERT_SHA256
```

## Using it

1. Start the server on the LAN (`backend/`, port 3050, discovery on UDP 3051).
2. Open the app: servers on the same network are found automatically (on a computer,
   allow the app in the firewall prompt); otherwise type the address, e.g.
   `http://192.168.1.10:3050`.
3. **Создать игру** — choose an admin PIN (4–8 digits); you become the game's admin and
   get its PIN, link and QR code. **Войти в игру** — enter the 6-digit game PIN (or
   pick a live game), then a role: player (name), host, screen or admin (admin PIN).
   Tokens are remembered per server and game, so «Продолжить как …» rejoins.

## Share links

Every build opens `svoyigra://join?server=<base>&pin=<PIN>`. Windows and Linux builds
register the scheme for the current user each time they start (Linux also adds a menu
entry); macOS declares it in `Info.plist`. A link opened while the app runs goes to the
open window.

The Android build, when made with `APP_LINK_HOST`, also opens
`http(s)://<APP_LINK_HOST>/g/<PIN>` as verified Android App Links. For verification set
`ANDROID_CERT_SHA256` on the server to the signing certificate's SHA-256 fingerprint:
`make cert-sha256` for the debug key, or `keytool -list -v -keystore <release.jks> -alias <alias>`
for a release key.

Fonts (Unbounded, Inter, JetBrains Mono) are bundled from Google Fonts under the SIL
Open Font License 1.1.
