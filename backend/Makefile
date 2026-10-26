ifneq ("$(wildcard .env)","")
	include .env
	export
endif

.PHONY: development build run test lint clean

development:
	go run .

build:
	CGO_ENABLED=0 go build -ldflags="-s -w" -o bin/svoy-igra .

run: build
	./bin/svoy-igra

test:
	go test -count=1 ./...

lint:
	go vet ./...

clean:
	rm -rf bin
