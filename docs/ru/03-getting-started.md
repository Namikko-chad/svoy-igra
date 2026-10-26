# Начало работы

## Требования

| Для | Нужно |
|---|---|
| бэкенд | Go (версия в `backend/go.mod`), `make` |
| веб-клиент | Node.js (см. `frontend/.nvmrc`, если есть), `pnpm` |
| Android-приложения | Flutter SDK + Android SDK |
| десктопное приложение | Flutter SDK + инструменты ОС (Linux: `clang`, `cmake`, `ninja`, dev-пакеты GTK 3 / GStreamer; Windows: Visual Studio 2022 C++; macOS: Xcode) |
| контейнеры | Docker с Compose |

## Конфигурация бэкенда (`backend/.env`)

Скопируйте `backend/.env.example` в `backend/.env`.

| Переменная | По умолчанию | Значение |
|---|---|---|
| `SERVER_HOST` | `0.0.0.0` | адрес привязки |
| `SERVER_PORT` | `3050` | HTTP-порт (REST + WebSocket) |
| `SERVER_NAME` | `Своя игра` | имя, которое сообщается при обнаружении в LAN и в `/api/info` |
| `DATA_DIR` | `./data` | паки (`packs/<id>/`), игры (`games/<id>.json`) и их аватары (`avatars/<gameId>/`) |
| `MAX_UPLOAD_MB` | `1024` | максимальный размер загружаемого файла `.dub`/медиа и распакованного пака |
| `GAME_IDLE_MINUTES` | `60` | игра, к которой никто не подключён столько времени, удаляется |
| `MAX_GAMES` | `100` | максимальное число одновременных игр |
| `ANDROID_PACKAGE` | `dev.svoyigra.mobile` | id приложения, объявляемый в `/.well-known/assetlinks.json` |
| `ANDROID_CERT_SHA256` | пусто | SHA-256 отпечатки сертификата подписи (через запятую) для Android App Links; пусто → `assetlinks.json` нет |
| `STATIC_DIR` | пусто | раздавать собранный веб-клиент (например, `../frontend/dist`) с того же порта |
| `WEB_URL` | пусто | публичный адрес веб-клиента, используемый в ссылках-приглашениях (`<WEB_URL>/g/<PIN>`) и возвращаемый как `webUrl` из `/api/info`; пусто → адрес страницы/приложения, создавшего игру |
| `DISCOVERY_PORT` | `3051` | UDP-порт для обнаружения в LAN; `0` отключает |
| `CORS_ORIGINS` | `*` | разрешённые источники (origins) браузера |
| `LOG_LEVEL` | `info` | `debug`/`info`/`warn`/`error` |

Makefile загружает `.env`, и его значения имеют приоритет над окружением оболочки.

## Запуск для разработки

```bash
cd backend && make development        # :3050, UDP :3051
cd frontend && pnpm install && pnpm dev   # :3000, проксирует /api (и WebSocket) на :3050
```

Откройте `http://<computer-ip>:3000`, нажмите «Создать игру», выберите PIN админа и отправьте
ссылку-приглашение игрокам. Все остальные вводят PIN игры (или открывают ссылку)
и выбирают роль.

Команды оператора: `svoy-igra unlock-pack <pack-id>` (или `go run . unlock-pack <id>` в
`backend/`) снимает блокировку с пака; `svoy-igra healthcheck` завершается с кодом 0, если
локальный сервер отвечает на `/api/health`.

## Один бинарник для вечеринки

```bash
cd frontend && pnpm build
cd ../backend && make build
STATIC_DIR=../frontend/dist ./bin/svoy-igra
```

После этого всё раздаётся с `http://<computer-ip>:3050`.

## Docker

```bash
docker compose up -d --build
```

Один образ (корневой `Dockerfile`, ~13 МБ): Go-сервер на `:3050` отдаёт API, WebSocket и
веб-клиент; финальная стадия — `scratch` (статический бинарник и собранный сайт), запуск
от непривилегированного пользователя, проверка здоровья контейнера — `svoy-igra healthcheck`.
Данные сохраняются в томе `game-data`. Широковещательное UDP-обнаружение обычно не проходит
через проброс портов Docker; телефоны и ТВ всё равно могут подключиться, введя адрес вручную.

## Роутер MikroTik (RouterOS 7.21+, arm64)

Сервер может работать контейнером на arm64-MikroTik (RB5009, hAP ax², hAP ax³,
CCR2004/2116, Chateau…). Это тот же образ на `scratch`, собранный под arm64 с
`APP_USER=0:0` (точки монтирования в RouterOS принадлежат root).

```bash
make mikrotik        # → build/svoy-igra-arm64.tar (~12 МБ), эмуляция не нужна
```

Загрузите tar на роутер (Winbox *Files* или `scp build/svoy-igra-arm64.tar admin@192.168.88.1:/usb1/`)
и выполните, поправив имя диска (`usb1`, `nvme1`, `disk1`…) и адреса под свою сеть:

```routeros
# 1. Режим контейнеров — один раз; подтвердите кнопкой reset / перезагрузкой по питанию, как попросит роутер.
/system/device-mode/update container=yes

# 2. Сеть: контейнер включается прямо в LAN-мост, поэтому телефоны и ТВ
#    видят его по собственному адресу и работает обнаружение в локальной сети (UDP broadcast).
/interface/veth/add name=veth-igra address=192.168.88.5/24 gateway=192.168.88.1
/interface/bridge/port/add bridge=bridge interface=veth-igra

# 3. Настройки и постоянные данные (паки, игры, аватары).
/container/config/set tmpdir=usb1/tmp
/container/envs/add list=igra key=WEB_URL value=http://192.168.88.5:3050
/container/mounts/add list=igra-data src=usb1/igra-data dst=/data

# 4. Сам контейнер.
/container/add file=usb1/svoy-igra-arm64.tar interface=veth-igra root-dir=usb1/igra \
    envlist=igra mountlists=igra-data name=svoy-igra logging=yes start-on-boot=yes
/container/start [find name=svoy-igra]
```

