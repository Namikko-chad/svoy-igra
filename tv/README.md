# Своя игра — экран (Android TV)

The TV display of the quiz: board, questions with media, timer, scores and the
final podium. It joins one game on the server (chosen from the list or by PIN) as the read-only `screen`
role — no login, no input besides choosing the server and the game. Players
use their phones; the host runs the game from the web UI.

## Getting started

```bash
make deps             # flutter pub get
make run              # run on a connected TV / emulator
make build-apk-debug  # build/app/outputs/flutter-apk/app-debug.apk
make build-apk        # release APK (signed with the debug key for now)
make analyze test
```

Install on a TV over ADB: `adb connect <tv-ip>` then
`adb install -r build/app/outputs/flutter-apk/app-debug.apk`. The app shows up in
the Android TV launcher row ("Своя игра — экран").

## Using it

1. On first start the app scans the LAN (UDP broadcast on port 3051). One server
   found → it is chosen at once; several → pick one with the D-pad; none → type
   the address (`192.168.1.10:3050`).
2. Pick a live game from the list (refreshed every 5 s; the list shows no PINs) — or
   press «Ввести PIN» and type the 6-digit game PIN with the on-screen pad or the
   remote's number keys. The TV joins as a read-only screen. Only a screen joined by
   PIN shows the join link, QR and PIN in the lobby; one picked from the list says
   that the administrator hands out the link.
3. Server, PIN and screen token are remembered: the next start goes straight to the game.
   If the game is closed or expires, the TV returns to the games list («Игра закрыта»).
4. **Back**, **Menu** or **OK** on the game display opens a menu to switch the game
   or the server.

Architecture and conventions: [CLAUDE.md](CLAUDE.md).
