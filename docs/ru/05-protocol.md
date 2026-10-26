# Протокол

Единственный источник истины для всех клиентов (веб, приложения, ТВ) и бэкенда. Клиент,
который расходится с этим файлом, неправ; бэкенд, который расходится с ним, неправ.
Меняйте файл и все реализации вместе.

- Базовый URL: `http(s)://<server>:<port>`. Все REST-эндпоинты находятся под `/api`.
- Все ключи JSON — в `camelCase`. Всё время — **Unix-миллисекунды, UTC** (`number`).
- URL медиа, которые возвращает сервер, **относительные** (`/api/packs/...`). Клиент,
  который раздаётся не с того же источника (приложения, ТВ), добавляет в начало базовый URL своего сервера.

## 1. Игры и роли

Один сервер ведёт **много игр одновременно**. Игра идентифицируется 6-значным **PIN игры**
и имеет ссылку-приглашение `<base>/g/<PIN>` (§8). Общесерверных паролей нет.

- Для **создания** игры PIN не нужен: создатель выбирает **PIN админа** (4–8 цифр)
  и становится первым админом игры.
- Для **входа** в существующую игру нужен PIN игры, затем выбирается роль:

| Роль | Вход с | Ограничение | Что видит |
|---|---|---|---|
| `player` | PIN игры + имя | — | табло, вопрос (ответ — только при показе), очки, свою кнопку |
| `host` | PIN игры | **один одновременно** (`409 host_taken`) | табло, вопрос **и ответ**, введённый ответ, очки, настройки; ведёт игру |
| `screen` | PIN игры **или** публичный id игры из списка (`watch`) | — | отображение только для чтения: табло, вопрос, очки, кто отвечает; ответ — при показе. Экран из списка никогда не получает ни PIN, ни ссылку-приглашение |
| `admin` | PIN игры + PIN админа | — | игроков (очки, устройства, задержку, сдвиги, статистику), пак, фазу, настройки — никогда не видит табло/вопрос/ответ идущей игры; управляет общей библиотекой паков и файлом этой игры |

Слот ведущего свободен, если токена ведущего нет, или у его владельца нет открытого сокета
в течение 30 с, или владелец отправил `leave`. Занятие свободного слота отзывает предыдущий
токен ведущего.

Игра **без открытых сокетов** в течение `GAME_IDLE_MINUTES` (по умолчанию 60) удаляется вместе
с её токенами. Сокеты, открытые в момент закрытия игры её админом, получают код закрытия `4004`; после
удаления её токены просто неизвестны — REST отвечает `401 unauthorized`, новый сокет
закрывается с `4001`, `GET /api/games/{pin}` отвечает `404 game_not_found`. Клиенты обрабатывают
`4001` и `4004` одинаково: забывают токен. Паки не являются частью игры и переживают её.

Список текущих игр (`GET /api/games`) публичен намеренно, но в нём **никогда нет
PIN игры и ссылки-приглашения**: именно PIN позволяет войти игроком, ведущим или
админом. Из списка можно только *наблюдать* за игрой как экран (`POST /api/games/{id}/watch`);
такой экран везде получает `pin: null` и `link: null` (результат входа, `/api/auth/me`,
`welcome`, каждый `state`), поэтому его лобби не может показать QR-код. Экран, вошедший
по PIN, видит и то и другое.

Каждый токен принадлежит ровно одной игре и одной роли. Токены — непрозрачные строки, передаваемые
как `Authorization: Bearer <token>` (REST) или `?token=<token>` (WebSocket). Клиенты хранят
их по серверу + PIN игры, чтобы перезагрузка или перезапуск приложения возвращали в игру незаметно.

## 2. REST

Ошибки: любой не-2xx ответ содержит `{"error": {"code": "<snake_case>", "message": "<human text>"}}`.
`4xx` = клиент может это исправить (сообщение осмысленное). `500` = сбой сервера,
сообщение общее (`internal_error`), подробности есть только в логе сервера.

### 2.1 Публичные

| Метод | Путь | Тело | Ответ |
|---|---|---|---|
| GET | `/api/health` | — | `{"status":"ok"}` |
| GET | `/api/info` | — | `{"name": string, "version": string, "serverNow": number, "webUrl": string \| null}` |
| GET | `/api/games` | — | `GameInfo[]` с `pin: null`, `link: null` — все текущие игры, сначала самые новые |
| POST | `/api/games/{id}/watch` | — | `JoinResult` с ролью `screen` и `pin`/`link`, равными null; `404 game_not_found` |
| POST | `/api/games` | `{"adminPin": string, "title"?: string}` | `JoinResult` (201) с ролью `admin`; `400 invalid_admin_pin` (не 4–8 цифр), `400 invalid_title` (> 60 символов), `503 too_many_games` |
| GET | `/api/games/{pin}` | — | `GameInfo`; `404 game_not_found` |
| POST | `/api/games/{pin}/join` | `{"role": Role, "name"?: string, "adminPin"?: string}` | `JoinResult`; `404 game_not_found`, `400 invalid_role`, `400 invalid_name` (игрок: пустое / > 32 символов), `409 name_taken`, `409 host_taken`, `401 invalid_admin_pin` |
| GET | `/api/auth/me` | (Bearer) | `JoinResult` без `token`; `401 unauthorized` (неизвестный токен или удалённая игра) |
| GET | `/api/packs/{packId}/media/{name}` | — | файл (поддерживает HTTP `Range`), `404 not_found` |
| GET | `/.well-known/assetlinks.json` | — | заявление Android App Links (§8); `404`, если не настроено |
| POST | `/api/avatar` | (Bearer-токен игрока или ведущего) multipart-поле `file` | `{"avatarUrl": string}`; `403 forbidden` для других ролей, `400 invalid_image` (не PNG/JPEG/WebP/GIF), `413 too_large` (> 2 МиБ) |
| DELETE | `/api/avatar` | (Bearer-токен игрока или ведущего) | 204 |
| GET | `/api/games/{gameId}/avatars/{file}` | — | изображение; `404 not_found` |

