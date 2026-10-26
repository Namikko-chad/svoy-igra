package packs

import (
	"database/sql"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unicode/utf8"

	"svoy-igra/app/httpx"
)

type Summary struct {
	ID          string `json:"id"`
	Title       string `json:"title"`
	Author      string `json:"author"`
	Description string `json:"description"`
	Rounds      int    `json:"rounds"`
	Categories  int    `json:"categories"`
	Questions   int    `json:"questions"`
	MediaCount  int    `json:"mediaCount"`
	SizeBytes   int64  `json:"sizeBytes"`
	CreatedAt   int64  `json:"createdAt"`
	UpdatedAt   int64  `json:"updatedAt"`
	Locked      bool   `json:"locked"`
}

type Pack struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Author      string  `json:"author"`
	Description string  `json:"description"`
	SizeBytes   int64   `json:"sizeBytes"`
	CreatedAt   int64   `json:"createdAt"`
	UpdatedAt   int64   `json:"updatedAt"`
	Locked      bool    `json:"locked"`
	Rounds      []Round `json:"rounds"`
	Media       []Media `json:"media"`
}

// Round kinds.
const (
	RoundNormal = "normal"
	RoundFinal  = "final"
)

type Round struct {
	ID         int64      `json:"id"`
	Position   int        `json:"position"`
	Name       string     `json:"name"`
	Kind       string     `json:"kind"`
	Categories []Category `json:"categories"`
}

type Category struct {
	ID        int64      `json:"id"`
	RoundID   int64      `json:"roundId"`
	Position  int        `json:"position"`
	Name      string     `json:"name"`
	Questions []Question `json:"questions"`
}

type Question struct {
	ID             int64  `json:"id"`
	CategoryID     int64  `json:"categoryId"`
	Position       int    `json:"position"`
	Value          int    `json:"value"`
	Question       string `json:"question"`
	Answer         string `json:"answer"`
	Comment        string `json:"comment"`
	ReadingSeconds *int   `json:"readingSeconds"`
}

// QuestionInput is a create/partial-update payload. ReadingSeconds uses a
// double pointer so "absent" and "null" differ.
type QuestionInput struct {
	Value          *int    `json:"value"`
	Question       *string `json:"question"`
	Answer         *string `json:"answer"`
	Comment        *string `json:"comment"`
	ReadingSeconds **int   `json:"readingSeconds"`
	Position       *int    `json:"position"`
}

type MetaInput struct {
	Title       *string `json:"title"`
	Author      *string `json:"author"`
	Description *string `json:"description"`
}

