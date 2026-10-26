# Global Rules

## CLAUDE Rules
- Always check the `CLAUDE.md` inside each app folder (`backend/`, `frontend/`, `clients/`, `tv/`).

## What this is
«Своя игра» — a Jeopardy-style quiz for a room: a Go server runs the game, players
answer from the web site or the app (Android, Windows, Linux, macOS), the host runs it from the same clients,
an admin watches players and latency, an Android TV shows the board.

## Repository Structure
| Dir | What | Tooling |
|---|---|---|
| `backend/` | Go server: REST + WebSocket, game engine, pack library, LAN discovery | `make` |
| `frontend/` | Vue 3 + Vite web client (player, host, pack editor, admin, screen) | `pnpm` |
| `clients/` | Flutter app for Android, Windows, Linux, macOS — functionally identical to the web client | `make` / `flutter` |
| `tv/` | Flutter Android TV app — read-only screen | `make` / `flutter` |
| `docs/` | Documentation, `docs/en` + `docs/ru` | — |

- Apps live in **separate directories**; never mix code, configs or dependencies.
- The three clients do not share code. They share one contract:
  **`docs/en/05-protocol.md` is authoritative** for REST, WebSocket, the `.dub` pack
  format and the game JSON. A protocol change updates the backend, all three clients
  and both language versions of that file in the same change.

## Package Managers & Build Tools
- **Frontend:** always `pnpm` (never `npm` or `yarn`).
- **Backend:** always `make`.
- **Flutter apps:** the app's `Makefile` (wraps `flutter`).

## Storage
- The backend has **no database server**. Question packs are SQLite files in
  `DATA_DIR/packs/<id>/` (portable as `.dub` = ZIP of `pack.sqlite` + `media/`); the
  server runs many games, each one JSON file (`DATA_DIR/games/<id>.json`). Never add
  Postgres/Redis/etc. There are no server-wide passwords: every token belongs to one game.

## Git Workflow
- All development goes through the **`main`** branch.
- Never commit unless explicitly asked — just write code.

## Time & Timezone
- The backend stores and sends time as **Unix milliseconds, UTC**.
- Clients display time in the **device's local time zone**, formatted ISO 8601
  `YYYY-MM-DD HH:MM:SS` (e.g. `2026-06-15 14:30:05`).
- Countdowns use the server clock: `offset = serverNow - localNow` from each `state`.

## Running Locally for Testing
When asked to run the project for testing:
1. Start the **backend**: `cd backend && make development` (needs `backend/.env`,
   copy from `.env.example`; port 3050, UDP discovery 3051).
2. Start the **frontend**: `cd frontend && pnpm dev` (port 3000, proxies `/api` to the backend).
3. Do **not** expose raw API endpoints for manual testing — let the user interact through the UI.
4. Both processes must run simultaneously; confirm both are healthy before reporting it ready.

## Design System
The visual language of all three clients is defined in **`DESIGN_MANIFEST.md`** —
portable tokens, components and rules. It must NOT contain file paths, project names,
env var names, third-party library names, or project-state language. Each client
implements the tokens in its own idiom (CSS variables / Flutter theme); client-specific
notes go to that client's `CLAUDE.md`. Never record migration history — git is the archive.

## Documentation
Full documentation lives in `docs/`, one subdirectory per language (`docs/en/`,
`docs/ru/`). **All present language subdirectories must stay in sync** — never update
one without the rest, in the same change. Document what the code actually does; trim
obsolete content rather than marking it "legacy".

| Code area changed | Update this doc |
|---|---|
| Project purpose, scope, roles | `01-introduction.md` |
| New top-level doc section/file | `02-table-of-contents.md` |
| Env vars, run/build/deploy commands, Docker, APK builds | `03-getting-started.md` |
| Component wiring (`backend/app/server.go`), data flow, lifecycle | `04-architecture.md` |
| REST, WebSocket messages, game flow, `.dub` format, game JSON, discovery | `05-protocol.md` |
| Backend packages (`backend/app/*`) | `06-backend-structure.md` |
| Game rules as players/hosts see them, question markdown authoring | `07-game-and-packs.md` |
| Web client layout (`frontend/src/*`) | `09-frontend-structure.md` |
| Design tokens/components, per-client theme | `10-design-system.md` (+ `DESIGN_MANIFEST.md`) |
| App clients (`clients/lib/*`, platform runners) | `11-clients.md` |
| TV app (`tv/lib/*`) | `12-tv.md` |
| `.dub` pack format, pack import/export rules (`backend/app/packs`) | `13-pack-format.md` (+ `05-protocol.md` §3, §5) |

Rules: all languages updated atomically; cross-reference links stay valid; document
real (not aspirational) behavior; a code change without the matching docs update is incomplete.

## CHANGELOG
A `CHANGELOG.md` lives at the repository root. **Every file-modifying change must add an entry.**
- Same change, same entry (no "later").
- [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format: an `[Unreleased]`
  section on top, then version sections newest-first, grouped under
  `Added`/`Changed`/`Deprecated`/`Removed`/`Fixed`/`Security`.
- [SemVer](https://semver.org/) `MAJOR.MINOR.PATCH`. Any `BREAKING:` bullet → MAJOR;
  else any `Added` → MINOR; else PATCH.
- **Cut a release at the end of every session that produced file-modifying changes:**
  replace `## [Unreleased]` with `## [X.Y.Z] - YYYY-MM-DD` and insert a fresh empty
  `## [Unreleased]` above it. Read the most recent version heading to find the previous
  version — never invent one. A docs-only session still cuts a `PATCH`.
  Keep `backend/app/config/config.go` `Version` equal to the released version.
- One bullet per concrete change, referencing the affected module / path / endpoint.
- Describe the user- or operator-visible effect. No CHANGELOG entry = the change is not done.

When refactoring: fully replace the old component and update all call sites; don't keep
a deprecated version "for compatibility"; converge to one implementation.

## Git Worktrees — FORBIDDEN

- **Never use git worktrees.** Do not run `git worktree add` / `list` / `remove` / `prune`, do not create or work inside a separate worktree directory, and never suggest a worktree as a way to isolate work.
- Do not use any tool or agent "worktree" isolation mode (e.g. the `EnterWorktree` / `ExitWorktree` tools, or `isolation: "worktree"` when spawning an agent).
- Work directly in the existing repository clone. If another branch is needed, verify the tree is clean and switch in place with `git switch`.
