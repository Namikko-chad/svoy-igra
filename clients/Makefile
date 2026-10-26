FLUTTER ?= flutter
# Host of the share links opened as Android App Links (https://<host>/g/<PIN>).
# Empty: only the svoyigra:// scheme is handled.
APP_LINK_HOST ?=
# Device for `make run`: empty = the one flutter picks, or linux / windows / macos / an Android id.
DEVICE ?=

APP_LINK_ARG = $(if $(APP_LINK_HOST),-PAPP_LINK_HOST=$(APP_LINK_HOST),)
DEVICE_ARG = $(if $(DEVICE),-d $(DEVICE),)

.PHONY: deps analyze test run build-apk build-apk-debug build-linux build-windows build-macos cert-sha256 clean

deps:
	$(FLUTTER) pub get

analyze: deps
	$(FLUTTER) analyze

test: deps
	$(FLUTTER) test

run: deps
	$(FLUTTER) run $(DEVICE_ARG) $(APP_LINK_ARG)

# Release APK, signed with the debug key (fine for LAN distribution).
build-apk: deps
	$(FLUTTER) build apk --release $(APP_LINK_ARG)

build-apk-debug: deps
	$(FLUTTER) build apk --debug $(APP_LINK_ARG)

# Desktop builds run on their own OS (Flutter does not cross-compile desktop apps).
# Linux: build/linux/x64/release/bundle/ (run ./svoy_igra; keep the folder together).
build-linux: deps
	$(FLUTTER) build linux --release

# Windows: build\windows\x64\runner\Release\ (svoy_igra.exe + DLLs + data\).
build-windows: deps
	$(FLUTTER) build windows --release

# macOS: build/macos/Build/Products/Release/SvoyIgra.app (unsigned).
build-macos: deps
	$(FLUTTER) build macos --release

# SHA-256 fingerprint of the signing certificate → server env ANDROID_CERT_SHA256.
cert-sha256:
	keytool -list -v -keystore $(HOME)/.android/debug.keystore -alias androiddebugkey \
		-storepass android -keypass android | grep 'SHA256:'

clean:
	$(FLUTTER) clean
