FLUTTER ?= flutter

.PHONY: deps analyze test run build-apk build-apk-debug clean

deps:
	$(FLUTTER) pub get

analyze: deps
	$(FLUTTER) analyze

test: deps
	$(FLUTTER) test

run: deps
	$(FLUTTER) run

build-apk: deps
	$(FLUTTER) build apk --release

build-apk-debug: deps
	$(FLUTTER) build apk --debug

clean:
	$(FLUTTER) clean
