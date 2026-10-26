# Pack file format (`.dub`) — a guide for pack generators

This page is everything a person or a program needs to **produce a question pack**
that the server imports and plays. It is self-contained; the authoritative short form is
[Protocol §3 and §5](05-protocol.md).

## 1. The archive

A `.dub` file is a **ZIP archive** (the extension is just renamed) with exactly this layout:

```
pack.sqlite          the questions (SQLite 3 database)
media/<name>         pictures, video and audio referenced by the questions (optional)
```

- No other entries are allowed — no top-level folder, no `__MACOSX/`, no `.DS_Store`,
  no `readme.txt`. A `media/` directory entry itself is tolerated.
- Compression: `pack.sqlite` deflated, media **stored** (they are compressed already).
  Either method works for either file; this is only the recommended choice.
- The total **unpacked** size must not exceed the server's `MAX_UPLOAD_MB` (1024 MB by
  default); the uploaded file obeys the same limit.

## 2. `pack.sqlite`

Create exactly these tables (`format_version` 1):

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE rounds (
  id INTEGER PRIMARY KEY,
  position INTEGER NOT NULL,              -- 0-based order of rounds
  name TEXT NOT NULL,                     -- ≤ 100 characters
  kind TEXT NOT NULL DEFAULT 'normal');   -- 'normal' | 'final'
CREATE TABLE categories (
  id INTEGER PRIMARY KEY,
  round_id INTEGER NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,              -- 0-based order inside the round
  name TEXT NOT NULL);                    -- ≤ 100 characters
CREATE TABLE questions (
  id INTEGER PRIMARY KEY,
  category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,              -- 0-based order inside the category
  value INTEGER NOT NULL,                 -- points, 0 … 1 000 000
  question TEXT NOT NULL,                 -- markdown, ≤ 20 000 characters
  answer TEXT NOT NULL,                   -- markdown, ≤ 20 000 characters
  comment TEXT NOT NULL DEFAULT '',       -- markdown note for the host, shown on reveal
  reading_seconds INTEGER);               -- NULL = game default (10 s); else 1 … 120
```

### `meta` rows

| key | value | required |
|---|---|---|
| `format_version` | the string `'1'` | **yes** — import rejects the pack without it |
| `title` | pack title, ≤ 200 characters | yes (an empty title becomes «Без названия») |
| `author` | free text | no |
| `description` | free text | no |
| `created_at`, `updated_at` | Unix milliseconds as a string, e.g. `'1792999881988'` | no (set on import) |
| `locked` | `'1'` makes the pack read-only on the server (editing creates a copy) | no |

All `value`s are TEXT. Unknown keys are ignored.

### Structure rules

- **Rounds** are played in `position` order. A pack needs at least one round with questions.
- **Categories (themes):** at most **10 per round**. Ten is the classic board.
- **Questions** in a category are shown left to right in `position` order. Give them
  increasing values; the editor's default is `100 × (position + 1)` — 100, 200, 300, …
  A category may hold any number of questions (5–10 is typical).
- **Positions** are 0-based and contiguous within their parent (0, 1, 2, …).
- **Ids** are any distinct integers per table; foreign keys must point to existing rows.
- **Final round** (`kind = 'final'`, usually the last round): every category is a final
  theme holding **exactly one** question; `value` must be `0` and `reading_seconds` NULL
  (players bet instead). 3–7 themes is typical. The game ignores extra questions in a
  final theme — do not create them.
- Special questions (Кот в мешке, Аукцион, …) are **not** part of the pack: the server
  places them at random when a round starts.

## 3. Question text (markdown)

`question`, `answer` and `comment` are CommonMark. Raw HTML is **not** rendered (it shows
as text). Use the usual markdown: `**bold**`, `*italic*`, lists, `> quotes`, links.

**Media** is inserted with image syntax and the `media:` scheme:

```md
Кто изображён на портрете?

![](media:portrait.jpg)

Послушайте отрывок: ![](media:anthem.mp3)
```

- `media:<name>` refers to `media/<name>` inside the archive. `http(s)://…` URLs also
  work, but a pack should be self-contained.
- The **file extension** decides how it is played (case-insensitive):

  | Kind | Extensions | Played as |
  |---|---|---|
  | image | `png jpg jpeg gif webp svg bmp` (and anything unknown) | picture |
  | video | `mp4 webm mov m4v mkv` | video (sound on the big screen) |
  | audio | `mp3 ogg oga wav m4a aac flac opus` | audio |

- Each reference becomes its own block at that position; the text around it is shown
  above/below it. Put media on its own line.
- Media works in the question, the answer and the comment. Answer media plays when the
  answer is revealed.
- For long video/audio in a question, set the question's `reading_seconds` to the clip
  length so the answer buttons do not open before the clip ends.
- Prefer widely playable formats: **JPEG/PNG/WebP**, **MP4 (H.264 + AAC)**, **MP3**.
  SVG does not display on the TV app.

## 4. Media files

- Name: 1–128 characters of `A–Z a–z 0–9 . _ -`, not starting with `.`. No spaces, no
  Cyrillic, no subfolders: `media/sub/x.png` is rejected.
- Every name used in markdown should exist in `media/`; a missing file shows as a broken
  item. Unused files are allowed but waste space.
- Keep files reasonably small: phones download them over Wi-Fi during the game
  (pictures ≤ 2 MB, audio/video ≤ 20–30 MB each is a good rule).

## 5. What the importer checks