**Аватары.** Игрок устанавливает собственный аватар, ведущий — аватар ведущего. Клиенты обрезают
картинку до квадрата и уменьшают её не более чем до 512×512 перед загрузкой. Каждая загрузка получает
новое случайное имя файла (URL меняется, поэтому кэши никогда не показывают устаревшую картинку) и
заменяет предыдущую. URL аватаров содержат публичный id игры, но никогда не её PIN. Они
живут столько же, сколько игра (удаляются вместе с ней).

`webUrl` — публичный адрес веб-клиента (env `WEB_URL`); `null` означает, что веб-клиент
раздаётся с собственного адреса сервера.

Имена игроков уникальны без учёта регистра в пределах игры. Клиент, у которого есть токен,
**не** входит повторно — он переподключает WebSocket с этим токеном. Неверный PIN админа
стоит 500 мс.

### 2.2 Только для админа

Bearer-**токен админа любой игры**; иначе `401 unauthorized` / `403 forbidden`.
Библиотека паков общая для всех игр.

| Метод | Путь | Тело | Ответ |
|---|---|---|---|
| GET | `/api/packs` | — | `PackSummary[]` (сначала самые новые по `updatedAt`) |
| POST | `/api/packs` | `{"title":string}` | `Pack` (201) |
| POST | `/api/packs/import` | multipart, поле `file` = `.dub` | `PackSummary` (201); `400 invalid_pack` |
| GET | `/api/packs/{id}` | — | `Pack` (полное дерево) |
| PATCH | `/api/packs/{id}` | `{"title"?,"author"?,"description"?}` | `PackSummary` |
| DELETE | `/api/packs/{id}` | — | 204; `409 pack_in_use` (загружен в какой-либо игре) |
| GET | `/api/packs/{id}/export` | — | файл `.dub`, `Content-Disposition: attachment; filename="<title>.dub"` |
| POST | `/api/packs/{id}/copy` | `{"title":string}` | `Pack` (201) — разблокированная копия с медиа; работает и для заблокированных паков |
| POST | `/api/packs/{id}/lock` | — | `PackSummary` — блокирует пак (необратимо через API) |
| POST | `/api/packs/{id}/rounds` | `{"name":string, "kind"?: "normal"\|"final"}` | `Round` (201) |
| PATCH | `/api/packs/{id}/rounds/{roundId}` | `{"name"?,"position"?,"kind"?}` | `Round`; `409 final_one_question` при переключении на `final`, если в какой-либо категории больше одного вопроса |
| DELETE | `/api/packs/{id}/rounds/{roundId}` | — | 204 |
| POST | `/api/packs/{id}/rounds/{roundId}/categories` | `{"name":string}` | `Category` (201); `409 too_many_categories` (не более 10 на раунд) |
| PATCH | `/api/packs/{id}/categories/{categoryId}` | `{"name"?,"position"?}` | `Category` |
| DELETE | `/api/packs/{id}/categories/{categoryId}` | — | 204 |
| POST | `/api/packs/{id}/categories/{categoryId}/questions` | `QuestionInput` | `Question` (201); `409 final_one_question` (у финальной темы уже есть вопрос) |
| PATCH | `/api/packs/{id}/questions/{questionId}` | частичный `QuestionInput` + `"position"?` | `Question` |
| DELETE | `/api/packs/{id}/questions/{questionId}` | — | 204 |
| POST | `/api/packs/{id}/media` | multipart, поле `file` (необязательное поле `name` **перед** `file`) | `Media` (201); существующее имя заменяется |
| DELETE | `/api/packs/{id}/media/{name}` | — | 204 |

**Заблокированные паки.** Любой изменяющий вызов из перечисленных выше для заблокированного пака (PATCH, DELETE, раунды,
категории, вопросы, медиа) отвечает `409 pack_locked`. Вместо этого клиенты предлагают «Редактировать
копию»: `POST …/copy` с новым названием, затем открыть копию. Снять блокировку может только оператор
сервера (`svoy-igra unlock-pack <id>`) — это же единственный способ удалить
заблокированный пак. Блокировка хранится в паке
(`meta.locked`) и сохраняется при экспорте/импорте.

Скачивания (`export`) указывают имя файла в `Content-Disposition`; название не в ASCII
передаётся в кодировке RFC 5987 как `filename*=utf-8''…`, поэтому разбирайте и `filename`, и `filename*`.

`position` отсчитывается от 0; его установка перемещает элемент и перенумеровывает соседние элементы
(`round` внутри пака, `category` внутри раунда, `question` внутри категории). Новые
элементы добавляются в конец. Новый вопрос без `value` получает `100 × (index + 1)`.

Файл игры (собственной игры токена):