func meta(db *sql.DB) (map[string]string, error) {
	rows, err := db.Query(`SELECT key, value FROM meta`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	m := map[string]string{}
	for rows.Next() {
		var k, v string
		if err := rows.Scan(&k, &v); err != nil {
			return nil, err
		}
		m[k] = v
	}
	return m, rows.Err()
}

func atoi64(s string) int64 { n, _ := strconv.ParseInt(s, 10, 64); return n }

func (s *Store) Summary(id string) (*Summary, error) {
	db, err := s.db(id)
	if err != nil {
		return nil, err
	}
	m, err := meta(db)
	if err != nil {
		return nil, err
	}
	sum := &Summary{
		ID: id, Title: m["title"], Author: m["author"], Description: m["description"],
		CreatedAt: atoi64(m["created_at"]), UpdatedAt: atoi64(m["updated_at"]),
		SizeBytes: dirSize(s.packDir(id)), Locked: m["locked"] == "1",
	}
	err = db.QueryRow(`SELECT (SELECT count(*) FROM rounds), (SELECT count(*) FROM categories), (SELECT count(*) FROM questions)`).
		Scan(&sum.Rounds, &sum.Categories, &sum.Questions)
	if err != nil {
		return nil, err
	}
	media, _ := s.ListMedia(id)
	sum.MediaCount = len(media)
	return sum, nil
}

// Get returns the full pack tree.
func (s *Store) Get(id string) (*Pack, error) {
	sum, err := s.Summary(id)
	if err != nil {
		return nil, err
	}
	db, _ := s.db(id)
	p := &Pack{
		ID: id, Title: sum.Title, Author: sum.Author, Description: sum.Description,
		SizeBytes: sum.SizeBytes, CreatedAt: sum.CreatedAt, UpdatedAt: sum.UpdatedAt,
		Locked: sum.Locked, Rounds: []Round{},
	}

	roundIdx := map[int64]int{}
	rows, err := db.Query(`SELECT id, position, name, kind FROM rounds ORDER BY position, id`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		r := Round{Categories: []Category{}}
		if err := rows.Scan(&r.ID, &r.Position, &r.Name, &r.Kind); err != nil {
			rows.Close()
			return nil, err
		}
		roundIdx[r.ID] = len(p.Rounds)
		p.Rounds = append(p.Rounds, r)
	}
	rows.Close()

	type catRef struct{ r, c int }
	catIdx := map[int64]catRef{}
	rows, err = db.Query(`SELECT id, round_id, position, name FROM categories ORDER BY position, id`)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		c := Category{Questions: []Question{}}
		if err := rows.Scan(&c.ID, &c.RoundID, &c.Position, &c.Name); err != nil {
			rows.Close()
			return nil, err
		}
		ri, ok := roundIdx[c.RoundID]
		if !ok {
			continue
		}
		catIdx[c.ID] = catRef{ri, len(p.Rounds[ri].Categories)}
		p.Rounds[ri].Categories = append(p.Rounds[ri].Categories, c)
	}
	rows.Close()

	rows, err = db.Query(`SELECT id, category_id, position, value, question, answer, comment, reading_seconds FROM questions ORDER BY position, id`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		q, err := scanQuestion(rows)
		if err != nil {
			return nil, err
		}
		ref, ok := catIdx[q.CategoryID]
		if !ok {
			continue
		}
		cat := &p.Rounds[ref.r].Categories[ref.c]
		cat.Questions = append(cat.Questions, *q)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if p.Media, err = s.ListMedia(id); err != nil {
		return nil, err
	}
	return p, nil
}

type scanner interface{ Scan(...any) error }

func scanQuestion(r scanner) (*Question, error) {
	var q Question
	var rs sql.NullInt64
	if err := r.Scan(&q.ID, &q.CategoryID, &q.Position, &q.Value, &q.Question, &q.Answer, &q.Comment, &rs); err != nil {
		return nil, err
	}
	if rs.Valid {
		v := int(rs.Int64)
		q.ReadingSeconds = &v
	}
	return &q, nil
}

func cleanName(s string, field string, max int) (string, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return "", httpx.BadRequest("invalid_"+field, "Название не может быть пустым")
	}
	if utf8.RuneCountInString(s) > max {
		return "", httpx.BadRequest("invalid_"+field, "Слишком длинное название (максимум "+strconv.Itoa(max)+" символов)")
	}
	return s, nil
}

// UpdateMeta edits title/author/description.
func (s *Store) UpdateMeta(id string, in MetaInput) (*Summary, error) {
	db, err := s.writable(id)
	if err != nil {
		return nil, err
	}
	set := func(k, v string) error {
		_, err := db.Exec(`INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)`, k, v)
		return err
	}
	if in.Title != nil {
		t, err := cleanName(*in.Title, "title", 200)
		if err != nil {
			return nil, err
		}
		if err := set("title", t); err != nil {
			return nil, err
		}
	}
	if in.Author != nil {
		if err := set("author", strings.TrimSpace(*in.Author)); err != nil {
			return nil, err
		}
	}
	if in.Description != nil {
		if err := set("description", strings.TrimSpace(*in.Description)); err != nil {
			return nil, err
		}
	}
	s.touch(db)
	return s.Summary(id)
}

