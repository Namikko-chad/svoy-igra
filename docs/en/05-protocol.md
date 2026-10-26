# Protocol

The single source of truth for every client (web, apps, TV) and the backend. A
client that disagrees with this file is wrong; a backend that disagrees with it is
wrong. Change the file and every implementation together.

- Base URL: `http(s)://<server>:<port>`. All REST endpoints live under `/api`.
- All JSON keys are `camelCase`. All times are **Unix milliseconds, UTC** (`number`).
- Media URLs returned by the server are **relative** (`/api/packs/...`). A client
  that is not served from the same origin (apps, TV) prefixes its server base URL.

## 1. Games and roles

One server runs **many games at once**. A game is identified by a 6-digit **game PIN**
and has a share link `<base>/g/<PIN>` (§8). There are no server-wide passwords.

- **Creating** a game needs no PIN: the creator chooses an **admin PIN** (4–8 digits)
  and becomes the game's first admin.
- **Joining** an existing game takes the game PIN, then a role:

| Role | Join with | Limit | What it sees |
|---|---|---|---|
| `player` | game PIN + name | — | board, question (answer only on reveal), scores, own buzzer |
| `host` | game PIN | **one at a time** (`409 host_taken`) | board, question **and answer**, typed answer, scores, settings; runs the game |
| `screen` | game PIN, **or** the game's public id from the list (`watch`) | — | read-only display: board, question, scores, who answers; answer on reveal. A screen from the list never receives the PIN or the share link |
| `admin` | game PIN + admin PIN | — | players (scores, devices, latency, offsets, stats), pack, phase, settings — never the board/question/answer of the running game; manages the shared pack library and this game's file |

The host slot is free when no host token exists, or the holder has no open socket
for 30 s, or the holder sent `leave`. Taking a free slot revokes the previous host
token.

A game with **no open sockets** for `GAME_IDLE_MINUTES` (default 60) is deleted with
its tokens. Sockets open when a game is closed by its admin get close code `4004`; after
deletion its tokens are simply unknown — REST answers `401 unauthorized`, a new socket is
closed with `4001`, `GET /api/games/{pin}` answers `404 game_not_found`. Clients treat
`4001` and `4004` alike: forget the token. Packs are not part of a game and survive it.

The list of live games (`GET /api/games`) is public by design, but it **never contains
the game PIN or the share link**: the PIN is what lets people join as player, host or
admin. From the list one can only *watch* a game as a screen (`POST /api/games/{id}/watch`);
such a screen gets `pin: null` and `link: null` everywhere (join result, `/api/auth/me`,
`welcome`, every `state`), so its lobby cannot show a QR code. A screen that joined with
the PIN sees both.

Every token belongs to exactly one game and one role. Tokens are opaque strings sent
as `Authorization: Bearer <token>` (REST) or `?token=<token>` (WebSocket). Clients store
them per server + game PIN so a reload or app restart rejoins silently.

## 2. REST

Errors: any non-2xx carries `{"error": {"code": "<snake_case>", "message": "<human text>"}}`.
`4xx` = the client can fix it (message is meaningful). `500` = server failure,
message is generic (`internal_error`), details are only in the server log.