| Метод | Путь | Тело | Ответ |
|---|---|---|---|
| GET | `/api/game/export` | — | JSON `GameFile`, `Content-Disposition: attachment; filename="game-<PIN>-YYYYMMDD-HHMMSS.json"` |
| POST | `/api/game/import` | JSON `GameFile` в теле **или** multipart-поле `file` | 204; `400 invalid_game_file`; `409 pack_missing` (указанного пака нет в библиотеке) |

Импорт заменяет содержимое игры (пак, игроки, очки, история, настройки) и сохраняет
её идентичность (PIN, название, PIN админа, токены админа/ведущего/экрана). Если файл был сохранён
посреди вопроса, игра продолжается в фазе `board` того же раунда.

### 2.3 Типы

```ts
type Role = 'player' | 'host' | 'admin' | 'screen'
type GameInfo = {
  id: string                 // публичный id, используется watch
  pin: string | null         // 6 цифр; null в GET /api/games и для экранов watch
  title: string
  link: string | null        // ссылка-приглашение, §8; null, как и pin
  phase: Phase
  pack: { id: string; title: string } | null
  players: number            // места
  hostTaken: boolean
  createdAt: number
}
type JoinResult = {
  token: string; role: Role
  playerId?: string; name?: string   // только для игрока
  game: GameInfo
}
type PackSummary = {
  id: string; title: string; author: string; description: string; locked: boolean;
  rounds: number; categories: number; questions: number; mediaCount: number;
  sizeBytes: number; createdAt: number; updatedAt: number;
}
type Pack = Omit<PackSummary, 'rounds'|'categories'|'questions'|'mediaCount'> & {
  rounds: Round[]; media: Media[];
}
type Round    = { id: number; position: number; name: string; kind: 'normal' | 'final'; categories: Category[] }
type Category = { id: number; roundId: number; position: number; name: string; questions: Question[] }
type Question = {
  id: number; categoryId: number; position: number; value: number;
  question: string;        // markdown
  answer: string;          // markdown
  comment: string;         // markdown, заметка ведущего, показывается при показе ответа
  readingSeconds: number | null;   // переопределяет настройку игры для этого вопроса
}
type QuestionInput = { value?: number; question?: string; answer?: string; comment?: string; readingSeconds?: number | null }
type Media = { name: string; mime: string; size: number; url: string }
```

## 3. Markdown вопросов и блоки

Вопрос, ответ и комментарий — это CommonMark. Сырой HTML **не** отображается (экранируйте его).
На медиа ссылаются синтаксисом изображения:

```md
Кто изображён на фото?

![](media:portrait.jpg)

Послушайте отрывок: ![гимн](media:anthem.mp3)
```

- `media:<name>` → файл из папки `media/` пака. URL `http(s)://…` тоже разрешены.
- Вид определяется по расширению файла (без учёта регистра):
  - изображение: `png jpg jpeg gif webp svg bmp`
  - видео: `mp4 webm mov m4v mkv`
  - аудио: `mp3 ogg oga wav m4a aac flac opus`
  - всё остальное → изображение.

Сервер никогда не заставляет клиентов разбирать это: каждый вопрос, который он отправляет во время игры,
уже разбит на **блоки** в порядке следования в документе:

```ts
type Block =
  | { type: 'text'; markdown: string }                    // markdown с удалёнными ссылками на медиа
  | { type: 'image' | 'video' | 'audio'; url: string; alt: string }   // alt присутствует всегда, может быть ''
```

Правило разбиения: каждое вхождение `![alt](src)` становится одним медиаблоком на своём
месте; текст между вхождениями (обрезанный) становится блоком `text`; пустой текст
отбрасывается. `url` для `media:x` — это `/api/packs/{packId}/media/{x}` (с экранированием пути).
Предпросмотр редактора применяет то же правило локально.

Медиа может встречаться и в вопросе, и в ответе, и в комментарии — одни и те же правила
применяются к `blocks`, `answerBlocks` и разбитому комментарию. Каждый видео- и аудиоблок должен
действительно воспроизводиться на каждом клиенте (стандартные элементы управления плеера доступны всегда).

Правила воспроизведения:
- `screen` автоматически воспроизводит видео и аудио (со звуком), когда появляется вопрос, а
  медиа ответа — когда начинается фаза `reveal`.
- `player` показывает изображения и видео (без звука, автовоспроизведение, без повтора, можно включить звук/элементы управления);
  для аудио показывается плашка «🔊 звучит на экране» с кнопкой ручного воспроизведения.
- `host` показывает всё с элементами управления, без автовоспроизведения — включая медиа ответа.
- Предпросмотр редактора паков отображает медиа точно так же, как у ведущего (воспроизводимо, с элементами управления).

Поля markdown в редакторе паков (вопрос, ответ, комментарий) имеют простую панель инструментов: **жирный**,
*курсив*, заголовок, маркированный список, нумерованный список, цитата, ссылка и «Медиа» — выбрать
существующий файл пака или загрузить новый и вставить `![](media:<name>)` в позицию курсора
этого поля.

## 4. WebSocket

`GET /api/ws?token=<token>` — для всех ролей, токен определяет игру и роль.

Коды закрытия: `4001` недействительный или отозванный токен, `4003` игрок удалён, `4004` игра закрыта
(удалена её админом или истекла), `4009` заменено более новым подключением с тем же
токеном игрока или ведущего (одно живое подключение на токен игрока и на токен ведущего; у админов и
экранов их может быть много).

После `leave` клиент забывает токен; для игрока это также означает отказ от места и
очков (клиенты сначала спрашивают подтверждение).

