# Frontend rules

## Stack
Vue 3 (`<script setup lang="ts">`), Vite, TypeScript (strict), vue-router, Pinia, markdown-it
(`html: false`, `linkify`). Vitest for unit tests, `vue-tsc` for typechecking. No UI framework —
the design system is plain CSS custom properties (`src/styles/tokens.css`) plus our own components.

## Commands (pnpm only — never npm/yarn)
- `pnpm install` · `pnpm dev` (port `FRONTEND_PORT`, default 3000, host 0.0.0.0; `/api` incl. WS → `BACKEND_URL`, default http://localhost:3050)
- `pnpm build` (typecheck + `dist/`) · `pnpm typecheck` · `pnpm test`

## Layout
- `src/types/protocol.ts` — wire types mirrored from the protocol doc.
- `src/api/` — REST: `http.ts` (fetch wrapper, Bearer, `{error:{code,message}}` → `ApiError`),
  `transfer.ts` (XHR uploads with progress, authenticated blob downloads), `index.ts`
  (`gamesApi` create/get/join, `authApi.me`, `packsApi` incl. copy/lock, `gameApi` file import/export).
- `src/ws/client.ts` — `GameSocket` (token-only): hello/ping-pong, reconnect backoff 1…10 s,
  reactive `state` / `connected` / `clockOffset` / `fatalCode` (4001/4003/4004/4009 stop
  reconnecting), `onEvent`, `leave()`.
- `src/composables/` — `useRoleSocket(pin, role)` (stored token → socket; maps close codes;
  `leave()`), `useGameSocket`, `useAdminToken(pin)` (admin REST pages), `useNow`, `useQuestionTimer`.
- `src/stores/` — `session` (tokens per server + game PIN + role in localStorage, key
  `svoy.token|<origin>|<pin>|<role>`, see `utils/storage.ts`), `toast`.
- `src/utils/` — `blocks.ts` (the server's markdown → blocks splitter, same regex as the backend —
  keep it identical to protocol §3), `mdEdit.ts` (pure toolbar edits: wrap/unwrap, line prefixes,
  link, block insert — unit-tested), `special.ts` (special questions + final view logic: labels,
  wrong-answer delta, cat recipients, auction limits, final rows, settings clamps — unit-tested),
  `phase.ts` (labels, `isSpecialPhase`), `pin.ts` (PIN rules, Android intent link §8), `roles.ts`,
  markdown, time, latency, device, media names, sound.
- `src/components/` — shared UI (`GameShell` top bar + «Выйти» + close-code screens, board,
  buzzer, timer, scoreboard, question blocks, `ShareCard` PIN/link/QR, dialogs); `admin/`,
  `editor/` hold role-specific pieces (`MarkdownField` = textarea + formatting toolbar + «Медиа»
  picker/upload inserting `![](media:<name>)` at that field's cursor).
- Special questions and the final: `components/special/SpecialStage.vue` renders `cat_transfer`,
  `auction` and every `final_*` phase for player / host / screen (props `role`, `state`, server
  `now`; commands go out via its `cmd` event). `QuestionHeader` shows the modifier badge and stake,
  `ModifierSplash` + `useModifierSplash` show the big Russian label when a special cell opens.
  Solo questions (`soloPlayerId`) have no buzzer. `SettingsFields` (host + admin) edits timers,
  penalty, per-round modifier counts and `finalSeconds`. The pack editor toggles a round's
  `kind` («🏆 Финал»): themes hold exactly one question, no value / reading time.
- Board (`GameBoard.vue`): one row per category, name column fixed on the left, values left → right.
  Each cell is a size container; the value's font is `min(45cqh, (100cqw − padding) / 3.4)` so 4-digit
  values never overflow. Rows share the height (TV fills the stage); on phones the name column is
  sticky and 72 px cells scroll horizontally.
- Avatars: `AvatarImg` (picture or initials; sizes 24/40/64/96, optional gold/accent ring) is used
  in scoreboard chips, standings, answering highlights, auction/cat/final lists, the host list, the
  admin table (with «Удалить аватар» → `clear_avatar`) and next to «Ведущий» on the screen.
  `AvatarEditor` (player lobby + avatar button in the bar, host lobby + menu) crops to a centered
  square ≤ 512 px on a canvas (`utils/avatar.ts`, WebP or JPEG) and uploads via `POST /api/avatar`;
  the new URL arrives with the next `state`.
- Media: question, answer and comment blocks all render through `QuestionBlocks` → `MediaBlock`
  with the role's playback mode (protocol §3): screen autoplays (answer media when `reveal`
  starts; question media pauses then), player video is muted autoplay with controls, host and the
  editor preview get controls and no autoplay.
- `src/pages/` — one file per route:
  `/` (create a game / enter a PIN) · `/g/:pin` (role step) · `/g/:pin/play` · `/g/:pin/host` ·
  `/g/:pin/screen` · `/g/:pin/admin` · `/g/:pin/admin/packs` · `/g/:pin/admin/packs/:id`.

## Roles
- One server runs many games; there are no server-wide PINs. The admin (game PIN + admin PIN)
  owns the pack library/editor, `load_pack`, settings, the game file, rename/PIN change, close.
  The host (one per game) runs the game. Screen is a role joined like the others.
- Game-scoped pages read their token from storage; no token → back to `/g/:pin`. Every page has
  «Выйти» (`leave`, then forget the token).
- `game.pin` / `game.link` are nullable: a screen opened from the public game list (`watch`)
  never receives them, so the screen lobby then shows no PIN/QR. Never put a PIN in a public list.
- The dev proxy (and any reverse proxy in production) keeps the browser's `Host` — the backend builds share links from the
  request origin.

## Conventions
- `../docs/en/05-protocol.md` is authoritative for REST/WS. Never invent fields; if the protocol
  changes, update `types/protocol.ts` and every consumer together.
- `../DESIGN_MANIFEST.md` defines tokens and component behaviour. Dark only; one primary action per state.
- UI language is Russian.
- Times are shown in the viewer's local zone as ISO `YYYY-MM-DD HH:MM:SS` (`utils/time.ts`).
- Never render the correct answer on player/screen surfaces before `reveal` (the server already
  filters, the UI must not work around it). The admin UI never renders board/question.
- Media URLs from the server are relative (`/api/packs/...`) — the SPA is served same-origin.
