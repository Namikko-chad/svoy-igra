// Package packs is the question-pack library: one directory per pack under
// DATA_DIR/packs/<id>/ holding pack.sqlite and media/. It also reads and
// writes the portable .dub archive (a ZIP of the same two things).
package packs

import (
	"database/sql"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"sync"
	"time"

	"svoy-igra/app/httpx"
	"svoy-igra/app/ids"

	_ "modernc.org/sqlite"
)

const (
	dbFile        = "pack.sqlite"
	mediaDir      = "media"
	formatVersion = "1"
	// MaxCategories is the per-round category limit.
	MaxCategories = 10
)

var (
	ErrNotFound = httpx.NotFound("Пак не найден")
	packIDRe    = regexp.MustCompile(`^[a-f0-9]{12}$`)
)

const schema = `
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS rounds (
  id INTEGER PRIMARY KEY, position INTEGER NOT NULL, name TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'normal');
CREATE TABLE IF NOT EXISTS categories (
  id INTEGER PRIMARY KEY,
  round_id INTEGER NOT NULL REFERENCES rounds(id) ON DELETE CASCADE,
  position INTEGER NOT NULL, name TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS questions (
  id INTEGER PRIMARY KEY,
  category_id INTEGER NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  position INTEGER NOT NULL, value INTEGER NOT NULL,
  question TEXT NOT NULL, answer TEXT NOT NULL, comment TEXT NOT NULL DEFAULT '',
  reading_seconds INTEGER);
CREATE INDEX IF NOT EXISTS categories_round ON categories(round_id, position);
CREATE INDEX IF NOT EXISTS questions_category ON questions(category_id, position);
`

// Store owns the library directory. Every pack has its own single-connection
// database handle, opened lazily and cached.
type Store struct {
	dir       string
	tmp       string // staging dir for exports
	maxUnpack int64

	mu  sync.Mutex
	dbs map[string]*sql.DB
}

// NewStore opens the library in dataDir/packs; tmpDir stages exports
// (empty: the system temp dir).
func NewStore(dataDir, tmpDir string, maxUnpack int64) (*Store, error) {
	dir := filepath.Join(dataDir, "packs")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	return &Store{dir: dir, tmp: tmpDir, maxUnpack: maxUnpack, dbs: map[string]*sql.DB{}}, nil
}

// Close releases every open database.
func (s *Store) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	for id, db := range s.dbs {
		_ = db.Close()
		delete(s.dbs, id)
	}
}

func (s *Store) packDir(id string) string { return filepath.Join(s.dir, id) }

func (s *Store) MediaPath(id, name string) (string, error) {
	if !packIDRe.MatchString(id) || !ValidMediaName(name) {
		return "", ErrNotFound
	}
	return filepath.Join(s.packDir(id), mediaDir, name), nil
}

func openDB(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", "file:"+path+"?_pragma=foreign_keys(1)&_pragma=busy_timeout(5000)&_pragma=journal_mode(DELETE)")
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(schema); err != nil {
		_ = db.Close()
		return nil, fmt.Errorf("apply schema: %w", err)
	}
	// Packs written before rounds.kind existed get the column (all rounds normal).
	var hasKind int
	if err := db.QueryRow(`SELECT count(*) FROM pragma_table_info('rounds') WHERE name='kind'`).Scan(&hasKind); err != nil {
		_ = db.Close()
		return nil, err
	}
	if hasKind == 0 {
		if _, err := db.Exec(`ALTER TABLE rounds ADD COLUMN kind TEXT NOT NULL DEFAULT 'normal'`); err != nil {
			_ = db.Close()
			return nil, fmt.Errorf("add rounds.kind: %w", err)
		}
	}
	return db, nil
}