Каждый кадр — текстовое JSON-сообщение: `{"type": string, "data"?: object, "reqId"?: string}`.

### 4.1 Рукопожатие и heartbeat

1. Клиент подключается. Сервер отправляет `welcome`:
   `{"type":"welcome","data":{"role":"player","playerId":"p_…","pin":"123456","serverNow":1761400000000}}`
   (`playerId` — только для игроков; у экрана из публичного списка нет `pin`).
2. Клиент отправляет `hello` с информацией об устройстве (обязательно для игроков, необязательно для остальных):
   ```json
   {"type":"hello","data":{"platform":"web|android|windows|linux|macos|android_tv","model":"Pixel 8",
     "os":"Android 15","appVersion":"1.0.0","userAgent":"…","screen":"1080x2400"}}
   ```
3. Сервер отправляет `state` сразу и после **каждого** изменения.
4. Каждые 2 с сервер отправляет `{"type":"ping","data":{"t":<serverNow>}}`; клиент
   должен сразу ответить `{"type":"pong","data":{"t":<same t>}}`. По нему сервер
   вычисляет время приёма-передачи. Клиент, пропустивший 3 пинга подряд, помечается
   отключённым (`connected:false`), но сохраняет своё место и очки.

Часы: каждый `state` содержит `serverNow`. При получении вычисляйте `offset = serverNow - Date.now()`
и показывайте обратный отсчёт как `deadline - (Date.now() + offset)`.

Клиенты автоматически переподключаются с нарастающей задержкой (1 с, 2 с, 4 с … максимум 10 с).

### 4.2 Сообщения сервер → клиент

| type | data | примечания |
|---|---|---|
| `welcome` | см. выше | |
| `state` | `GameView` | полный снимок, отфильтрованный по роли получателя |
| `ping` | `{t}` | |
| `event` | `GameEvent` | разовый сигнал для звуков/анимаций; никогда не нужен для корректности |
| `error` | `{code, message}` | отклонённая команда; повторяет `reqId`, если он был у команды |

