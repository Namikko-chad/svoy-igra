# Getting started

## Requirements

| For | Need |
|---|---|
| backend | Go (version in `backend/go.mod`), `make` |
| web client | Node.js (see `frontend/.nvmrc` if present), `pnpm` |
| Android apps | Flutter SDK + Android SDK |
| desktop app | Flutter SDK + the OS toolchain (Linux: `clang`, `cmake`, `ninja`, GTK 3 / GStreamer dev; Windows: Visual Studio 2022 C++; macOS: Xcode) |
| containers | Docker with Compose |

## Backend configuration (`backend/.env`)

Copy `backend/.env.example` to `backend/.env`.

| Variable | Default | Meaning |
|---|---|---|
| `SERVER_HOST` | `0.0.0.0` | bind address |
| `SERVER_PORT` | `3050` | HTTP port (REST + WebSocket) |
| `SERVER_NAME` | `Своя игра` | name answered to LAN discovery and `/api/info` |
| `DATA_DIR` | `./data` | packs (`packs/<id>/`), games (`games/<id>.json`) and their avatars (`avatars/<gameId>/`) |
| `MAX_UPLOAD_MB` | `1024` | max size of an uploaded `.dub`/media file and of an unpacked pack |
| `GAME_IDLE_MINUTES` | `60` | a game with nobody connected this long is deleted |
| `MAX_GAMES` | `100` | maximum simultaneous games |
| `ANDROID_PACKAGE` | `dev.svoyigra.mobile` | app id announced in `/.well-known/assetlinks.json` |
| `ANDROID_CERT_SHA256` | empty | signing-certificate SHA-256 fingerprints (comma-separated) for Android App Links; empty → no `assetlinks.json` |
| `STATIC_DIR` | empty | serve a built web client (e.g. `../frontend/dist`) from the same port |
| `WEB_URL` | empty | public address of the web client used in share links (`<WEB_URL>/g/<PIN>`) and returned as `webUrl` by `/api/info`; empty → the address of the page/app that created the game |
| `DISCOVERY_PORT` | `3051` | UDP port for LAN discovery; `0` disables |
| `CORS_ORIGINS` | `*` | allowed browser origins |
| `LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error` |

The Makefile loads `.env` and its values take precedence over the shell environment.

## Run for development

```bash
cd backend && make development        # :3050, UDP :3051
cd frontend && pnpm install && pnpm dev   # :3000, proxies /api (and the WebSocket) to :3050
```

Open `http://<computer-ip>:3000`, press «Создать игру», choose an admin PIN and send
the share link to the players. Everyone else enters the game PIN (or opens the link)
and picks a role.

Operator commands: `svoy-igra unlock-pack <pack-id>` (or `go run . unlock-pack <id>` in
`backend/`) removes the lock from a pack; `svoy-igra healthcheck` exits 0 when the local
server answers `/api/health`.

## One binary for a party

```bash
cd frontend && pnpm build
cd ../backend && make build
STATIC_DIR=../frontend/dist ./bin/svoy-igra
```

Everything is then served from `http://<computer-ip>:3050`.

## Docker

```bash
docker compose up -d --build
```

One image (root `Dockerfile`, ~13 MB): the Go server on `:3050` serves the API, the
WebSocket and the web client; the final stage is `scratch` (a static binary and the built
site), running as an unprivileged user, with `svoy-igra healthcheck` as the container
health check. Data persists in the `game-data` volume. UDP broadcast discovery usually does not pass
through Docker's port mapping; phones and TVs can still connect by typing the address.

## MikroTik router (RouterOS 7.21+, arm64)

The server can run as a container on an arm64 MikroTik (RB5009, hAP ax², hAP ax³,
CCR2004/2116, Chateau…). The image is the same `scratch` image built for arm64 with
`APP_USER=0:0` (RouterOS mounts are owned by root).

```bash
make mikrotik        # → build/svoy-igra-arm64.tar (~12 MB), no emulation needed
```

Upload the tar to the router (Winbox *Files*, or `scp build/svoy-igra-arm64.tar admin@192.168.88.1:/usb1/`)
and run, adjusting the disk name (`usb1`, `nvme1`, `disk1`…) and addresses to your network:

