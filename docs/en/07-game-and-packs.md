# Game rules and question packs

## Avatars

Every player and the host can upload their own picture (from the play or host screen).
Clients crop it to a square; the server accepts PNG, JPEG, WebP or GIF up to 2 MB. Avatars
appear in the scoreboard, the answering highlight, auctions, the final and the standings;
without one the initials are shown. The admin can remove any avatar. Avatars are deleted
together with the game.

## Game settings

| Setting | Default | Who | Effect |
|---|---|---|---|
| Reading time | 10 s | host, admin | common timer before buttons open (a question may override it) |
| Buzz window | 15 s | host, admin | time to press after the buttons open; nobody pressed → the answer is revealed |
| Penalty for a wrong answer | off | host, admin | subtract the question value on a wrong answer |
| Automatic latency compensation | off | admin | open each button earlier by half that player's average round-trip time |
| Special questions per round | 1 of each kind | host, admin | how many cats, auctions, no-risk and double questions are hidden in each normal round (0–5 each) |
| Final answer time | 60 s | host, admin | time to type the final answer |
| Button shift per player | 0 ms | admin | −5000…+10000 ms; positive = that player's button appears later |

## Phases

The admin loads a pack in the lobby; the host starts the game.
`lobby` → `board` → `question` → `answering` → `reveal` → `board` … → `round_end` →
next round … → `finished`. The host can skip a question, jump to any round, finish or
reset the game at any time. Full transition rules: [Protocol §4.4](05-protocol.md#44-game-flow).

## Special questions

At the start of every normal round the server hides special questions in random cells —
by default one of each kind; the admin or host sets how many of each (0–5) per round. A
special cell looks like any other until it is opened.

| Kind | What happens | Correct | Wrong |
|---|---|---|---|
| Кот в мешке | the chooser must give the question to another player, who answers alone | +value | −value |
| Аукцион | players bid in turn (raise, «Ва-банк» = the whole score, or «Пас»); the highest bidder answers alone | +bid | −bid |
| Вопрос без риска | only the chooser answers | +2×value | nothing lost |
| Двойная стоимость | a normal question with buttons | +2×value | −2×value if the wrong-answer penalty is on |

Nobody presses a button for a question answered alone: after the reading time that player
answers and the host judges.

## Final

A round marked «Финал» in the pack editor is played as the final: each theme holds one
question. Players with a positive score take part. In turn — lowest score first — they
strike out themes until one is left; then everyone makes a secret bet (1 … their score),
sees the question and types an answer within the time limit (60 s by default). The host
judges each finalist: correct adds the bet, wrong subtracts it. Then the correct answer
and the results are shown to all. The host can skip the final while themes are being
removed.

## The game file

The server writes each game to `DATA_DIR/games/<id>.json` within a second of every change
and deletes it after an hour without anyone connected. The admin can download the game's
content (a backup, statistics) and upload it later into the same or another game —
players whose tokens are in the file reconnect with them. The file holds players, scores, device info, button shifts,
statistics, played questions, settings and the full history. Format: [Protocol §6](05-protocol.md#6-game-file-json).

## Packs

A pack has a title, author, description and rounds. Each round has up to 10 categories;
each category is a column of questions. A round can be switched to «Финал»: its
categories become final themes with exactly one question each and no value. A new question gets the value
`100 × its position` (100, 200, 300…); the value can be changed.

The pack library is shared by every game on the server. Packs are created and edited by
any game's admin in the built-in editor (web and apps), and moved between servers as
`.dub` files (download/upload in the pack library). To generate packs with a script or
another tool, see [Pack file format](13-pack-format.md).

**Locked packs.** An admin can lock a pack (this cannot be undone in the app). A locked pack
cannot be edited or deleted; «Редактировать» on it asks for a new title and opens an
editable copy. The lock travels inside the `.dub`. The server operator can unlock a pack
with `svoy-igra unlock-pack <id>`.

### Writing questions

Question, answer and host comment are Markdown. Raw HTML is not rendered.

```md
**Кто** изображён на фото?

![](media:portrait.jpg)
```

Each markdown field (question, answer, comment) has a toolbar: bold, italic, heading,
bulleted and numbered lists, quote, link and «Медиа». «Медиа» picks a file of the pack or
uploads a new one and writes `![](media:<name>)` at the cursor of that field — so media
can go into the question and into the answer alike. The editor preview plays it. The kind
is decided by extension:

| Kind | Extensions | On the screen | On a player's device |
|---|---|---|---|
| image | png jpg jpeg gif webp svg bmp | shown | shown |
| video | mp4 webm mov m4v mkv | autoplays with sound | plays muted |
| audio | mp3 ogg oga wav m4a aac flac opus | autoplays | «звучит на экране», can be played manually |

Media in the answer follows the same rules and plays when the answer is revealed (the
screen autoplays it). Combine freely: text, a picture and a sound clip in one question. For long media set the
question's own reading time so buttons do not open before the clip ends.

Media file names may contain Latin letters, digits, `.`, `-`, `_`; uploads with other
characters are renamed (Cyrillic is transliterated).