```ts
type Phase =
  | 'lobby' | 'board'
  | 'cat_transfer' | 'auction'            // специальные вопросы до показа вопроса (§4.5)
  | 'question' | 'answering' | 'reveal'
  | 'round_end'
  | 'final_themes' | 'final_bets' | 'final_question' | 'final_judging' | 'final_reveal'  // §4.6
  | 'finished'

type Modifier = 'cat' | 'auction' | 'no_risk' | 'double'

type GameView = {
  serverNow: number
  role: Role
  game: { pin: string | null; title: string; link: string | null; hostTaken: boolean; hostConnected: boolean;
          hostAvatarUrl: string | null }
                                // pin/link: null для экрана, вошедшего из публичного списка
  phase: Phase
  pack: { id: string; title: string } | null
  round: { index: number; name: string; total: number; kind: 'normal' | 'final' } | null
  board: BoardCategory[] | null                        // admin: null
  players: PlayerView[]                                 // в порядке присоединения
  chooserId: string | null      // игрок, который выбирает следующий вопрос
  question: QuestionView | null // фазы cat_transfer/auction/question/answering/reveal и
                                // final_question/final_judging/final_reveal; admin: null
  soloPlayerId: string | null   // cat / auction / no_risk: единственный отвечающий игрок; кнопок нет
  auction: AuctionView | null   // фаза auction
  final: FinalView | null       // фазы final_*
  answeringPlayerId: string | null
  attemptedPlayerIds: string[]  // уже ответили неверно на этот вопрос
  readingStartsAt: number | null // когда открылся вопрос (фазы question/answering)
  readingEndsAt: number | null   // конец общего 10-секундного таймера (фазы question/answering)
  buzzStartsAt: number | null    // начало текущего окна нажатия: = readingEndsAt или
                                 // момент повторного открытия кнопок после неверного ответа
  buzzEndsAt: number | null      // после этого больше никто не может нажать
  typedAnswer: string | null    // только для ведущего: что ввёл отвечающий игрок (необязательно)
  lastResult: { playerId: string; correct: boolean; delta: number } | null  // для текущего вопроса
  settings: Settings | null     // host/admin; у остальных null
  admins: number | null         // только для админа: открытые сокеты админов
  me: MeView | null             // только для игрока
}

type BoardCategory = { id: number; name: string; questions: { id: number; value: number; played: boolean }[] }

type QuestionView = {
  id: number
  categoryName: string
  value: number                  // стоимость ячейки (финал: 0)
  modifier: Modifier | null      // раскрывается при открытии ячейки; на табло никогда не виден
  stake: number                  // что приносит верный ответ: value, ×2 для double/no_risk,
                                 // выигравшая ставка для auction (финал: 0, ставки у каждого игрока свои)
  blocks: Block[]                // [] в cat_transfer и auction (вопрос ещё не показан)
  answerBlocks: Block[] | null   // host: всегда; остальные: только в фазе 'reveal'
  comment: string | null         // та же видимость, что у answerBlocks; сырой markdown — разбейте его
                                 // на блоки по правилу из §3 (media:x → /api/packs/{pack.id}/media/x)
}

type AuctionView = {
  turnPlayerId: string | null    // чей ход (null, когда всё решено)
  highBid: number                // начинается со стоимости ячейки, принадлежит выбирающему
  highBidderId: string
  allIn: boolean                 // старшая ставка — ва-банк
  passedPlayerIds: string[]      // спасовали или не могут перебить (score ≤ highBid и ва-банк невозможен)
}

type FinalView = {
  themes: { id: number; name: string; removed: boolean }[]
  removerId: string | null       // final_themes: чья очередь убирать тему
  answerStartsAt: number | null  // final_question: когда начался ответ (начало полосы таймера)
  answerEndsAt: number | null    // final_question: крайний срок письменных ответов
  participants: {
    playerId: string
    hasBet: boolean
    bet: number | null           // ведущему, самому игроку и всем — после оценки/в final_reveal
    hasAnswer: boolean
    answer: string | null        // ведущему и самому игроку — всегда; всем — после оценки
    correct: boolean | null      // null, пока ведущий не оценил этого игрока
  }[]
}

type PlayerView = {
  id: string; name: string; score: number; connected: boolean
  avatarUrl: string | null       // относительный URL (§2.1, «Аватары»); null = показывать инициалы
  admin?: AdminPlayerInfo        // только в представлении админа
}

type AdminPlayerInfo = {
  device: { platform: string; model: string; os: string; appVersion: string; userAgent: string; screen: string; ip: string }
  rttMs: number | null           // последнее время приёма-передачи
  rttAvgMs: number | null        // среднее по последним 10
  jitterMs: number | null        // среднее абсолютное отклонение по последним 10
  lastSeenAt: number | null
  buzzOffsetMs: number           // заданный админом сдвиг момента появления кнопки этого игрока
  effectiveOffsetMs: number      // buzzOffsetMs минус автокомпенсация (если включена)
  stats: { correct: number; wrong: number; buzzes: number; avgReactionMs: number | null; bestReactionMs: number | null }
}

type MeView = {
  id: string; name: string; score: number
  canSelect: boolean             // фаза board && я выбирающий
  buzzer: 'hidden' | 'waiting' | 'open' | 'answering' | 'used' | 'closed'
  buzzOpensAt: number | null     // время сервера, когда откроется моя кнопка (фаза question)
  canType: boolean               // фаза answering && отвечаю я
  canGiveCat: boolean            // фаза cat_transfer && я выбирающий
  canBid: boolean                // фаза auction && мой ход
  canRemoveTheme: boolean        // фаза final_themes && моя очередь
  finalist: boolean              // я участвую в финале
  canBet: boolean                // фаза final_bets && финалист (можно менять ставку до закрытия ставок)
  canAnswerFinal: boolean        // фаза final_question && финалист && до answerEndsAt
}

type Settings = {
  readingSeconds: number         // по умолчанию 10, диапазон 1..120
  buzzSeconds: number            // по умолчанию 15, диапазон 3..300; окно для нажатия после открытия кнопки
  wrongPenalty: boolean          // по умолчанию false: вычитать стоимость при неверном ответе
  autoLatencyCompensation: boolean // по умолчанию false: открывать каждую кнопку раньше на rttAvg/2
  modifiers: { cat: number; auction: number; noRisk: number; double: number }
                                 // на обычный раунд, по умолчанию по 1, 0..5; расставляются случайно при старте раунда
  finalSeconds: number           // по умолчанию 60, диапазон 10..300: время на письменный ответ в финале
}

type GameEvent =
  | { kind: 'question_opened'; questionId: number }
  | { kind: 'buzz'; playerId: string; reactionMs: number }
  | { kind: 'judged'; playerId: string; correct: boolean; delta: number }
  | { kind: 'timeout' }                      // никто не нажал вовремя
  | { kind: 'score_adjusted'; playerId: string; delta: number }
  | { kind: 'round_started'; index: number }
  | { kind: 'game_finished' }
  | { kind: 'modifier'; questionId: number; modifier: Modifier }   // открылась специальная ячейка
  | { kind: 'cat_given'; fromId: string; toId: string }
  | { kind: 'auction_bid'; playerId: string; amount: number; allIn: boolean }
  | { kind: 'auction_pass'; playerId: string }
  | { kind: 'auction_won'; playerId: string; amount: number }
  | { kind: 'final_theme_removed'; playerId: string | null; themeId: number }
  | { kind: 'final_judged'; playerId: string; correct: boolean; delta: number }
```

Состояния `buzzer` (игрок): `hidden` вне фаз `question`/`answering`; `waiting`
до открытия моей кнопки; `open` я могу нажать; `answering` я выиграл нажатие; `used` я
уже ответил неверно на этот вопрос; `closed` отвечает кто-то другой или
окно закончилось. В соло-вопросе (задан `soloPlayerId`) ни у кого не бывает `open`: у соло-игрока
`waiting` во время чтения, затем `answering`; у всех остальных `closed`.

### 4.3 Команды клиент → сервер

Команды имеют вид `{type, data, reqId?}`. Команда, которую роли отправлять нельзя или которая
недопустима в текущей фазе, получает `error` (`forbidden`, `wrong_phase`,
`not_found`, `invalid`). Успешные команды порождают рассылку нового `state`.

Любая роль: `pong {t}`, `hello {…}`, `leave {}` — отказывается от места и закрывает сокет:
место игрока удаляется, ведущий освобождает слот ведущего, токен админа/экрана
отзывается. После этого клиент забывает токен.

**player**

