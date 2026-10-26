# syntax=docker/dockerfile:1
#
# One image for the whole server: the Go backend serves the API, the WebSocket
# and the built web client (STATIC_DIR) from a single port. The final stage is
# `scratch`: a static binary and the web files, nothing else.
#
# The build stages run on the build machine's architecture and cross-compile,
# so `--platform linux/arm64` needs no emulation (see `make mikrotik`).
#
# APP_USER is the uid:gid the server runs as. The default is unprivileged; the
# MikroTik image uses 0:0 because RouterOS mounts are owned by root.
ARG APP_USER=10001:10001

# ---- web client ----
FROM --platform=$BUILDPLATFORM node:24-alpine AS web
WORKDIR /src
# Node's happy-eyeballs gives each address 250 ms and then fails on slow networks.
ENV NODE_OPTIONS=--no-network-family-autoselection
RUN corepack enable && corepack prepare pnpm@9.15.9 --activate
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN --mount=type=cache,id=pnpm,target=/root/.local/share/pnpm/store \
    pnpm install --frozen-lockfile
COPY frontend/ ./
RUN pnpm build

# ---- server ----
FROM --platform=$BUILDPLATFORM golang:1.26-alpine AS server
WORKDIR /src
COPY backend/go.mod backend/go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY backend/ ./
ARG TARGETOS
ARG TARGETARCH
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/svoy-igra . \
 && mkdir -p /out/data

# ---- runtime ----
FROM scratch
ARG APP_USER
COPY --from=server /out/svoy-igra /app/svoy-igra
COPY --from=web /src/dist /app/web
# An empty, writable data directory for the unprivileged user (scratch has no mkdir).
COPY --from=server --chown=${APP_USER} /out/data /data
USER ${APP_USER}
# scratch has no /tmp: the server stages uploads in $DATA_DIR/tmp and points
# TMPDIR (used by SQLite and the Go runtime) at the same place.
ENV DATA_DIR=/data \
    TMPDIR=/data/tmp \
    STATIC_DIR=/app/web \
    SERVER_PORT=3050 \
    DISCOVERY_PORT=3051
VOLUME /data
EXPOSE 3050 3051/udp
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/app/svoy-igra", "healthcheck"]
ENTRYPOINT ["/app/svoy-igra"]
