# Contributing

Thanks for helping with «Своя игра»! Bug reports, ideas, question packs and pull
requests are welcome.

## Before you start

- Read the app's own `CLAUDE.md` (`backend/`, `frontend/`, `clients/`, `tv/`) — it
  lists the conventions of that part.
- [`docs/en/05-protocol.md`](docs/en/05-protocol.md) is the contract between the server
  and all clients. A protocol change updates the backend, all three clients and both
  language versions of that file.

## Tooling

| Part | Tooling | Check |
|---|---|---|
| `backend/` | Go, `make` | `make -C backend test` |
| `frontend/` | `pnpm` (never npm/yarn) | `pnpm typecheck && pnpm test` |
| `clients/`, `tv/` | Flutter via the app's `Makefile` | `flutter test` |

## Every change

- Update the matching page in **both** `docs/en/` and `docs/ru/`.
- Add a bullet to `## [Unreleased]` in [`CHANGELOG.md`](CHANGELOG.md)
  ([Keep a Changelog](https://keepachangelog.com/en/1.1.0/)).

## Reporting bugs

Open an issue with: how you run the server (Docker, binary, MikroTik), the client and its
version, steps to reproduce, what you expected and what happened. Security problems: see
[SECURITY.md](SECURITY.md).