| type | data | когда разрешено |
|---|---|---|
| `select_question` | `{questionId}` | фаза `board`, я выбирающий, вопрос не сыгран |
| `buzz` | `{}` | фаза `question`, моя кнопка в состоянии `open` |
| `submit_answer` | `{text}` (≤ 200 символов) | фаза `answering`, отвечаю я; необязательно, можно отправлять много раз (побеждает последний) |
| `give_cat` | `{playerId}` | фаза `cat_transfer`, я выбирающий; любой другой игрок |
| `auction_bid` | `{amount}` | фаза `auction`, мой ход: `highBid < amount ≤ my score`, не после ва-банка |
| `auction_all_in` | `{}` | фаза `auction`, мой ход: поставить все свои очки (должно быть > `highBid`) |
| `auction_pass` | `{}` | фаза `auction`, мой ход |
| `final_remove_theme` | `{themeId}` | фаза `final_themes`, моя очередь убирать, тема не убрана |
| `final_bet` | `{amount}` | фаза `final_bets`, финалист: `1 ≤ amount ≤ my score` (побеждает последняя) |
| `final_answer` | `{text}` (≤ 200 символов) | фаза `final_question`, финалист, до `answerEndsAt` (побеждает последний) |

**host**

| type | data | эффект |
|---|---|---|
| `start_game` | `{}` | фаза `lobby` с загруженным паком: фаза → `board`, выбирающий = случайный подключённый игрок (или первый) |
| `select_question` | `{questionId}` | фаза `board`: открыть вопрос от имени выбирающего |
| `set_chooser` | `{playerId}` | любая фаза после старта |
| `judge` | `{correct: boolean}` | фаза `answering` |
| `skip_question` | `{}` | фаза `question`/`answering`: закрыть без очков → `reveal` |
| `continue` | `{}` | фаза `reveal` → `board` или `round_end`, если в раунде не осталось несыгранных вопросов |
| `next_round` | `{}` | фаза `board`/`round_end`/`final_themes` → следующий раунд (`board` или финал) или `finished` после последнего раунда |
| `set_round` | `{index}` | фазы `board`/`round_end`/`final_themes`: перейти к раунду |
| `finish_game` | `{}` | → `finished` |
| `reset_game` | `{keepPlayers: boolean}` | → `lobby`; очки обнуляются, отметки о сыгранных вопросах очищаются; без `keepPlayers` все токены игроков отзываются (`4001`) |
| `update_settings` | `{readingSeconds?, buzzSeconds?, wrongPenalty?, modifiers?, finalSeconds?}` | любая фаза; применяется со следующего вопроса (modifiers — со следующего раунда) |
| `kick_player` | `{playerId}` | удаляет игрока, его сокет закрывается с кодом `4003` |
| `give_cat` | `{playerId}` | как это сделал бы выбирающий |
| `auction_close` | `{}` | фаза `auction`: завершить торги сейчас; выигрывает обладатель старшей ставки |
| `final_remove_theme` | `{themeId}` | фаза `final_themes`, от имени убирающего |
| `final_close_bets` | `{}` | фаза `final_bets`: финалисты без ставки ставят 1 → `final_question` |
| `final_close_answers` | `{}` | фаза `final_question`: остановить ответы сейчас → `final_judging` |
| `final_judge` | `{playerId, correct: boolean}` | фаза `final_judging`: по одному разу на финалиста |

**admin**

| type | data | эффект |
|---|---|---|
| `load_pack` | `{packId}` | фаза `lobby`/`finished`: загружает пак (табло строится из раунда 0); затем ведущий начинает игру |
| `update_settings` | `{readingSeconds?, buzzSeconds?, wrongPenalty?, autoLatencyCompensation?, modifiers?, finalSeconds?}` | любая фаза |
| `update_game` | `{title?, adminPin?}` | переименовать игру / сменить PIN админа (существующие токены админов остаются действительными) |
| `adjust_score` | `{playerId, delta}` | score += delta |
| `set_score` | `{playerId, score}` | score = value |
| `set_buzz_offset` | `{playerId, offsetMs}` | диапазон −5000..10000; положительное = кнопка появляется позже |
| `kick_player` | `{playerId}` | как у ведущего |
| `reset_game` | `{keepPlayers: boolean}` | как у ведущего |
| `close_game` | `{}` | немедленно удаляет игру; каждый сокет закрывается с кодом `4004` |
| `clear_avatar` | `{playerId?}` | удаляет аватар игрока; без `playerId` — аватар ведущего (модерация) |

### 4.4 Ход игры

```
lobby ─start_game→ board ─select_question→ question ─buzz→ answering ─judge(correct)→ reveal
                     ↑                        │  ↑            │                         │
                     │            timeout/skip│  └judge(wrong)┘ (others still eligible) │
                     │                        ↓                                         │
                     └──────────continue───── reveal ←──── judge(wrong), nobody left ───┘
reveal ─continue→ board | round_end ─next_round→ board(next) | finished
```

Фаза `question`:
- `readingEndsAt = openedAt + readingSeconds×1000` (`readingSeconds` из
  вопроса, если задано, иначе из настройки игры).
- Кнопка каждого допущенного игрока открывается в
  `readingEndsAt + effectiveOffsetMs(player)`, с ограничением `≥ openedAt`. Сервер
  в этот момент отправляет этому игроку свежий `state` (`buzzer: 'open'`). Клиенты
  никогда не открывают кнопку по своим часам.
- `buzzStartsAt = readingEndsAt`;
  `buzzEndsAt = buzzStartsAt + max(0, max effectiveOffsetMs) + buzzSeconds×1000`.
  Полосы таймера: чтение = `readingStartsAt → readingEndsAt`, окно нажатия = `buzzStartsAt → buzzEndsAt`.
  Когда оно проходит и никто не нажал → `event timeout` → `reveal`.