После этого откройте `http://192.168.88.5:3050`. Замечания:

- RouterOS сохраняет в `/container/envs` только младший байт каждого символа, поэтому
  кириллица приходит искажённой («Своя игра» превращается в «!2>O 83@0»). Не задавайте
  `SERVER_NAME` (встроенное имя — «Своя игра») или пишите латиницей.
- Адрес контейнера берите **вне DHCP-пула** (`/ip/pool/print`; стандартный пул —
  `192.168.88.10–254`, поэтому здесь `.5`).
- Контейнерам нужен диск в ext4: в FAT32 нет прав доступа и ссылок, которые используют слои образа.
- Если флеш-память роутера маленькая, держите корень контейнера и данные на внешнем
  накопителе (USB/NVMe); образу нужно ~25 МБ в распакованном виде плюс медиа ваших паков.
- Имена параметров в `/container` менялись между выпусками RouterOS 7 (в 7.21 монтирования
  переехали в `mountlists`); если имя не принимается, проверьте его автодополнением по Tab.
- RouterOS игнорирует `HEALTHCHECK` образа; `logging=yes` отправляет журнал сервера в
  журнал роутера.
- За NAT вместо LAN-моста (отдельный мост `containers`, `dst-nat` TCP 3050 на контейнер)
  работает всё, кроме обнаружения в локальной сети — адрес роутера вводится в приложениях вручную.
- Обновление: загрузите новый tar, `/container/stop`, `/container/remove` и добавьте контейнер
  заново с тем же `root-dir`, переменными и монтированиями; том с данными сохраняет все паки и игры.

## Приложения

```bash
make -C clients build-apk       # Android: release APK (подписан debug-ключом)
make -C clients build-linux     # Linux:   build/linux/x64/release/bundle/svoy_igra
make -C clients build-windows   # Windows: build\windows\x64\runner\Release\svoy_igra.exe
make -C clients build-macos     # macOS:   build/macos/Build/Products/Release/SvoyIgra.app
make -C tv build-apk
```

Десктопные сборки делаются на своей ОС (Linux — нужны `clang`, `cmake`, `ninja` и dev-пакеты
GTK 3 / GStreamer; Windows — Visual Studio 2022 с C++; macOS — Xcode). Скопируйте папку сборки
целиком (или `.app`) на компьютер и запустите `svoy_igra` / `svoy_igra.exe` / `SvoyIgra.app`;
установка не нужна. Разрешите приложению доступ в окне брандмауэра (Windows, macOS), иначе оно
не найдёт серверы в локальной сети.

При первом запуске приложение ищет серверы в сети (широковещательный UDP) и предлагает
найденные; вместо этого можно ввести адрес вида `http://192.168.1.10:3050`.
Затем ТВ-приложение показывает список текущих игр; оно управляется D-pad пульта.

### Сборки на GitHub Actions

`.github/workflows/builds.yml` собирает все приложения на машинах GitHub: десктоп для
Windows (`svoy-igra-<version>-windows-x64.zip`), macOS (`…-macos.zip`, universal) и
Linux (`…-linux-x64.tar.gz`), а также APK для телефона (`svoy-igra-<version>.apk`) и ТВ
(`svoy-igra-tv-<version>.apk`). `<version>` — версия сервера из
`backend/app/config/config.go`; номер сборки — номер запуска.

- Запуск: **Actions → Builds → Run workflow**; файлы — артефакты запуска.
- Тег `vX.Y.Z` дополнительно публикует их как релиз на GitHub.
- Настройки репозитория (**Settings → Secrets and variables → Actions**):
  - секрет `ANDROID_DEBUG_KEYSTORE` — `base64 -w0 ~/.android/debug.keystore`. APK подписываются
    этим ключом, поэтому установленные приложения обновляются поверх, а `ANDROID_CERT_SHA256`
    остаётся верным. Без него каждый запуск подписывает новым случайным ключом (в запуске будет
    предупреждение);
  - переменная `APP_LINK_HOST` (необязательно) — хост ссылок `https://<host>/g/<PIN>`, которые
    открывает приложение на телефоне.
- Номер сборки в CI больше, чем у локальной (`1`), поэтому после установки APK из CI локальная
  сборка ставится только после удаления приложения.
- Десктопные сборки не подписаны сертификатом разработчика: Windows SmartScreen попросит
  подтвердить («Подробнее» → «Выполнить в любом случае»); на macOS в первый раз откройте
  приложение через правый клик → «Открыть» или выполните `xattr -dr com.apple.quarantine SvoyIgra.app`.

### Ссылки-приглашения, открывающие приложение

- `svoyigra://join?server=…&pin=…` всегда открывает приложение (на телефоне или компьютере;
  десктопное приложение регистрирует ссылку для текущего пользователя при запуске); веб-страница `/g/<PIN>`
  показывает для неё на Android «Открыть в приложении» (работает в LAN).
- Для публичного домена соберите приложение командой `make -C clients build-apk APP_LINK_HOST=igra.example.com`
  и задайте на сервере `ANDROID_CERT_SHA256` равным отпечатку сертификата подписи APK
  (`keytool -list -v -keystore <keystore>` → `SHA256:`). Тогда ссылки `https://igra.example.com/g/<PIN>`
  открывают Android-приложение напрямую; на компьютере они открываются в браузере.

## Тесты

```bash
make -C backend test          # включает полную игру по HTTP + WebSocket
cd frontend && pnpm test
make -C clients test
make -C tv test
```