### 2.1 Public

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/health` | — | `{"status":"ok"}` |
| GET | `/api/info` | — | `{"name": string, "version": string, "serverNow": number, "webUrl": string \| null}` |
| GET | `/api/games` | — | `GameInfo[]` with `pin: null`, `link: null` — every live game, newest first |
| POST | `/api/games/{id}/watch` | — | `JoinResult` with role `screen` and `pin`/`link` null; `404 game_not_found` |
| POST | `/api/games` | `{"adminPin": string, "title"?: string}` | `JoinResult` (201) with role `admin`; `400 invalid_admin_pin` (not 4–8 digits), `400 invalid_title` (> 60 chars), `503 too_many_games` |
| GET | `/api/games/{pin}` | — | `GameInfo`; `404 game_not_found` |
| POST | `/api/games/{pin}/join` | `{"role": Role, "name"?: string, "adminPin"?: string}` | `JoinResult`; `404 game_not_found`, `400 invalid_role`, `400 invalid_name` (player: empty / > 32 chars), `409 name_taken`, `409 host_taken`, `401 invalid_admin_pin` |
| GET | `/api/auth/me` | (Bearer) | `JoinResult` without `token`; `401 unauthorized` (unknown token or deleted game) |
| GET | `/api/packs/{packId}/media/{name}` | — | the file (supports HTTP `Range`), `404 not_found` |
| GET | `/.well-known/assetlinks.json` | — | Android App Links statement (§8); `404` when not configured |
| POST | `/api/avatar` | (Bearer player or host token) multipart field `file` | `{"avatarUrl": string}`; `403 forbidden` for other roles, `400 invalid_image` (not PNG/JPEG/WebP/GIF), `413 too_large` (> 2 MiB) |
| DELETE | `/api/avatar` | (Bearer player or host token) | 204 |
| GET | `/api/games/{gameId}/avatars/{file}` | — | the image; `404 not_found` |

**Avatars.** A player sets their own avatar, the host sets the host avatar. Clients crop
the picture to a square and scale it to at most 512×512 before uploading. Each upload gets
a new random file name (the URL changes, so caches never show a stale picture) and
replaces the previous one. Avatar URLs contain the game's public id, never its PIN. They
live as long as the game (deleted with it).

`webUrl` is the public address of the web client (env `WEB_URL`); `null` means the web
client is served from the server's own address.

Player names are unique case-insensitively within a game. A client that has a token
does **not** join again — it reconnects the WebSocket with the token. A wrong admin PIN
costs 500 ms.

### 2.2 Admin only

Bearer **admin token of any game**; otherwise `401 unauthorized` / `403 forbidden`.
The pack library is shared by all games.

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/packs` | — | `PackSummary[]` (newest `updatedAt` first) |
| POST | `/api/packs` | `{"title":string}` | `Pack` (201) |
| POST | `/api/packs/import` | multipart, field `file` = `.dub` | `PackSummary` (201); `400 invalid_pack` |
| GET | `/api/packs/{id}` | — | `Pack` (full tree) |
| PATCH | `/api/packs/{id}` | `{"title"?,"author"?,"description"?}` | `PackSummary` |
| DELETE | `/api/packs/{id}` | — | 204; `409 pack_in_use` (loaded in any game) |
| GET | `/api/packs/{id}/export` | — | `.dub` file, `Content-Disposition: attachment; filename="<title>.dub"` |
| POST | `/api/packs/{id}/copy` | `{"title":string}` | `Pack` (201) — an unlocked copy with media; works on locked packs |
| POST | `/api/packs/{id}/lock` | — | `PackSummary` — locks the pack (irreversible through the API) |
| POST | `/api/packs/{id}/rounds` | `{"name":string, "kind"?: "normal"\|"final"}` | `Round` (201) |
| PATCH | `/api/packs/{id}/rounds/{roundId}` | `{"name"?,"position"?,"kind"?}` | `Round`; `409 final_one_question` when switching to `final` while a category has more than one question |
| DELETE | `/api/packs/{id}/rounds/{roundId}` | — | 204 |
| POST | `/api/packs/{id}/rounds/{roundId}/categories` | `{"name":string}` | `Category` (201); `409 too_many_categories` (max 10 per round) |
| PATCH | `/api/packs/{id}/categories/{categoryId}` | `{"name"?,"position"?}` | `Category` |
| DELETE | `/api/packs/{id}/categories/{categoryId}` | — | 204 |
| POST | `/api/packs/{id}/categories/{categoryId}/questions` | `QuestionInput` | `Question` (201); `409 final_one_question` (a final theme already has its question) |
| PATCH | `/api/packs/{id}/questions/{questionId}` | partial `QuestionInput` + `"position"?` | `Question` |
| DELETE | `/api/packs/{id}/questions/{questionId}` | — | 204 |
| POST | `/api/packs/{id}/media` | multipart, field `file` (optional field `name` **before** `file`) | `Media` (201); an existing name is replaced |
| DELETE | `/api/packs/{id}/media/{name}` | — | 204 |

**Locked packs.** Every mutating call above on a locked pack (PATCH, DELETE, rounds,
categories, questions, media) answers `409 pack_locked`. Clients offer «Редактировать
копию» instead: `POST …/copy` with a new title, then open the copy. Only the server
operator can unlock (`svoy-igra unlock-pack <id>`) — that is also the only way to delete
a locked pack. The lock is stored in the pack
(`meta.locked`) and survives export/import.