// reorder moves id to pos among the rows of table selected by scope and
// renumbers them 0..n-1.
func reorder(tx *sql.Tx, table, scope string, scopeArgs []any, id int64, pos *int) error {
	q := `SELECT id FROM ` + table
	if scope != "" {
		q += ` WHERE ` + scope
	}
	q += ` ORDER BY position, id`
	rows, err := tx.Query(q, scopeArgs...)
	if err != nil {
		return err
	}
	var ids []int64
	for rows.Next() {
		var x int64
		if err := rows.Scan(&x); err != nil {
			rows.Close()
			return err
		}
		if x != id || pos == nil {
			ids = append(ids, x)
		}
	}
	rows.Close()
	if pos != nil {
		p := max(0, min(*pos, len(ids)))
		ids = append(ids[:p], append([]int64{id}, ids[p:]...)...)
	}
	for i, x := range ids {
		if _, err := tx.Exec(`UPDATE `+table+` SET position=? WHERE id=?`, i, x); err != nil {
			return err
		}
	}
	return nil
}

func withTx(db *sql.DB, fn func(tx *sql.Tx) error) error {
	tx, err := db.Begin()
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}

var (
	errRoundNotFound    = httpx.NotFound("Раунд не найден")
	errCategoryNotFound = httpx.NotFound("Категория не найдена")
	errQuestionNotFound = httpx.NotFound("Вопрос не найден")
)

// ---- rounds ----

func (s *Store) getRound(db *sql.DB, id int64) (*Round, error) {
	r := Round{Categories: []Category{}}
	err := db.QueryRow(`SELECT id, position, name, kind FROM rounds WHERE id=?`, id).Scan(&r.ID, &r.Position, &r.Name, &r.Kind)
	if isNoRows(err) {
		return nil, errRoundNotFound
	}
	return &r, err
}

var errFinalOneQuestion = httpx.Conflict("final_one_question", "В финальном раунде у каждой темы ровно один вопрос")

func validKind(kind string) (string, error) {
	switch kind {
	case "", RoundNormal:
		return RoundNormal, nil
	case RoundFinal:
		return RoundFinal, nil
	}
	return "", httpx.BadRequest("invalid_kind", "Тип раунда: normal или final")
}

func (s *Store) CreateRound(packID, name, kind string) (*Round, error) {
	db, err := s.writable(packID)
	if err != nil {
		return nil, err
	}
	if name, err = cleanName(name, "name", 100); err != nil {
		return nil, err
	}
	if kind, err = validKind(kind); err != nil {
		return nil, err
	}
	res, err := db.Exec(`INSERT INTO rounds(position, name, kind) VALUES((SELECT coalesce(max(position)+1,0) FROM rounds), ?, ?)`, name, kind)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	s.touch(db)
	return s.getRound(db, id)
}