// openRaw opens a database file without touching its schema.
func openRaw(path string) (*sql.DB, error) {
	db, err := sql.Open("sqlite", "file:"+path+"?mode=ro")
	if err != nil {
		return nil, err
	}
	if err := db.Ping(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return db, nil
}

// db returns the open handle for a pack, or ErrNotFound.
func (s *Store) db(id string) (*sql.DB, error) {
	if !packIDRe.MatchString(id) {
		return nil, ErrNotFound
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if db, ok := s.dbs[id]; ok {
		return db, nil
	}
	path := filepath.Join(s.packDir(id), dbFile)
	if _, err := os.Stat(path); err != nil {
		return nil, ErrNotFound
	}
	db, err := openDB(path)
	if err != nil {
		return nil, err
	}
	s.dbs[id] = db
	return db, nil
}

func (s *Store) forget(id string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if db, ok := s.dbs[id]; ok {
		_ = db.Close()
		delete(s.dbs, id)
	}
}

func nowMs() int64 { return time.Now().UnixMilli() }

func newID() string { return ids.Hex(6) }

// Create makes an empty pack.
func (s *Store) Create(title string) (*Pack, error) {
	id := newID()
	if err := os.MkdirAll(filepath.Join(s.packDir(id), mediaDir), 0o755); err != nil {
		return nil, err
	}
	db, err := openDB(filepath.Join(s.packDir(id), dbFile))
	if err != nil {
		return nil, err
	}
	now := strconv.FormatInt(nowMs(), 10)
	for k, v := range map[string]string{
		"format_version": formatVersion, "title": title, "author": "", "description": "",
		"created_at": now, "updated_at": now,
	} {
		if _, err := db.Exec(`INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)`, k, v); err != nil {
			_ = db.Close()
			return nil, err
		}
	}
	s.mu.Lock()
	s.dbs[id] = db
	s.mu.Unlock()
	return s.Get(id)
}

var ErrLocked = httpx.Conflict("pack_locked", "Пак заблокирован: его нельзя изменить или удалить. Отредактируйте копию.")

func isLocked(db *sql.DB) (bool, error) {
	var v string
	err := db.QueryRow(`SELECT value FROM meta WHERE key='locked'`).Scan(&v)
	if isNoRows(err) {
		return false, nil
	}
	return v == "1", err
}

// writable returns the pack's handle, or ErrLocked for a locked pack.
func (s *Store) writable(id string) (*sql.DB, error) {
	db, err := s.db(id)
	if err != nil {
		return nil, err
	}
	locked, err := isLocked(db)
	if err != nil {
		return nil, err
	}
	if locked {
		return nil, ErrLocked
	}
	return db, nil
}

// SetLocked locks or (operator only) unlocks a pack.
func (s *Store) SetLocked(id string, locked bool) error {
	db, err := s.db(id)
	if err != nil {
		return err
	}
	v := "0"
	if locked {
		v = "1"
	}
	_, err = db.Exec(`INSERT OR REPLACE INTO meta(key,value) VALUES('locked',?)`, v)
	return err
}

// Delete removes a pack from disk.
func (s *Store) Delete(id string) error {
	if _, err := s.writable(id); err != nil {
		return err
	}
	s.forget(id)
	return os.RemoveAll(s.packDir(id))
}

// List returns every pack, newest update first. A broken pack is skipped.
func (s *Store) List() ([]Summary, error) {
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return nil, err
	}
	out := []Summary{}
	for _, e := range entries {
		if !e.IsDir() || !packIDRe.MatchString(e.Name()) {
			continue
		}
		sum, err := s.Summary(e.Name())
		if err != nil {
			continue
		}
		out = append(out, *sum)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].UpdatedAt > out[j].UpdatedAt })
	return out, nil
}

// Exists reports whether a pack is in the library.
func (s *Store) Exists(id string) bool {
	_, err := s.db(id)
	return err == nil
}

func (s *Store) touch(db *sql.DB) {
	_, _ = db.Exec(`INSERT OR REPLACE INTO meta(key,value) VALUES('updated_at',?)`, strconv.FormatInt(nowMs(), 10))
}

func dirSize(dir string) int64 {
	var n int64
	_ = filepath.WalkDir(dir, func(_ string, d os.DirEntry, err error) error {
		if err == nil && !d.IsDir() {
			if info, err := d.Info(); err == nil {
				n += info.Size()
			}
		}
		return nil
	})
	return n
}

func isNoRows(err error) bool { return errors.Is(err, sql.ErrNoRows) }