- Побеждает **первый `buzz`, дошедший до сервера** → фаза `answering`.
  `reactionMs = arrival − the moment that player's button opened`.

Фаза `answering`:
- `judge correct` → score += value, `chooserId` = этот игрок, → `reveal`.
- `judge wrong` → игрок попадает в `attemptedPlayerIds`, score −= value, если включён
  `wrongPenalty`. Если остались допущенные подключённые игроки → обратно в `question`
  с новым окном: `buzzStartsAt` = сейчас, кнопки сразу открываются снова (+ их
  сдвиги), новый `buzzEndsAt`; `readingStartsAt`/`readingEndsAt` сохраняют свои значения.
  Иначе → `reveal`.

Вопрос становится `played`, когда переходит в `reveal`.

`continue` из `reveal` и `next_round`/`set_round` в раунд с `kind: 'final'`
запускают финал (§4.6) вместо табло.

### 4.5 Специальные вопросы (модификаторы)

При старте обычного раунда сервер помечает модификаторами случайные несыгранные ячейки —
`settings.modifiers` задаёт, сколько каждого вида ставится на раунд (меньше, если раунд маленький; один
модификатор на ячейку). Метки скрыты, пока ячейку не откроют (`event modifier`,
`question.modifier`). Они сохраняются в файле игры.

| Модификатор | Ход | Верно | Неверно |
|---|---|---|---|
| `double` | обычный вопрос с кнопками | +2×value | −2×value, если `wrongPenalty` |
| `no_risk` | соло: отвечает только выбирающий | +2×value | 0 |
| `cat` | `cat_transfer`: выбирающий отдаёт вопрос **другому** игроку (если больше никто не подключён — себе), затем соло | +value | −value (всегда) |
| `auction` | `auction`: торги, затем победитель отвечает соло | +ставка | −ставка (всегда) |

**Соло-ход:** фаза `question` с заданным `soloPlayerId` и без кнопок; после времени чтения
сервер переходит в `answering` с этим игроком. Неверный соло-ответ сразу ведёт
в `reveal`. Выбирающим после верного соло-ответа становится соло-игрок.

**Аукцион:** `highBid` = стоимость ячейки, принадлежит выбирающему; ходы идут по кругу в порядке присоединения,
начиная со следующего за выбирающим, пропуская спасовавших и тех, кто не может перебить (score ≤
`highBid` и ва-банк уже невозможен). В свой ход: повысить (`auction_bid`, любая сумма выше
`highBid` вплоть до своих очков), ва-банк (`auction_all_in`, все очки; после ва-банка
возможен только более высокий ва-банк) или пас. Торги заканчиваются, когда спасовали все, кроме
обладателя старшей ставки, — или когда ведущий отправляет `auction_close`; `event auction_won`, затем
соло-ход со `stake` = выигравшая ставка.

### 4.6 Финальный раунд

Раунд с `kind: 'final'` (§5): каждая категория — тема с одним вопросом.

1. **Финалисты** = игроки со счётом > 0 на момент начала финала. Нет ни одного → `finished`.
2. `final_themes`: финалисты убирают темы по одной за ход — сначала игрок с наименьшим счётом (при равенстве — порядок
   присоединения), затем по кругу — пока не останется одна тема (шаг пропускается, если тема всего одна).
3. `final_bets`: показывается оставшаяся тема (`question` несёт её `categoryName` с
   пустыми `blocks`); каждый финалист тайно ставит `1…score`.
   Когда все финалисты сделали ставки (или `final_close_bets`) → `final_question`.
4. `final_question`: вопрос показывается всем; финалисты вводят ответы до
   `answerEndsAt` = now + `finalSeconds` (или `final_close_answers`) → `final_judging`.
5. `final_judging`: ведущий видит все ответы и ставки и оценивает каждого финалиста:
   верно +ставка, неверно −ставка (`event final_judged`; ставка и ответ этого финалиста становятся
   видны всем). Когда оценены все → `final_reveal`: правильный ответ
   (`answerBlocks`, `comment`) и все результаты для всех. `continue` → `finished`
   (или `round_end`, если дальше есть раунды).

## 5. Файл пака (`.dub`)

`.dub` — это ZIP-архив:

```
pack.sqlite         # вопросы (сжаты deflate)
media/<name>        # изображения, видео, аудио (хранятся без повторного сжатия)
```

Схема `pack.sqlite` (версия формата 1):

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- ключи: format_version ('1'), title, author, description, created_at, updated_at (unix ms),
--        locked ('1' = заблокирован; отсутствует или '0' = редактируемый)
CREATE TABLE rounds (
  id INTEGER PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'normal');   -- 'normal' | 'final'
CREATE TABLE categories (
  id INTEGER PRIMARY KEY,
  round_id INTEGER NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  position INTEGER NOT NULL, name TEXT NOT NULL);
CREATE TABLE questions (
  id INTEGER PRIMARY KEY,
  category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  position INTEGER NOT NULL, value INTEGER NOT NULL,
  question TEXT NOT NULL, answer TEXT NOT NULL, comment TEXT NOT NULL DEFAULT '',
  reading_seconds INTEGER);