Downloads (`export`) name the file in `Content-Disposition`; a non-ASCII title is
sent RFC 5987-encoded as `filename*=utf-8''…`, so parse both `filename` and `filename*`.

`position` is 0-based; setting it moves the item and renumbers its siblings
(`round` within pack, `category` within round, `question` within category). New
items are appended. A new question without `value` gets `100 × (index + 1)`.

Game file (the token's own game):

| Method | Path | Body | Response |
|---|---|---|---|
| GET | `/api/game/export` | — | `GameFile` JSON, `Content-Disposition: attachment; filename="game-<PIN>-YYYYMMDD-HHMMSS.json"` |
| POST | `/api/game/import` | `GameFile` JSON body **or** multipart field `file` | 204; `400 invalid_game_file`; `409 pack_missing` (the referenced pack is not in the library) |

Import replaces the game's content (pack, players, scores, history, settings) and keeps
its identity (PIN, title, admin PIN, admin/host/screen tokens). If the file was saved
mid-question, the game resumes on the `board` phase of the same round.

### 2.3 Types

```ts
type Role = 'player' | 'host' | 'admin' | 'screen'
type GameInfo = {
  id: string                 // public id, used by watch
  pin: string | null         // 6 digits; null in GET /api/games and for watch screens
  title: string
  link: string | null        // share link, §8; null like pin
  phase: Phase
  pack: { id: string; title: string } | null
  players: number            // seats
  hostTaken: boolean
  createdAt: number
}
type JoinResult = {
  token: string; role: Role
  playerId?: string; name?: string   // player only
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
  comment: string;         // markdown, host note shown on reveal
  readingSeconds: number | null;   // overrides the game setting for this question
}
type QuestionInput = { value?: number; question?: string; answer?: string; comment?: string; readingSeconds?: number | null }
type Media = { name: string; mime: string; size: number; url: string }
```

## 3. Question markdown and blocks

Question, answer and comment are CommonMark. Raw HTML is **not** rendered (escape it).
Media is referenced with image syntax:

```md
Кто изображён на фото?

![](media:portrait.jpg)

Послушайте отрывок: ![гимн](media:anthem.mp3)
```

- `media:<name>` → a file from the pack's `media/` folder. `http(s)://…` URLs are allowed too.
- The kind is chosen by file extension (case-insensitive):
  - image: `png jpg jpeg gif webp svg bmp`
  - video: `mp4 webm mov m4v mkv`
  - audio: `mp3 ogg oga wav m4a aac flac opus`
  - anything else → image.

The server never makes clients parse this: every question it sends during a game is
already split into **blocks**, in document order:

```ts
type Block =
  | { type: 'text'; markdown: string }                    // markdown with media references removed
  | { type: 'image' | 'video' | 'audio'; url: string; alt: string }   // alt is always present, may be ''
```

Splitting rule: each `![alt](src)` occurrence becomes one media block at its
position; the text between occurrences (trimmed) becomes a `text` block; empty text
is dropped. `url` for `media:x` is `/api/packs/{packId}/media/{x}` (path-escaped).
The editor preview applies the same rule locally.

Media may appear in the question, the answer and the comment alike — the same rules
apply to `blocks`, `answerBlocks` and the split comment. Every video and audio block must
actually play on every client (native player controls are always available).

Playback rules:
- `screen` autoplays video and audio (with sound) when the question appears, and the
  answer's media when the `reveal` phase starts.
- `player` shows images and video (muted, autoplay, loop off, unmute/controls available);
  audio shows an “🔊 звучит на экране” chip with a manual play button.
- `host` shows everything with controls, no autoplay — the answer's media included.
- The pack editor preview renders media exactly like the host (playable, with controls).

Pack editor markdown fields (question, answer, comment) have a basic toolbar: **bold**,
*italic*, heading, bulleted list, numbered list, quote, link, and «Медиа» — pick an
existing pack file or upload a new one and insert `![](media:<name>)` at the cursor of
that field.

## 4. WebSocket

`GET /api/ws?token=<token>` — every role, the token decides game and role.

Close codes: `4001` invalid or revoked token, `4003` kicked, `4004` game closed
(deleted by its admin or expired), `4009` replaced by a newer connection with the same
player or host token (one live socket per player and per host token; admins and
screens may have many).

After `leave` the client forgets the token; for a player this also gives up the seat and
the score (clients confirm first).

Every frame is a JSON text message: `{"type": string, "data"?: object, "reqId"?: string}`.

### 4.1 Handshake and heartbeat

1. Client connects. Server sends `welcome`:
   `{"type":"welcome","data":{"role":"player","playerId":"p_…","pin":"123456","serverNow":1761400000000}}`
   (`playerId` only for players; no `pin` for a screen from the public list).
2. Client sends `hello` with its device info (required for players, optional for others):
   ```json
   {"type":"hello","data":{"platform":"web|android|windows|linux|macos|android_tv","model":"Pixel 8",
     "os":"Android 15","appVersion":"1.0.0","userAgent":"…","screen":"1080x2400"}}
   ```
3. Server sends `state` immediately and after **every** change.
4. Every 2 s the server sends `{"type":"ping","data":{"t":<serverNow>}}`; the client
   must answer at once with `{"type":"pong","data":{"t":<same t>}}`. The server
   derives round-trip time from it. A client that misses 3 pings in a row is marked
   disconnected (`connected:false`), but it keeps its seat and score.

Clock: every `state` carries `serverNow`. Compute `offset = serverNow - Date.now()`
on receipt and show countdowns as `deadline - (Date.now() + offset)`.

Clients reconnect automatically with backoff (1 s, 2 s, 4 s … max 10 s).

### 4.2 Server → client messages

| type | data | notes |
|---|---|---|
| `welcome` | see above | |
| `state` | `GameView` | full snapshot, filtered for the receiver's role |
| `ping` | `{t}` | |
| `event` | `GameEvent` | one-shot cue for sounds/animations; never needed for correctness |
| `error` | `{code, message}` | a rejected command; echoes `reqId` when the command had one |

```ts
type Phase =
  | 'lobby' | 'board'
  | 'cat_transfer' | 'auction'            // special questions before the question is shown (§4.5)
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
                                // pin/link: null for a screen that joined from the public list
  phase: Phase
  pack: { id: string; title: string } | null
  round: { index: number; name: string; total: number; kind: 'normal' | 'final' } | null
  board: BoardCategory[] | null                        // admin: null
  players: PlayerView[]                                 // ordered by join time
  chooserId: string | null      // the player who selects the next question
  question: QuestionView | null // phases cat_transfer/auction/question/answering/reveal and
                                // final_question/final_judging/final_reveal; admin: null
  soloPlayerId: string | null   // cat / auction / no_risk: the only player who answers; no buttons
  auction: AuctionView | null   // phase auction
  final: FinalView | null       // phases final_*
  answeringPlayerId: string | null
  attemptedPlayerIds: string[]  // already answered wrong on this question
  readingStartsAt: number | null // when the question opened (phases question/answering)
  readingEndsAt: number | null   // end of the common 10 s timer (phases question/answering)
  buzzStartsAt: number | null    // base of the current buzz window: = readingEndsAt, or the
                                 // moment buttons reopened after a wrong answer
  buzzEndsAt: number | null      // after this, nobody may buzz any more
  typedAnswer: string | null    // host only: what the answering player typed (optional)
  lastResult: { playerId: string; correct: boolean; delta: number } | null  // of the current question
  settings: Settings | null     // host/admin; others null
  admins: number | null         // admin only: open admin sockets
  me: MeView | null             // player only
}

type BoardCategory = { id: number; name: string; questions: { id: number; value: number; played: boolean }[] }

type QuestionView = {
  id: number
  categoryName: string
  value: number                  // the cell's value (final: 0)
  modifier: Modifier | null      // revealed when the cell opens; never visible on the board
  stake: number                  // what a correct answer earns: value, ×2 for double/no_risk,
                                 // the winning bid for auction (final: 0, bets are per player)
  blocks: Block[]                // [] in cat_transfer and auction (the question is not shown yet)
  answerBlocks: Block[] | null   // host: always; others: only in phase 'reveal'
  comment: string | null         // same visibility as answerBlocks; raw markdown — split it
                                 // into blocks with the §3 rule (media:x → /api/packs/{pack.id}/media/x)
}

type AuctionView = {
  turnPlayerId: string | null    // whose move it is (null once decided)
  highBid: number                // starts at the cell value, held by the chooser
  highBidderId: string
  allIn: boolean                 // the high bid is a ва-банк
  passedPlayerIds: string[]      // passed, or cannot outbid (score ≤ highBid and no ва-банк possible)
}

type FinalView = {
  themes: { id: number; name: string; removed: boolean }[]
  removerId: string | null       // final_themes: whose turn to remove a theme
  answerStartsAt: number | null  // final_question: when answering began (timer bar start)
  answerEndsAt: number | null    // final_question: deadline for written answers
  participants: {
    playerId: string
    hasBet: boolean
    bet: number | null           // host, the player himself, and everyone once judged/final_reveal
    hasAnswer: boolean
    answer: string | null        // host and the player himself always; everyone once judged
    correct: boolean | null      // null until the host judged this player
  }[]
}

type PlayerView = {
  id: string; name: string; score: number; connected: boolean
  avatarUrl: string | null       // relative URL (§2.1 Avatars); null = show initials
  admin?: AdminPlayerInfo        // only in the admin's view
}

type AdminPlayerInfo = {
  device: { platform: string; model: string; os: string; appVersion: string; userAgent: string; screen: string; ip: string }
  rttMs: number | null           // last round-trip
  rttAvgMs: number | null        // average of the last 10
  jitterMs: number | null        // mean absolute deviation of the last 10
  lastSeenAt: number | null
  buzzOffsetMs: number           // admin-set shift of when this player's button appears
  effectiveOffsetMs: number      // buzzOffsetMs minus auto compensation (if enabled)
  stats: { correct: number; wrong: number; buzzes: number; avgReactionMs: number | null; bestReactionMs: number | null }
}

type MeView = {
  id: string; name: string; score: number
  canSelect: boolean             // phase board && I am the chooser
  buzzer: 'hidden' | 'waiting' | 'open' | 'answering' | 'used' | 'closed'
  buzzOpensAt: number | null     // server time my button opens (phase question)
  canType: boolean               // phase answering && I am answering
  canGiveCat: boolean            // phase cat_transfer && I am the chooser
  canBid: boolean                // phase auction && my turn
  canRemoveTheme: boolean        // phase final_themes && my turn
  finalist: boolean              // I take part in the final
  canBet: boolean                // phase final_bets && finalist (may re-bet until bets close)
  canAnswerFinal: boolean        // phase final_question && finalist && before answerEndsAt
}

type Settings = {
  readingSeconds: number         // default 10, range 1..120
  buzzSeconds: number            // default 15, range 3..300; window to buzz after the button opens
  wrongPenalty: boolean          // default false: subtract value on a wrong answer
  autoLatencyCompensation: boolean // default false: open each button earlier by rttAvg/2
  modifiers: { cat: number; auction: number; noRisk: number; double: number }
                                 // per normal round, default 1 each, 0..5; placed at random when a round starts
  finalSeconds: number           // default 60, range 10..300: time to write the final answer
}

type GameEvent =
  | { kind: 'question_opened'; questionId: number }
  | { kind: 'buzz'; playerId: string; reactionMs: number }
  | { kind: 'judged'; playerId: string; correct: boolean; delta: number }
  | { kind: 'timeout' }                      // nobody buzzed in time
  | { kind: 'score_adjusted'; playerId: string; delta: number }
  | { kind: 'round_started'; index: number }
  | { kind: 'game_finished' }
  | { kind: 'modifier'; questionId: number; modifier: Modifier }   // a special cell opened
  | { kind: 'cat_given'; fromId: string; toId: string }
  | { kind: 'auction_bid'; playerId: string; amount: number; allIn: boolean }
  | { kind: 'auction_pass'; playerId: string }
  | { kind: 'auction_won'; playerId: string; amount: number }
  | { kind: 'final_theme_removed'; playerId: string | null; themeId: number }
  | { kind: 'final_judged'; playerId: string; correct: boolean; delta: number }
```

`buzzer` states (player): `hidden` outside phase `question`/`answering`; `waiting`
before my button opens; `open` I can press; `answering` I won the buzz; `used` I
already answered wrong on this question; `closed` someone else is answering or the
window is over. With a solo question (`soloPlayerId` set) nobody gets `open`: the solo
player is `waiting` during the reading time, then `answering`; everyone else `closed`.

### 4.3 Client → server commands

Commands are `{type, data, reqId?}`. A command the role may not send, or that is
invalid in the current phase, gets `error` (`forbidden`, `wrong_phase`,
`not_found`, `invalid`). Successful commands produce a new `state` broadcast.

Any role: `pong {t}`, `hello {…}`, `leave {}` — gives the seat up and closes the socket:
a player's seat is removed, a host frees the host slot, an admin/screen token is
revoked. The client then forgets the token.

**player**

| type | data | allowed when |
|---|---|---|
| `select_question` | `{questionId}` | phase `board`, I am the chooser, question not played |
| `buzz` | `{}` | phase `question`, my buzzer is `open` |
| `submit_answer` | `{text}` (≤ 200 chars) | phase `answering`, I am answering; optional, may be sent many times (last wins) |
| `give_cat` | `{playerId}` | phase `cat_transfer`, I am the chooser; any other player |
| `auction_bid` | `{amount}` | phase `auction`, my turn: `highBid < amount ≤ my score`, not after a ва-банк |
| `auction_all_in` | `{}` | phase `auction`, my turn: bid my whole score (must be > `highBid`) |
| `auction_pass` | `{}` | phase `auction`, my turn |
| `final_remove_theme` | `{themeId}` | phase `final_themes`, I am the remover, theme not removed |
| `final_bet` | `{amount}` | phase `final_bets`, finalist: `1 ≤ amount ≤ my score` (last wins) |
| `final_answer` | `{text}` (≤ 200 chars) | phase `final_question`, finalist, before `answerEndsAt` (last wins) |

**host**

| type | data | effect |
|---|---|---|
| `start_game` | `{}` | phase `lobby` with a pack loaded: phase → `board`, chooser = random connected player (or first) |
| `select_question` | `{questionId}` | phase `board`: open a question on behalf of the chooser |
| `set_chooser` | `{playerId}` | any phase after start |
| `judge` | `{correct: boolean}` | phase `answering` |
| `skip_question` | `{}` | phase `question`/`answering`: close without points → `reveal` |
| `continue` | `{}` | phase `reveal` → `board`, or `round_end` when the round has no unplayed questions |
| `next_round` | `{}` | phase `board`/`round_end`/`final_themes` → next round (`board` or the final), or `finished` after the last round |
| `set_round` | `{index}` | phases `board`/`round_end`/`final_themes`: jump to a round |
| `finish_game` | `{}` | → `finished` |
| `reset_game` | `{keepPlayers: boolean}` | → `lobby`; scores zeroed, played cleared; without `keepPlayers` all player tokens are revoked (`4001`) |
| `update_settings` | `{readingSeconds?, buzzSeconds?, wrongPenalty?, modifiers?, finalSeconds?}` | any phase; applies from the next question (modifiers: from the next round) |
| `kick_player` | `{playerId}` | removes the player, their socket is closed with `4003` |
| `give_cat` | `{playerId}` | as the chooser would |
| `auction_close` | `{}` | phase `auction`: end the bidding now; the high bidder wins |
| `final_remove_theme` | `{themeId}` | phase `final_themes`, on behalf of the remover |
| `final_close_bets` | `{}` | phase `final_bets`: finalists without a bet bet 1 → `final_question` |
| `final_close_answers` | `{}` | phase `final_question`: stop answers now → `final_judging` |
| `final_judge` | `{playerId, correct: boolean}` | phase `final_judging`: once per finalist |

**admin**

| type | data | effect |
|---|---|---|
| `load_pack` | `{packId}` | phase `lobby`/`finished`: loads the pack (board built from round 0); the host then starts |
| `update_settings` | `{readingSeconds?, buzzSeconds?, wrongPenalty?, autoLatencyCompensation?, modifiers?, finalSeconds?}` | any phase |
| `update_game` | `{title?, adminPin?}` | rename the game / change the admin PIN (existing admin tokens stay valid) |
| `adjust_score` | `{playerId, delta}` | score += delta |
| `set_score` | `{playerId, score}` | score = value |
| `set_buzz_offset` | `{playerId, offsetMs}` | range −5000..10000; positive = button appears later |
| `kick_player` | `{playerId}` | as host |
| `reset_game` | `{keepPlayers: boolean}` | as host |
| `close_game` | `{}` | deletes the game now; every socket is closed with `4004` |
| `clear_avatar` | `{playerId?}` | removes a player's avatar; without `playerId` the host's (moderation) |

### 4.4 Game flow

```
lobby ─start_game→ board ─select_question→ question ─buzz→ answering ─judge(correct)→ reveal
                     ↑                        │  ↑            │                         │
                     │            timeout/skip│  └judge(wrong)┘ (others still eligible) │
                     │                        ↓                                         │
                     └──────────continue───── reveal ←──── judge(wrong), nobody left ───┘
reveal ─continue→ board | round_end ─next_round→ board(next) | finished
```

Phase `question`:
- `readingEndsAt = openedAt + readingSeconds×1000` (`readingSeconds` from the
  question if set, otherwise the game setting).
- Each eligible player's button opens at
  `readingEndsAt + effectiveOffsetMs(player)`, clamped to `≥ openedAt`. The server
  pushes a fresh `state` to that player at that moment (`buzzer: 'open'`). Clients
  never open the button on their own clock.
- `buzzStartsAt = readingEndsAt`;
  `buzzEndsAt = buzzStartsAt + max(0, max effectiveOffsetMs) + buzzSeconds×1000`.
  Timer bars: reading = `readingStartsAt → readingEndsAt`, buzz window = `buzzStartsAt → buzzEndsAt`.
  When it passes with nobody buzzing → `event timeout` → `reveal`.
- The **first `buzz` to arrive at the server** wins → phase `answering`.
  `reactionMs = arrival − the moment that player's button opened`.

Phase `answering`:
- `judge correct` → score += value, `chooserId` = that player, → `reveal`.
- `judge wrong` → the player goes into `attemptedPlayerIds`, score −= value if
  `wrongPenalty`. If eligible connected players remain → back to `question`
  with a fresh window: `buzzStartsAt` = now, buttons reopen immediately (+ their
  offsets), new `buzzEndsAt`; `readingStartsAt`/`readingEndsAt` keep their values.
  Otherwise → `reveal`.

The question becomes `played` when it enters `reveal`.

`continue` from `reveal` and `next_round`/`set_round` into a round with `kind: 'final'`
start the final (§4.6) instead of a board.

### 4.5 Special questions (modifiers)

When a normal round starts, the server marks random unplayed cells with modifiers —
`settings.modifiers` gives how many of each per round (fewer if the round is small; one
modifier per cell). The marks are secret until a cell is opened (`event modifier`,
`question.modifier`). They are saved in the game file.

| Modifier | Flow | Correct | Wrong |
|---|---|---|---|
| `double` | normal question with buttons | +2×value | −2×value if `wrongPenalty` |
| `no_risk` | solo: only the chooser answers | +2×value | 0 |
| `cat` | `cat_transfer`: the chooser gives the question to **another** player (if nobody else is connected — to himself), then solo | +value | −value (always) |
| `auction` | `auction`: bidding, then the winner answers solo | +bid | −bid (always) |

**Solo flow:** phase `question` with `soloPlayerId` set and no buttons; after the reading
time the server moves to `answering` with that player. A wrong solo answer goes straight
to `reveal`. The chooser after a correct solo answer is the solo player.

**Auction:** `highBid` = cell value, held by the chooser; turns go round in join order
starting after the chooser, skipping players who passed or cannot outbid (score ≤
`highBid` and no ва-банк left). On a turn: raise (`auction_bid`, any amount above
`highBid` up to the score), ва-банк (`auction_all_in`, the whole score; after a ва-банк
only a higher ва-банк is possible) or pass. The bidding ends when everyone except the
high bidder has passed — or the host sends `auction_close`; `event auction_won`, then the
solo flow with `stake` = the winning bid.

### 4.6 Final round

A round with `kind: 'final'` (§5): each category is a theme with one question.

1. **Finalists** = players with score > 0 when the final starts. None → `finished`.
2. `final_themes`: finalists remove themes one per turn — lowest score first (ties: join
   order), then cycling — until one theme is left (skipped when there is only one).
3. `final_bets`: the remaining theme is shown (`question` carries its `categoryName`, with
   empty `blocks`); each finalist secretly bets `1…score`.
   When all finalists have bet (or `final_close_bets`) → `final_question`.
4. `final_question`: the question is shown to everyone; finalists type answers until
   `answerEndsAt` = now + `finalSeconds` (or `final_close_answers`) → `final_judging`.
5. `final_judging`: the host sees every answer and bet and judges each finalist:
   correct +bet, wrong −bet (`event final_judged`; that finalist's bet and answer become
   visible to all). When all are judged → `final_reveal`: the correct answer
   (`answerBlocks`, `comment`) and all results for everyone. `continue` → `finished`
   (or `round_end` if more rounds follow).

## 5. Pack file (`.dub`)

A `.dub` is a ZIP archive:

```
pack.sqlite         # questions (deflated)
media/<name>        # images, video, audio (stored, not recompressed)
```

`pack.sqlite` schema (format version 1):

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
-- keys: format_version ('1'), title, author, description, created_at, updated_at (unix ms),
--       locked ('1' = locked; absent or '0' = editable)
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

`rounds.kind` is optional: a pack without the column reads every round as `normal` (the
server adds the column when it opens the pack; `format_version` stays `1`). In a `final`
round every category is a theme holding **exactly one** question; its `value` and
`reading_seconds` are ignored (store 0 / NULL).

Media names: 1–128 chars of `[A-Za-z0-9._-]`, not starting with `.`. Import
rejects archives with other entries, path traversal, a missing or unknown-version
`pack.sqlite`, or more than `MAX_UPLOAD_MB` uncompressed.

## 6. Game file (JSON)

The content of one game. The server keeps each game in
`DATA_DIR/games/<gameId>.json` (this content plus the game's identity: PIN, title,
admin PIN hash, admin/host/screen tokens, timestamps), written after every change
(debounced ~1 s) and loaded at start-up. The admin downloads and uploads the content
only — identity and admin secrets never leave the server.

```ts
type GameFile = {
  format: 'svoy-igra/game'; version: 1; savedAt: number
  pack: { id: string; title: string } | null
  phase: Phase                       // 'question'/'answering'/'reveal' are restored as 'board'
  roundIndex: number
  chooserId: string | null
  played: number[]                   // question ids
  modifiers: { [questionId: string]: Modifier }   // placed for the current round
  final: {                           // null outside the final; restored as is (final_question → final_judging)
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

## 7. LAN discovery

The server listens on UDP `DISCOVERY_PORT` (default `3051`). A client broadcasts the
ASCII datagram `SVOY_IGRA_DISCOVER` to `255.255.255.255:3051`; each server answers
the sender with JSON `{"name":string,"port":number,"version":string}`. The client
builds the base URL from the reply's source IP and `port`. The apps and TV use this to
offer found servers; manual address entry stays available.

## 8. Share links and opening the app

The share link of a game is `<base>/g/<PIN>`, fixed when the game is created. `<base>` is
`WEB_URL` when set; otherwise the request's `Origin` header (a browser's page origin);
otherwise `X-Forwarded-Proto`/`X-Forwarded-Host`, falling back to the scheme and `Host`
the request arrived with (an app talking to the server directly). Proxies in front of the
backend must pass the browser's `Host` / `X-Forwarded-Host` through.

- **Web:** `/g/:pin` is the second step of joining (role choice) with the PIN filled in.
  On Android browsers the page also shows «Открыть в приложении», an
  `intent://join?server=<urlencoded base>&pin=<PIN>#Intent;scheme=svoyigra;package=dev.svoyigra.mobile;S.browser_fallback_url=<urlencoded link>;end`
  link.
- **App** (Android, Windows, Linux, macOS) handles:
  - `svoyigra://join?server=<base>&pin=<PIN>` (custom scheme, works for LAN addresses);
  - `https://<APP_LINK_HOST>/g/<PIN>` and `http://<APP_LINK_HOST>/g/<PIN>` (Android App
    Links, Android only; the host is fixed at build time). The server base is the link's origin.
  Both open the role step for that game on that server.
- **Server:** `GET /.well-known/assetlinks.json` returns the Digital Asset Links statement
  for package `ANDROID_PACKAGE` (default `dev.svoyigra.mobile`) with the certificate
  fingerprints in `ANDROID_CERT_SHA256` (comma-separated); empty → `404`, and Android
  falls back to asking which app should open the link.
- **TV app:** after choosing the server it lists the live games (`GET /api/games`,
  refreshed every few seconds) and watches the chosen one (`POST /api/games/{id}/watch`);
  its lobby then shows no PIN or QR («Ссылку для входа раздаёт администратор»). Joining
  with the game PIN as `screen` stays available and shows the link, PIN and QR.
