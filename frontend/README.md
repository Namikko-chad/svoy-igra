# Своя игра — web client

Vue 3 + Vite + TypeScript SPA for players, the host, the admin and the big screen.

```bash
cp .env.example .env      # FRONTEND_PORT (3000), BACKEND_URL (http://localhost:3050)
pnpm install
pnpm dev                  # http://0.0.0.0:3000, /api (REST + WS) proxied to BACKEND_URL
pnpm build                # → dist/
pnpm typecheck && pnpm test
```

Routes: `/` create a game or enter a game PIN · `/g/:pin` choose a role · `/g/:pin/play` ·
`/g/:pin/host` · `/g/:pin/screen` · `/g/:pin/admin` · `/g/:pin/admin/packs` · `/g/:pin/admin/packs/:id`.

Production: the root `Dockerfile` builds `dist/` into the server image; the backend serves it
(`STATIC_DIR`) from the same origin as the API.

The protocol (`../docs/en/05-protocol.md`) and the design manifest (`../DESIGN_MANIFEST.md`) are authoritative.