```

`rounds.kind` необязателен: в паке без этого столбца каждый раунд читается как `normal` (сервер
добавляет столбец при открытии пака; `format_version` остаётся `1`). В раунде `final`
каждая категория — тема, содержащая **ровно один** вопрос; его `value` и
`reading_seconds` игнорируются (храните 0 / NULL).

Имена медиа: 1–128 символов из `[A-Za-z0-9._-]`, не начинающиеся с `.`. Импорт
отклоняет архивы с другими записями, обходом пути, отсутствующим `pack.sqlite` или
`pack.sqlite` неизвестной версии, а также размером более `MAX_UPLOAD_MB` в распакованном виде.

## 6. Файл игры (JSON)

Содержимое одной игры. Сервер хранит каждую игру в
`DATA_DIR/games/<gameId>.json` (это содержимое плюс идентичность игры: PIN, название,
хеш PIN админа, токены админа/ведущего/экрана, временные метки), записывает его после каждого изменения
(с задержкой ~1 с) и загружает при старте. Админ скачивает и загружает только
содержимое — идентичность и секреты админа никогда не покидают сервер.

```ts
type GameFile = {
  format: 'svoy-igra/game'; version: 1; savedAt: number
  pack: { id: string; title: string } | null
  phase: Phase                       // 'question'/'answering'/'reveal' восстанавливаются как 'board'
  roundIndex: number
  chooserId: string | null
  played: number[]                   // id вопросов
  modifiers: { [questionId: string]: Modifier }   // расставленные для текущего раунда
  final: {                           // null вне финала; восстанавливается как есть (final_question → final_judging)
    removed: number[]; removerId: string | null; finalists: string[]
    bets: { [playerId: string]: number }; answers: { [playerId: string]: string }
    judged: { [playerId: string]: boolean }
  } | null
  settings: Settings
  players: {
    id: string; name: string; token: string; score: number; joinedAt: number
    buzzOffsetMs: number
    device: AdminPlayerInfo['device'] | null
    stats: { correct: number; wrong: number; buzzes: number; totalReactionMs: number; bestReactionMs: number | null }
  }[]
  history: {
    at: number
    kind: 'game_started' | 'question_opened' | 'buzz' | 'judged' | 'timeout' | 'skipped'
        | 'score_adjusted' | 'score_set' | 'round_started' | 'game_finished' | 'player_joined'
        | 'player_kicked' | 'player_left' | 'pack_loaded' | 'modifier' | 'cat_given'
        | 'auction_bid' | 'auction_pass' | 'auction_won' | 'final_started' | 'final_theme_removed'
        | 'final_bet' | 'final_answer' | 'final_judged'
    by: 'player' | 'host' | 'admin' | 'system'
    playerId?: string; questionId?: number; value?: number; delta?: number; correct?: boolean; reactionMs?: number; text?: string
  }[]
}
```

## 7. Обнаружение в LAN

Сервер слушает UDP `DISCOVERY_PORT` (по умолчанию `3051`). Клиент рассылает широковещательно
ASCII-датаграмму `SVOY_IGRA_DISCOVER` на `255.255.255.255:3051`; каждый сервер отвечает
отправителю JSON `{"name":string,"port":number,"version":string}`. Клиент
строит базовый URL из IP-адреса источника ответа и `port`. Приложения и ТВ используют это, чтобы
предлагать найденные серверы; ручной ввод адреса остаётся доступным.

## 8. Ссылки-приглашения и открытие приложения

Ссылка-приглашение игры — `<base>/g/<PIN>`, фиксируется при создании игры. `<base>` — это
`WEB_URL`, если задан; иначе заголовок `Origin` запроса (источник страницы браузера);
иначе `X-Forwarded-Proto`/`X-Forwarded-Host` с откатом к схеме и `Host`,
с которыми пришёл запрос (приложение, обращающееся к серверу напрямую). Прокси перед
бэкендом должны передавать браузерные `Host` / `X-Forwarded-Host` дальше.

- **Веб:** `/g/:pin` — второй шаг входа (выбор роли) с уже заполненным PIN.
  В браузерах на Android страница также показывает «Открыть в приложении» — ссылку
  `intent://join?server=<urlencoded base>&pin=<PIN>#Intent;scheme=svoyigra;package=dev.svoyigra.mobile;S.browser_fallback_url=<urlencoded link>;end`.
- **Приложение** (Android, Windows, Linux, macOS) обрабатывает:
  - `svoyigra://join?server=<base>&pin=<PIN>` (собственная схема, работает для адресов в LAN);
  - `https://<APP_LINK_HOST>/g/<PIN>` и `http://<APP_LINK_HOST>/g/<PIN>` (Android App
    Links, только Android; хост фиксируется при сборке). Базовый адрес сервера — источник ссылки.
  Обе открывают шаг выбора роли для этой игры на этом сервере.
- **Сервер:** `GET /.well-known/assetlinks.json` возвращает заявление Digital Asset Links
  для пакета `ANDROID_PACKAGE` (по умолчанию `dev.svoyigra.mobile`) с отпечатками сертификатов
  из `ANDROID_CERT_SHA256` (через запятую); пусто → `404`, и Android
  вместо этого спрашивает, каким приложением открыть ссылку.
- **ТВ-приложение:** после выбора сервера показывает список текущих игр (`GET /api/games`,
  обновляется каждые несколько секунд) и наблюдает за выбранной (`POST /api/games/{id}/watch`);
  тогда его лобби не показывает ни PIN, ни QR («Ссылку для входа раздаёт администратор»). Вход
  по PIN игры как `screen` остаётся доступным и показывает ссылку, PIN и QR.
