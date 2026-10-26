# Формат файла пака (`.dub`) — руководство для генераторов паков

На этой странице собрано всё, что нужно человеку или программе, чтобы **создать пак вопросов**,
который сервер импортирует и сможет запустить в игре. Страница самодостаточна; авторитетная краткая форма —
[Протокол §3 и §5](05-protocol.md).

## 1. Архив

Файл `.dub` — это **ZIP-архив** (просто с другим расширением) ровно с такой структурой:

```
pack.sqlite          вопросы (база данных SQLite 3)
media/<name>         картинки, видео и аудио, на которые ссылаются вопросы (необязательно)
```

- Никакие другие записи не допускаются — ни папки верхнего уровня, ни `__MACOSX/`, ни `.DS_Store`,
  ни `readme.txt`. Сама запись каталога `media/` допускается.
- Сжатие: `pack.sqlite` — deflate, медиафайлы — **stored** (они и так уже сжаты).
  Для любого файла подойдёт любой метод; это лишь рекомендуемый вариант.
- Суммарный **распакованный** размер не должен превышать серверный `MAX_UPLOAD_MB` (по умолчанию
  1024 МБ); на загружаемый файл действует тот же лимит.

## 2. `pack.sqlite`

Создайте ровно эти таблицы (`format_version` 1):

```sql
CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE rounds (
  id INTEGER PRIMARY KEY,
  position INTEGER NOT NULL,              -- порядок раундов, с 0
  name TEXT NOT NULL,                     -- ≤ 100 символов
  kind TEXT NOT NULL DEFAULT 'normal');   -- 'normal' | 'final'
CREATE TABLE categories (
  id INTEGER PRIMARY KEY,
  round_id INTEGER NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,              -- порядок внутри раунда, с 0
  name TEXT NOT NULL);                    -- ≤ 100 символов
CREATE TABLE questions (
  id INTEGER PRIMARY KEY,
  category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  position INTEGER NOT NULL,              -- порядок внутри категории, с 0
  value INTEGER NOT NULL,                 -- очки, 0 … 1 000 000
  question TEXT NOT NULL,                 -- markdown, ≤ 20 000 символов
  answer TEXT NOT NULL,                   -- markdown, ≤ 20 000 символов
  comment TEXT NOT NULL DEFAULT '',       -- markdown-заметка для ведущего, показывается при раскрытии
  reading_seconds INTEGER);               -- NULL = значение игры по умолчанию (10 с); иначе 1 … 120
```

### Строки `meta`

| ключ | значение | обязательно |
|---|---|---|
| `format_version` | строка `'1'` | **да** — без неё импорт отклоняет пак |
| `title` | название пака, ≤ 200 символов | да (пустое название превращается в «Без названия») |
| `author` | произвольный текст | нет |
| `description` | произвольный текст | нет |
| `created_at`, `updated_at` | миллисекунды Unix в виде строки, например `'1792999881988'` | нет (выставляются при импорте) |
| `locked` | `'1'` делает пак на сервере доступным только для чтения (редактирование создаёт копию) | нет |

Все `value` имеют тип TEXT. Неизвестные ключи игнорируются.

### Правила структуры

- **Раунды** играются в порядке `position`. В паке должен быть хотя бы один раунд с вопросами.
- **Категории (темы):** не более **10 на раунд**. Десять — классическое табло.
- **Вопросы** категории показываются слева направо в порядке `position`. Задавайте им
  возрастающую стоимость; по умолчанию редактор использует `100 × (position + 1)` — 100, 200, 300, …
  Категория может содержать любое количество вопросов (обычно 5–10).
- **Позиции** начинаются с 0 и идут без пропусков внутри родителя (0, 1, 2, …).
- **Id** — любые различные целые числа в пределах таблицы; внешние ключи должны указывать на существующие строки.
- **Финальный раунд** (`kind = 'final'`, обычно последний): каждая категория — финальная
  тема, содержащая **ровно один** вопрос; `value` должно быть `0`, а `reading_seconds` — NULL
  (вместо этого игроки делают ставки). Обычно 3–7 тем. Лишние вопросы в финальной теме игра
  игнорирует — не создавайте их.
- Специальные вопросы (Кот в мешке, Аукцион, …) **не** входят в пак: сервер
  расставляет их случайным образом при старте раунда.

## 3. Текст вопроса (markdown)

`question`, `answer` и `comment` — это CommonMark. Сырой HTML **не** рендерится (он отображается
как текст). Используйте обычный markdown: `**bold**`, `*italic*`, списки, `> quotes`, ссылки.

**Медиа** вставляются синтаксисом изображения со схемой `media:`:

```md
Кто изображён на портрете?

![](media:portrait.jpg)

Послушайте отрывок: ![](media:anthem.mp3)
```