```routeros
# 1. Container mode — once; confirm with the reset button / power cycle as prompted.
/system/device-mode/update container=yes

# 2. Network: put the container straight into the LAN bridge, so phones and TVs
#    reach it at its own address and LAN discovery (UDP broadcast) works.
/interface/veth/add name=veth-igra address=192.168.88.5/24 gateway=192.168.88.1
/interface/bridge/port/add bridge=bridge interface=veth-igra

# 3. Settings and persistent data (packs, games, avatars).
/container/config/set tmpdir=usb1/tmp
/container/envs/add list=igra key=WEB_URL value=http://192.168.88.5:3050
/container/mounts/add list=igra-data src=usb1/igra-data dst=/data

# 4. The container itself.
/container/add file=usb1/svoy-igra-arm64.tar interface=veth-igra root-dir=usb1/igra \
    envlist=igra mountlists=igra-data name=svoy-igra logging=yes start-on-boot=yes
/container/start [find name=svoy-igra]
```

Then open `http://192.168.88.5:3050`. Notes:

- RouterOS keeps only the low byte of each character typed into `/container/envs`, so
  Cyrillic values arrive garbled («Своя игра» becomes «!2>O 83@0»). Leave `SERVER_NAME`
  unset (the built-in name is «Своя игра») or use Latin letters.
- Pick the container's address **outside the DHCP pool** (`/ip/pool/print`; the default
  pool is `192.168.88.10–254`, hence `.5` here).
- Containers need an ext4 disk: FAT32 lacks the permissions and links image layers use.
- Keep the container's root and data on external storage (USB/NVMe) when the router's
  flash is small; the image needs ~25 MB unpacked plus your packs' media.
- Parameter names in `/container` have changed between RouterOS 7 releases (7.21 moved
  mounts to `mountlists`); if a name is rejected, check it with Tab completion.
- RouterOS ignores the image's `HEALTHCHECK`; `logging=yes` sends the server log to the
  router log.
- Behind NAT instead of the LAN bridge (a separate `containers` bridge, `dst-nat` of TCP
  3050 to the container), everything works except LAN discovery — type the router's
  address in the apps.
- To update: upload the new tar, `/container/stop`, `/container/remove`, and add it again
  with the same `root-dir`, envs and mounts; the data mount keeps every pack and game.

## Apps

```bash
make -C clients build-apk       # Android: release APK (debug-signed)
make -C clients build-linux     # Linux:   build/linux/x64/release/bundle/svoy_igra
make -C clients build-windows   # Windows: build\windows\x64\runner\Release\svoy_igra.exe
make -C clients build-macos     # macOS:   build/macos/Build/Products/Release/SvoyIgra.app
make -C tv build-apk
```

Desktop builds are made on their own OS (Linux needs `clang`, `cmake`, `ninja` and the
GTK 3 / GStreamer development packages; Windows — Visual Studio 2022 with C++; macOS —
Xcode). Copy the whole output folder (or the `.app`) to the computer and start
`svoy_igra` / `svoy_igra.exe` / `SvoyIgra.app`; nothing is installed. Allow the app in
the firewall prompt (Windows, macOS) so it can find servers on the LAN.

On first start the app searches the network for servers (UDP broadcast) and offers
the found ones; an address such as `http://192.168.1.10:3050` can be typed instead.
The TV app then lists the live games; it is driven with the remote's D-pad.

### Share links opening the app

- `svoyigra://join?server=…&pin=…` always opens the app (phone or computer; a desktop
  app registers the link for the current user when it starts); the web page `/g/<PIN>`
  shows «Открыть в приложении» on Android for it (works in a LAN).
- For a public domain, build the app with `make -C clients build-apk APP_LINK_HOST=igra.example.com`
  and set `ANDROID_CERT_SHA256` on the server to the APK signing-certificate fingerprint
  (`keytool -list -v -keystore <keystore>` → `SHA256:`). Links `https://igra.example.com/g/<PIN>`
  then open the Android app directly; computers open them in the browser.

## Tests

```bash
make -C backend test          # includes a full game over HTTP + WebSocket
cd frontend && pnpm test
make -C clients test
make -C tv test
```
