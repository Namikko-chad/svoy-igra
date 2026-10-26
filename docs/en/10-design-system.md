# Design system

The portable visual language — colour, type, spacing, components and rules — is
[`DESIGN_MANIFEST.md`](../../DESIGN_MANIFEST.md) at the repository root. All three
clients implement the same tokens; this page says where.

| Client | Tokens | Components |
|---|---|---|
| Web | `frontend/src/styles/tokens.css` (CSS custom properties), `base.css` | `frontend/src/components/` (`GameBoard`, `BuzzerButton`, `TimerBar`, `Scoreboard`, …) |
| Apps (Android, desktop) | `clients/lib/core/theme.dart` (`AppColors`, `AppText`, `buildTheme`) | `clients/lib/features/game/`, `clients/lib/features/player/buzzer.dart` |
| TV | `tv/lib/core/theme/` (`AppColors`, `AppText`, `AppTheme`) | `tv/lib/features/display/widgets/`, `tv/lib/core/widgets/tv_button.dart` |

## Per-client notes

- **Fonts.** Unbounded (display), Inter (body), JetBrains Mono (metrics). The web client
  loads them from Google Fonts with system fallbacks; the apps and TV bundle the files.
- **Web.** No UI framework; components are plain Vue + CSS. Layouts are mobile-first
  (360 px) for player/host/admin; `/screen` targets 1920×1080 and scales.
- **TV.** A fixed 1920×1080 stage scaled to the screen, so manifest pixel sizes are literal.
  Category headers are 24 px (larger than the manifest range) for reading at a distance.
  Every control has the accent focus ring for D-pad use.
- **Latency colours** (admin): `< 60 ms` success, `60–150 ms` warning, `> 150 ms` danger.

Adding a rule: portable → `DESIGN_MANIFEST.md`; client-specific (a file, a library) → this
page and that client's `CLAUDE.md`.
