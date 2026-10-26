.PHONY: backend frontend test apk-clients apk-tv linux up down mikrotik

# Run the backend (Go) on :3050.
backend:
	$(MAKE) -C backend development

# Run the web client (Vite) on :3000, proxying /api to the backend.
frontend:
	cd frontend && pnpm dev

# Backend tests.
test:
	$(MAKE) -C backend test

# Android builds.
apk-clients:
	$(MAKE) -C clients build-apk

apk-tv:
	$(MAKE) -C tv build-apk

# Desktop app for this computer (Linux; on Windows/macOS: make -C clients build-windows|build-macos).
linux:
	$(MAKE) -C clients build-linux

# Docker: backend + nginx-served web client.
up:
	docker compose up -d --build

down:
	docker compose down

# Image for a MikroTik router (RouterOS 7.21+, arm64): build/svoy-igra-arm64.tar
# to upload and add with /container/add file=… (docs/<lang>/03-getting-started.md).
MIKROTIK_TAR := build/svoy-igra-arm64.tar
mikrotik:
	mkdir -p build
	docker buildx build --builder default --platform linux/arm64 \
		--build-arg APP_USER=0:0 --provenance=false --sbom=false \
		-t svoy-igra:arm64 --load .
	docker save --platform linux/arm64 -o $(MIKROTIK_TAR) svoy-igra:arm64
	@ls -lh $(MIKROTIK_TAR)
