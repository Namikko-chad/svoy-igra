# Web client structure

Vue 3 (`<script setup lang="ts">`) + Vite + TypeScript + vue-router + Pinia, `markdown-it`
(`html: false`, `linkify`), `qrcode-generator` for the join QR. No UI framework: the design
system is CSS custom properties plus own components. Rules: `frontend/CLAUDE.md`.

## Routes

| Path | Page | Who |
|---|---|---|
| `/` | create a game (admin PIN + confirm, optional title) or enter a game PIN; games this browser holds tokens for | everyone |
| `/g/:pin` | role step: game title/pack/players, Игрок (name) / Ведущий (disabled while taken) / Экран / Администратор (admin PIN); «Продолжить как …»; «Открыть в приложении» on Android | everyone |
| `/g/:pin/play` | scoreboard, board, question, buzzer, typed answer, reveal, standings | player |
| `/g/:pin/host` | start the game (after the admin loads a pack), run it, judge, timers, reset | host |
| `/g/:pin/admin` | share card (PIN, link, copy, QR, Web Share), rename / admin PIN, pack selection, settings, game file, players table, reset, close game | admin |
| `/g/:pin/admin/packs` | shared library: create, import `.dub` with progress, export, delete, lock, «Редактировать копию» for locked packs | admin |
| `/g/:pin/admin/packs/:id` | pack editor: rounds, categories, questions, live preview, media manager (read-only notice for locked packs) | admin |
| `/g/:pin/screen` | big-screen view, «включить звук» overlay, double-click = fullscreen, lobby with link, QR and PIN | screen |

Every game page shares `GameShell` (top bar with the PIN and «Выйти» = `leave`) and
`useRoleSocket` (4001 → back to the role step, 4004 → «Игра закрыта», 4003 kicked,
4009 opened elsewhere). A page without a stored token goes to `/g/:pin`.

## Layout

```
src/
  main.ts, App.vue, router.ts
  types/protocol.ts        wire types from docs/en/05-protocol.md (+ normalizeView)
  api/http.ts              fetch wrapper: Bearer, {error:{code,message}} → ApiError
  api/transfer.ts          XHR uploads with progress, authenticated blob downloads
                           (Content-Disposition filename / filename*)
  api/index.ts             endpoints
  ws/client.ts             GameSocket: hello, ping→pong, reconnect 1…10 s, clock offset,
                           close codes 4001/4003/4009 stop reconnecting
  composables/             useGameSocket (errors → toasts, sound cues), useNow,
                           useQuestionTimer, useHostAuth
  stores/                  session (tokens in localStorage), toast
  utils/                   blocks (the §3 splitter), markdown, time, latency, device,
                           mediaName (transliteration), sound (WebAudio tones), reorder
  components/              GameBoard, BuzzerButton, TimerBar, Scoreboard, QuestionBlocks,
                           MediaBlock, Standings, QrCode, dialogs, toasts
    host/ admin/ editor/   role-specific panels
  pages/                   one file per route
  styles/tokens.css        DESIGN_MANIFEST.md tokens; base.css
tests/                     splitter and client unit tests (Vitest)
```

## Behaviour notes

- Special questions and the final: `components/special/SpecialStage.vue` renders
  `cat_transfer`, `auction` and every `final_*` phase for each role (player actions, host
  actions on behalf, read-only screen); a full-screen splash announces a modifier when a
  special cell opens. Pure view logic lives in `utils/special.ts`.
- Pack editor markdown fields use `components/editor/MarkdownField.vue`: toolbar (bold,
  italic, heading, lists, quote, link, «Медиа» picker/upload) on top of `utils/mdEdit.ts`;
  the live preview plays media. A round can be switched to «Финал».
- Tokens: `localStorage` key `svoy.token|<origin>|<pin>|<role>`, checked with `/api/auth/me`
  before «Продолжить как …» is offered.
- Timer bars: reading `readingStartsAt → readingEndsAt`, then `buzzStartsAt → buzzEndsAt`,
  on the server clock.
- Media uploads send a sanitised Latin `name` field before `file`.
- The dev server listens on `0.0.0.0:${FRONTEND_PORT:-3000}` and proxies `/api` (including
  the WebSocket) and `/.well-known/` to `${BACKEND_URL:-http://localhost:3050}`, keeping
  the browser's `Host` and adding `X-Forwarded-*` so share links point at the web client.
- Production: `pnpm build` → `dist/`, served by the backend (`STATIC_DIR`) from the same
  origin as the API — the root `Dockerfile` builds both into one image. A reverse proxy in
  front must pass `Host`/`X-Forwarded-Host` and WebSocket upgrades through.
- `index.html` carries the page description, Open Graph tags and a schema.org
  `WebApplication` block for search engines and link previews; `public/robots.txt` lets
  crawlers index only the start page (`/g/` game pages and `/api/` are disallowed).

## Commands

```bash
pnpm install · pnpm dev · pnpm build · pnpm typecheck · pnpm test
```