The server rejects the file with `400 invalid_pack` when:

- it is not a ZIP archive, or an entry is outside `pack.sqlite` / `media/<valid name>`
  (path traversal, folders, other files);
- the unpacked size exceeds `MAX_UPLOAD_MB`;
- `pack.sqlite` is missing, is not SQLite, has no `meta.format_version` or it is not `'1'`;
- the tables `rounds`, `categories` or `questions` are missing.

It does **not** re-validate lengths, value ranges, the 10-category limit or the final
round's one-question rule — the editor enforces those, so a generated pack must follow
them itself. An imported pack gets a new id; `rounds.kind` is added if absent.

## 6. Reference generator (Python 3, standard library only)

```python
"""Build a .dub pack. Run: python3 make_pack.py  →  pack.dub"""
import sqlite3, tempfile, time, zipfile, os

def build_dub(path, title, rounds, media_dir=None, author="", description=""):
    """rounds: [{"name": str, "kind": "normal"|"final",
                 "categories": [{"name": str,
                                 "questions": [{"value": int, "question": str, "answer": str,
                                                "comment": str, "reading_seconds": int|None}]}]}]
    media_dir: folder whose files are packed as media/<file name>."""
    with tempfile.TemporaryDirectory() as tmp:
        db_path = os.path.join(tmp, "pack.sqlite")
        db = sqlite3.connect(db_path)
        db.executescript("""
            CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE rounds (id INTEGER PRIMARY KEY, position INTEGER NOT NULL,
              name TEXT NOT NULL, kind TEXT NOT NULL DEFAULT 'normal');
            CREATE TABLE categories (id INTEGER PRIMARY KEY,
              round_id INTEGER NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
              position INTEGER NOT NULL, name TEXT NOT NULL);
            CREATE TABLE questions (id INTEGER PRIMARY KEY,
              category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
              position INTEGER NOT NULL, value INTEGER NOT NULL,
              question TEXT NOT NULL, answer TEXT NOT NULL, comment TEXT NOT NULL DEFAULT '',
              reading_seconds INTEGER);
        """)
        now = str(int(time.time() * 1000))
        db.executemany("INSERT INTO meta(key, value) VALUES (?, ?)", [
            ("format_version", "1"), ("title", title), ("author", author),
            ("description", description), ("created_at", now), ("updated_at", now)])
        for r_pos, rnd in enumerate(rounds):
            final = rnd.get("kind") == "final"
            assert len(rnd["categories"]) <= 10, "at most 10 categories per round"
            r_id = db.execute("INSERT INTO rounds(position, name, kind) VALUES (?, ?, ?)",
                              (r_pos, rnd["name"], "final" if final else "normal")).lastrowid
            for c_pos, cat in enumerate(rnd["categories"]):
                if final:
                    assert len(cat["questions"]) == 1, "a final theme has exactly one question"
                c_id = db.execute("INSERT INTO categories(round_id, position, name) VALUES (?, ?, ?)",
                                  (r_id, c_pos, cat["name"])).lastrowid
                for q_pos, q in enumerate(cat["questions"]):
                    db.execute("""INSERT INTO questions(category_id, position, value, question,
                                  answer, comment, reading_seconds) VALUES (?, ?, ?, ?, ?, ?, ?)""",
                               (c_id, q_pos, 0 if final else q.get("value", 100 * (q_pos + 1)),
                                q["question"], q["answer"], q.get("comment", ""),
                                None if final else q.get("reading_seconds")))
        db.commit()
        db.close()
        with zipfile.ZipFile(path, "w") as z:
            z.write(db_path, "pack.sqlite", compress_type=zipfile.ZIP_DEFLATED)
            if media_dir:
                for name in sorted(os.listdir(media_dir)):
                    z.write(os.path.join(media_dir, name), "media/" + name,
                            compress_type=zipfile.ZIP_STORED)

if __name__ == "__main__":
    build_dub("pack.dub", "Пример", [
        {"name": "Раунд 1", "categories": [
            {"name": "Кино", "questions": [
                {"value": 100, "question": "Кто снял «Сталкер»?", "answer": "Андрей Тарковский"},
                {"value": 200, "question": "Чья это музыка?\n\n![](media:theme.mp3)",
                 "answer": "Эдуард Артемьев", "reading_seconds": 20},
            ]},
        ]},
        {"name": "Финал", "kind": "final", "categories": [
            {"name": "Космос", "questions": [{"question": "Первый человек в космосе?",
                                              "answer": "Юрий Гагарин"}]},
            {"name": "Реки", "questions": [{"question": "Самая длинная река Европы?",
                                            "answer": "Волга"}]},
        ]},
    ], media_dir="media")   # a folder containing theme.mp3
```

## 7. Checklist before shipping a pack

- [ ] ZIP contains only `pack.sqlite` and `media/<file>` entries.
- [ ] `meta.format_version = '1'`, `meta.title` set.
- [ ] ≤ 10 categories per round; positions 0-based and contiguous.
- [ ] Values increase left to right; final questions have `value 0`, one per theme.
- [ ] Every `media:<name>` exists in `media/`; names use only `A–Z a–z 0–9 . _ -`.
- [ ] Media in common formats (JPEG/PNG/WebP, MP4 H.264, MP3); long clips have `reading_seconds`.
- [ ] Answers are short and checkable; put explanations in `comment`.
- [ ] The file imports: admin page → «Паки» → «Импорт .dub» (or `POST /api/packs/import`).
