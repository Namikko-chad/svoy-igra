package packs

import (
	"archive/zip"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"svoy-igra/app/httpx"
)

func invalidPack(msg string) error { return httpx.BadRequest("invalid_pack", msg) }

// Export writes the pack as a .dub archive to w.
func (s *Store) Export(id string, w io.Writer) error {
	db, err := s.db(id)
	if err != nil {
		return err
	}
	// A consistent copy of the database, independent of the live handle.
	tmpDir, err := os.MkdirTemp(s.tmp, "dub-export-*")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmpDir)
	snapshot := filepath.Join(tmpDir, dbFile)
	if _, err := db.Exec(`VACUUM INTO ?`, snapshot); err != nil {
		return fmt.Errorf("snapshot pack db: %w", err)
	}

	zw := zip.NewWriter(w)
	if err := addFile(zw, dbFile, snapshot, zip.Deflate); err != nil {
		return err
	}
	media, err := s.ListMedia(id)
	if err != nil {
		return err
	}
	for _, m := range media {
		if err := addFile(zw, mediaDir+"/"+m.Name, filepath.Join(s.packDir(id), mediaDir, m.Name), zip.Store); err != nil {
			return err
		}
	}
	return zw.Close()
}

func addFile(zw *zip.Writer, name, path string, method uint16) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		return err
	}
	h, err := zip.FileInfoHeader(info)
	if err != nil {
		return err
	}
	h.Name = name
	h.Method = method
	dst, err := zw.CreateHeader(h)
	if err != nil {
		return err
	}
	_, err = io.Copy(dst, f)
	return err
}

// Import unpacks a .dub archive (already saved at path) into a new pack.
func (s *Store) Import(path string) (*Summary, error) {
	zr, err := zip.OpenReader(path)
	if err != nil {
		return nil, invalidPack("Файл не является архивом .dub")
	}
	defer zr.Close()

	var total uint64
	var dbEntry *zip.File
	var media []*zip.File
	for _, f := range zr.File {
		name := f.Name
		switch {
		case name == dbFile:
			dbEntry = f
		case name == mediaDir+"/" && f.FileInfo().IsDir():
			continue
		case strings.HasPrefix(name, mediaDir+"/"):
			base := strings.TrimPrefix(name, mediaDir+"/")
			if !ValidMediaName(base) {
				return nil, invalidPack("Недопустимое имя медиафайла в архиве: " + name)
			}
			media = append(media, f)
		default:
			return nil, invalidPack("Неожиданный файл в архиве: " + name)
		}
		total += f.UncompressedSize64
		if total > uint64(s.maxUnpack) {
			return nil, invalidPack("Распакованный пак слишком большой")
		}
	}
	if dbEntry == nil {
		return nil, invalidPack("В архиве нет pack.sqlite")
	}

	id := newID()
	dir := s.packDir(id)
	ok := false
	defer func() {
		if !ok {
			s.forget(id)
			_ = os.RemoveAll(dir)
		}
	}()
	if err := os.MkdirAll(filepath.Join(dir, mediaDir), 0o755); err != nil {
		return nil, err
	}
	if err := extract(dbEntry, filepath.Join(dir, dbFile), s.maxUnpack); err != nil {
		return nil, err
	}
	for _, f := range media {
		if err := extract(f, filepath.Join(dir, mediaDir, strings.TrimPrefix(f.Name, mediaDir+"/")), s.maxUnpack); err != nil {
			return nil, err
		}
	}

	if err := validateDB(filepath.Join(dir, dbFile)); err != nil {
		return nil, err
	}
	db, err := s.db(id)
	if err != nil {
		return nil, invalidPack("Не удалось открыть pack.sqlite")
	}
	m, err := meta(db)
	if err != nil {
		return nil, invalidPack("Повреждённая таблица meta")
	}
	if m["title"] == "" {
		_, _ = db.Exec(`INSERT OR REPLACE INTO meta(key,value) VALUES('title','Без названия')`)
	}
	if m["created_at"] == "" {
		_, _ = db.Exec(`INSERT OR REPLACE INTO meta(key,value) VALUES('created_at',?)`, strconv.FormatInt(nowMs(), 10))
	}
	s.touch(db)
	sum, err := s.Summary(id)
	if err != nil {
		return nil, err
	}
	ok = true
	return sum, nil
}

func extract(f *zip.File, dst string, limit int64) error {
	rc, err := f.Open()
	if err != nil {
		return invalidPack("Повреждённый архив: " + f.Name)
	}
	defer rc.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	n, err := io.Copy(out, io.LimitReader(rc, limit+1))
	if cerr := out.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return invalidPack("Повреждённый архив: " + f.Name)
	}
	if n > limit {
		return invalidPack("Распакованный пак слишком большой")
	}
	return nil
}

// validateDB checks the format version before the store opens the file
// (opening applies the schema, which must not mask a foreign database).
func validateDB(path string) error {
	db, err := openRaw(path)
	if err != nil {
		return invalidPack("pack.sqlite не является базой SQLite")
	}
	defer db.Close()
	var v string
	if err := db.QueryRow(`SELECT value FROM meta WHERE key='format_version'`).Scan(&v); err != nil {
		return invalidPack("pack.sqlite не похож на пак вопросов (нет meta.format_version)")
	}
	if v != formatVersion {
		return invalidPack("Неподдерживаемая версия формата пака: " + v)
	}
	for _, t := range []string{"rounds", "categories", "questions"} {
		var n int
		if err := db.QueryRow(`SELECT count(*) FROM sqlite_master WHERE type='table' AND name=?`, t).Scan(&n); err != nil || n == 0 {
			return invalidPack("В pack.sqlite нет таблицы " + t)
		}
	}
	return nil
}

// Copy makes an unlocked copy of a pack (database and media) under a new title.
func (s *Store) Copy(id, title string) (*Pack, error) {
	title, err := cleanName(title, "title", 200)
	if err != nil {
		return nil, err
	}
	db, err := s.db(id)
	if err != nil {
		return nil, err
	}
	newIDv := newID()
	dir := s.packDir(newIDv)
	ok := false
	defer func() {
		if !ok {
			s.forget(newIDv)
			_ = os.RemoveAll(dir)
		}
	}()
	if err := os.MkdirAll(filepath.Join(dir, mediaDir), 0o755); err != nil {
		return nil, err
	}
	if _, err := db.Exec(`VACUUM INTO ?`, filepath.Join(dir, dbFile)); err != nil {
		return nil, fmt.Errorf("copy pack db: %w", err)
	}
	media, err := s.ListMedia(id)
	if err != nil {
		return nil, err
	}
	for _, m := range media {
		if err := copyFile(filepath.Join(s.packDir(id), mediaDir, m.Name), filepath.Join(dir, mediaDir, m.Name)); err != nil {
			return nil, err
		}
	}
	cdb, err := s.db(newIDv)
	if err != nil {
		return nil, err
	}
	now := strconv.FormatInt(nowMs(), 10)
	for k, v := range map[string]string{"title": title, "locked": "0", "created_at": now, "updated_at": now} {
		if _, err := cdb.Exec(`INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)`, k, v); err != nil {
			return nil, err
		}
	}
	p, err := s.Get(newIDv)
	if err != nil {
		return nil, err
	}
	ok = true
	return p, nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}