func (s *Store) UpdateRound(packID string, id int64, name *string, pos *int, kind *string) (*Round, error) {
	db, err := s.writable(packID)
	if err != nil {
		return nil, err
	}
	if _, err := s.getRound(db, id); err != nil {
		return nil, err
	}
	err = withTx(db, func(tx *sql.Tx) error {
		if kind != nil {
			k, err := validKind(*kind)
			if err != nil {
				return err
			}
			if k == RoundFinal {
				var crowded int
				if err := tx.QueryRow(`SELECT count(*) FROM (SELECT c.id FROM categories c JOIN questions q ON q.category_id=c.id
					WHERE c.round_id=? GROUP BY c.id HAVING count(*) > 1)`, id).Scan(&crowded); err != nil {
					return err
				}
				if crowded > 0 {
					return errFinalOneQuestion
				}
			}
			if _, err := tx.Exec(`UPDATE rounds SET kind=? WHERE id=?`, k, id); err != nil {
				return err
			}
		}
		if name != nil {
			n, err := cleanName(*name, "name", 100)
			if err != nil {
				return err
			}
			if _, err := tx.Exec(`UPDATE rounds SET name=? WHERE id=?`, n, id); err != nil {
				return err
			}
		}
		if pos != nil {
			return reorder(tx, "rounds", "", nil, id, pos)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	s.touch(db)
	return s.getRound(db, id)
}

func (s *Store) DeleteRound(packID string, id int64) error {
	db, err := s.writable(packID)
	if err != nil {
		return err
	}
	if _, err := s.getRound(db, id); err != nil {
		return err
	}
	err = withTx(db, func(tx *sql.Tx) error {
		if _, err := tx.Exec(`DELETE FROM rounds WHERE id=?`, id); err != nil {
			return err
		}
		return reorder(tx, "rounds", "", nil, 0, nil)
	})
	if err == nil {
		s.touch(db)
	}
	return err
}

// ---- categories ----

func (s *Store) getCategory(db *sql.DB, id int64) (*Category, error) {
	c := Category{Questions: []Question{}}
	err := db.QueryRow(`SELECT id, round_id, position, name FROM categories WHERE id=?`, id).Scan(&c.ID, &c.RoundID, &c.Position, &c.Name)
	if isNoRows(err) {
		return nil, errCategoryNotFound
	}
	return &c, err
}

func (s *Store) CreateCategory(packID string, roundID int64, name string) (*Category, error) {
	db, err := s.writable(packID)
	if err != nil {
		return nil, err
	}
	if _, err := s.getRound(db, roundID); err != nil {
		return nil, err
	}
	if name, err = cleanName(name, "name", 100); err != nil {
		return nil, err
	}
	var n int
	if err := db.QueryRow(`SELECT count(*) FROM categories WHERE round_id=?`, roundID).Scan(&n); err != nil {
		return nil, err
	}
	if n >= MaxCategories {
		return nil, httpx.Conflict("too_many_categories", "В раунде может быть не больше 10 категорий")
	}
	res, err := db.Exec(`INSERT INTO categories(round_id, position, name) VALUES(?, ?, ?)`, roundID, n, name)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	s.touch(db)
	return s.getCategory(db, id)
}

func (s *Store) UpdateCategory(packID string, id int64, name *string, pos *int) (*Category, error) {
	db, err := s.writable(packID)
	if err != nil {
		return nil, err
	}
	c, err := s.getCategory(db, id)
	if err != nil {
		return nil, err
	}
	err = withTx(db, func(tx *sql.Tx) error {
		if name != nil {
			n, err := cleanName(*name, "name", 100)
			if err != nil {
				return err
			}
			if _, err := tx.Exec(`UPDATE categories SET name=? WHERE id=?`, n, id); err != nil {
				return err
			}
		}
		if pos != nil {
			return reorder(tx, "categories", "round_id=?", []any{c.RoundID}, id, pos)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	s.touch(db)
	return s.getCategory(db, id)
}

func (s *Store) DeleteCategory(packID string, id int64) error {
	db, err := s.writable(packID)
	if err != nil {
		return err
	}
	c, err := s.getCategory(db, id)
	if err != nil {
		return err
	}
	err = withTx(db, func(tx *sql.Tx) error {
		if _, err := tx.Exec(`DELETE FROM categories WHERE id=?`, id); err != nil {
			return err
		}
		return reorder(tx, "categories", "round_id=?", []any{c.RoundID}, 0, nil)
	})
	if err == nil {
		s.touch(db)
	}
	return err
}

// ---- questions ----

const questionCols = `id, category_id, position, value, question, answer, comment, reading_seconds`

func (s *Store) getQuestion(db *sql.DB, id int64) (*Question, error) {
	q, err := scanQuestion(db.QueryRow(`SELECT `+questionCols+` FROM questions WHERE id=?`, id))
	if isNoRows(err) {
		return nil, errQuestionNotFound
	}
	return q, err
}

func validateQuestion(in QuestionInput) error {
	if in.Value != nil && (*in.Value < 0 || *in.Value > 1_000_000) {
		return httpx.BadRequest("invalid_value", "Стоимость должна быть от 0 до 1 000 000")
	}
	if in.ReadingSeconds != nil && *in.ReadingSeconds != nil {
		if v := **in.ReadingSeconds; v < 1 || v > 120 {
			return httpx.BadRequest("invalid_reading_seconds", "Время чтения должно быть от 1 до 120 секунд")
		}
	}
	for _, p := range []*string{in.Question, in.Answer, in.Comment} {
		if p != nil && len(*p) > 20_000 {
			return httpx.BadRequest("too_long", "Текст слишком длинный (максимум 20 000 символов)")
		}
	}
	return nil
}

func (s *Store) CreateQuestion(packID string, categoryID int64, in QuestionInput) (*Question, error) {
	db, err := s.writable(packID)
	if err != nil {
		return nil, err
	}
	if _, err := s.getCategory(db, categoryID); err != nil {
		return nil, err
	}
	if err := validateQuestion(in); err != nil {
		return nil, err
	}
	var n int
	if err := db.QueryRow(`SELECT count(*) FROM questions WHERE category_id=?`, categoryID).Scan(&n); err != nil {
		return nil, err
	}
	var kind string
	if err := db.QueryRow(`SELECT r.kind FROM rounds r JOIN categories c ON c.round_id=r.id WHERE c.id=?`, categoryID).Scan(&kind); err != nil {
		return nil, err
	}
	if kind == RoundFinal && n > 0 {
		return nil, errFinalOneQuestion
	}
	value := 100 * (n + 1)
	if kind == RoundFinal {
		value = 0
	}
	if in.Value != nil {
		value = *in.Value
	}
	str := func(p *string) string {
		if p == nil {
			return ""
		}
		return *p
	}
	var rs any
	if in.ReadingSeconds != nil && *in.ReadingSeconds != nil {
		rs = **in.ReadingSeconds
	}
	res, err := db.Exec(`INSERT INTO questions(category_id, position, value, question, answer, comment, reading_seconds) VALUES(?,?,?,?,?,?,?)`,
		categoryID, n, value, str(in.Question), str(in.Answer), str(in.Comment), rs)
	if err != nil {
		return nil, err
	}
	id, _ := res.LastInsertId()
	s.touch(db)
	return s.getQuestion(db, id)
}

func (s *Store) UpdateQuestion(packID string, id int64, in QuestionInput) (*Question, error) {
	db, err := s.writable(packID)
	if err != nil {
		return nil, err
	}
	q, err := s.getQuestion(db, id)
	if err != nil {
		return nil, err
	}
	if err := validateQuestion(in); err != nil {
		return nil, err
	}
	err = withTx(db, func(tx *sql.Tx) error {
		set := func(col string, v any) error {
			_, err := tx.Exec(`UPDATE questions SET `+col+`=? WHERE id=?`, v, id)
			return err
		}
		if in.Value != nil {
			if err := set("value", *in.Value); err != nil {
				return err
			}
		}
		if in.Question != nil {
			if err := set("question", *in.Question); err != nil {
				return err
			}
		}
		if in.Answer != nil {
			if err := set("answer", *in.Answer); err != nil {
				return err
			}
		}
		if in.Comment != nil {
			if err := set("comment", *in.Comment); err != nil {
				return err
			}
		}
		if in.ReadingSeconds != nil {
			var v any
			if *in.ReadingSeconds != nil {
				v = **in.ReadingSeconds
			}
			if err := set("reading_seconds", v); err != nil {
				return err
			}
		}
		if in.Position != nil {
			return reorder(tx, "questions", "category_id=?", []any{q.CategoryID}, id, in.Position)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	s.touch(db)
	return s.getQuestion(db, id)
}

func (s *Store) DeleteQuestion(packID string, id int64) error {
	db, err := s.writable(packID)
	if err != nil {
		return err
	}
	q, err := s.getQuestion(db, id)
	if err != nil {
		return err
	}
	err = withTx(db, func(tx *sql.Tx) error {
		if _, err := tx.Exec(`DELETE FROM questions WHERE id=?`, id); err != nil {
			return err
		}
		return reorder(tx, "questions", "category_id=?", []any{q.CategoryID}, 0, nil)
	})
	if err == nil {
		s.touch(db)
	}
	return err
}

// ---- media ----

type Media struct {
	Name string `json:"name"`
	Mime string `json:"mime"`
	Size int64  `json:"size"`
	URL  string `json:"url"`
}

func (s *Store) ListMedia(id string) ([]Media, error) {
	dir := filepath.Join(s.packDir(id), mediaDir)
	entries, err := os.ReadDir(dir)
	if os.IsNotExist(err) {
		return []Media{}, nil
	}
	if err != nil {
		return nil, err
	}
	out := []Media{}
	for _, e := range entries {
		if e.IsDir() || !ValidMediaName(e.Name()) {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		out = append(out, Media{Name: e.Name(), Mime: MimeOf(e.Name()), Size: info.Size(), URL: MediaURL(id, e.Name())})
	}
	return out, nil
}
