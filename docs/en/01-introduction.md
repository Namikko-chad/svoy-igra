# Introduction

«Своя игра» is a Jeopardy-style quiz for a group in one room (or on one network).
A Go server runs the game; people take part from a web browser or an Android phone,
and an Android TV (or a browser on a projector) shows the board.

## Games and roles

One server runs many games at once. Anyone can **create a game** — no password needed —
choosing an admin PIN; the creator becomes the game's admin and gets a 6-digit game PIN
and a share link (`…/g/<PIN>`) to send to the chat. The link opens the web site or, on
Android, the app. **Joining** takes the game PIN, then a role:

| Role | Joins with | Can |
|---|---|---|
| Player | game PIN + name | when it is their turn, pick a question; press «Дать ответ» once the button opens; optionally type the answer |
| Host | game PIN (one host at a time) | see the correct answer, judge answers, run the game (start, skip, rounds, finish, reset), set timers |
| Admin | game PIN + admin PIN | choose the pack, manage and edit the shared pack library (import/export `.dub`, lock packs), download/upload the game file; see players' scores (and correct them), devices, latency, reaction stats; shift each player's button, enable latency compensation, remove players, rename the game, change the admin PIN, close the game |
| Screen | game PIN — or, without it, a game picked from the public list | show the board, questions with media, timers and scores; no controls. A screen picked from the list never learns the PIN, so it shows no join QR |

The list of games on a server is public, but it never shows PINs: only those the link or
PIN was shared with can play, host or administer. Players and the host can upload their own avatars. A game nobody is connected to for an
hour is deleted. Packs are shared by all games and
outlive them; a **locked** pack cannot be changed or deleted — editing it makes a copy.

## How a question plays

1. The chooser (the last player who answered correctly) picks a cell — a category and a value.
2. The question appears everywhere. A common timer (10 s by default) runs.
3. When it ends the server opens «Дать ответ» on each player's device — at the same
   moment for everyone unless the admin shifted someone's button.
4. The first press to reach the server wins; that player answers aloud (and may type).
5. The host judges. Correct: the value is added, the player becomes the chooser. Wrong:
   the other players get the button again (optionally the value is subtracted).
6. The correct answer is revealed; the host continues to the board.

A game is made of rounds; each round has up to 10 categories, each category a column
of questions of increasing value.

## Clients

| Client | Technology | Roles |
|---|---|---|
| Web site | Vue 3 + Vite, served by the backend | create/join, player, host, admin (+ pack editor), screen |
| App | Flutter, Android / Windows / Linux / macOS | the same as the web site; opens share links |
| TV app | Flutter, Android TV | screen only; picks a game from the list |

## Storage

There is no database server. Question packs are SQLite files kept by the backend and
exchanged as `.dub` archives (ZIP of `pack.sqlite` + `media/`). Each game (players,
scores, played questions, history, statistics) is a JSON file the backend saves
continuously; the admin can download or upload its content.

Next: [Getting started](03-getting-started.md) · [Architecture](04-architecture.md) · [Table of contents](02-table-of-contents.md)