- `media:<name>` ссылается на `media/<name>` внутри архива. URL `http(s)://…` тоже
  работают, но пак должен быть самодостаточным.
- Способ воспроизведения определяется **расширением файла** (без учёта регистра):

  | Вид | Расширения | Воспроизводится как |
  |---|---|---|
  | изображение | `png jpg jpeg gif webp svg bmp` (и всё неизвестное) | картинка |
  | видео | `mp4 webm mov m4v mkv` | видео (звук на большом экране) |
  | аудио | `mp3 ogg oga wav m4a aac flac opus` | аудио |

- Каждая ссылка становится отдельным блоком в этом месте; окружающий текст показывается
  над/под ним. Размещайте медиа на отдельной строке.
- Медиа работают в вопросе, ответе и комментарии. Медиа ответа воспроизводятся при
  раскрытии ответа.
- Для длинного видео/аудио в вопросе задайте `reading_seconds` вопроса равным длине
  клипа, чтобы кнопки ответа не открылись до окончания клипа.
- Предпочитайте широко поддерживаемые форматы: **JPEG/PNG/WebP**, **MP4 (H.264 + AAC)**, **MP3**.
  SVG не отображается в TV-приложении.

## 4. Медиафайлы

- Имя: 1–128 символов из `A–Z a–z 0–9 . _ -`, не начинается с `.`. Без пробелов, без
  кириллицы, без подпапок: `media/sub/x.png` отклоняется.
- Каждое имя, используемое в markdown, должно существовать в `media/`; отсутствующий файл отображается
  как битый элемент. Неиспользуемые файлы допускаются, но занимают место.
- Делайте файлы разумно небольшими: телефоны скачивают их по Wi-Fi во время игры
  (хорошее правило — картинки ≤ 2 МБ, аудио/видео ≤ 20–30 МБ каждый).

## 5. Что проверяет импортёр

Сервер отклоняет файл с `400 invalid_pack`, если:

- это не ZIP-архив, или запись лежит вне `pack.sqlite` / `media/<valid name>`
  (выход за пределы пути, папки, другие файлы);
- распакованный размер превышает `MAX_UPLOAD_MB`;
- `pack.sqlite` отсутствует, не является SQLite, не содержит `meta.format_version` или оно не равно `'1'`;
- отсутствуют таблицы `rounds`, `categories` или `questions`.

Он **не** перепроверяет длины, диапазоны значений, лимит в 10 категорий и правило одного вопроса
в финальном раунде — их обеспечивает редактор, поэтому сгенерированный пак должен соблюдать
их сам. Импортированный пак получает новый id; `rounds.kind` добавляется, если его нет.

## 6. Эталонный генератор (Python 3, только стандартная библиотека)

```python
"""Собрать пак .dub. Запуск: python3 make_pack.py  →  pack.dub"""
import sqlite3, tempfile, time, zipfile, os

def build_dub(path, title, rounds, media_dir=None, author="", description=""):
    """rounds: [{"name": str, "kind": "normal"|"final",
                 "categories": [{"name": str,
                                 "questions": [{"value": int, "question": str, "answer": str,
                                                "comment": str, "reading_seconds": int|None}]}]}]
    media_dir: папка, файлы которой упаковываются как media/<имя файла>."""
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
            assert len(rnd["categories"]) <= 10, "не более 10 категорий в раунде"
            r_id = db.execute("INSERT INTO rounds(position, name, kind) VALUES (?, ?, ?)",
                              (r_pos, rnd["name"], "final" if final else "normal")).lastrowid
            for c_pos, cat in enumerate(rnd["categories"]):
                if final:
                    assert len(cat["questions"]) == 1, "в финальной теме ровно один вопрос"
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
    ], media_dir="media")   # папка, содержащая theme.mp3
```

## 7. Чек-лист перед выпуском пака

- [ ] ZIP содержит только записи `pack.sqlite` и `media/<file>`.
- [ ] `meta.format_version = '1'`, `meta.title` задан.
- [ ] ≤ 10 категорий на раунд; позиции начинаются с 0 и идут без пропусков.
- [ ] Стоимость растёт слева направо; у финальных вопросов `value 0`, по одному на тему.
- [ ] Каждый `media:<name>` существует в `media/`; имена используют только `A–Z a–z 0–9 . _ -`.
- [ ] Медиа в распространённых форматах (JPEG/PNG/WebP, MP4 H.264, MP3); у длинных клипов задан `reading_seconds`.
- [ ] Ответы короткие и проверяемые; пояснения вынесены в `comment`.
- [ ] Файл импортируется: страница администратора → «Паки» → «Импорт .dub» (или `POST /api/packs/import`).
