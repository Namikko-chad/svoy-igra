package packs

import (
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"svoy-igra/app/httpx"
)

var mediaNameRe = regexp.MustCompile(`^[A-Za-z0-9._-]{1,128}$`)

// ValidMediaName reports whether name is an allowed media file name.
func ValidMediaName(name string) bool {
	return mediaNameRe.MatchString(name) && !strings.HasPrefix(name, ".")
}

var translit = map[rune]string{
	'а': "a", 'б': "b", 'в': "v", 'г': "g", 'д': "d", 'е': "e", 'ё': "e", 'ж': "zh", 'з': "z", 'и': "i",
	'й': "y", 'к': "k", 'л': "l", 'м': "m", 'н': "n", 'о': "o", 'п': "p", 'р': "r", 'с': "s", 'т': "t",
	'у': "u", 'ф': "f", 'х': "h", 'ц': "c", 'ч': "ch", 'ш': "sh", 'щ': "sch", 'ъ': "", 'ы': "y", 'ь': "",
	'э': "e", 'ю': "yu", 'я': "ya",
}

// SanitizeMediaName turns an uploaded file name into a valid media name:
// Cyrillic is transliterated, everything else outside [A-Za-z0-9._-] becomes '_'.
func SanitizeMediaName(name string) string {
	name = filepath.Base(strings.ReplaceAll(name, `\`, "/"))
	var b strings.Builder
	for _, r := range name {
		lower := []rune(strings.ToLower(string(r)))[0]
		switch {
		case r < 128 && (r == '.' || r == '-' || r == '_' || r >= '0' && r <= '9' || r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z'):
			b.WriteRune(r)
		default:
			if t, ok := translit[lower]; ok {
				b.WriteString(t)
				continue
			}
			b.WriteByte('_')
		}
	}
	out := strings.TrimLeft(b.String(), ".")
	if len(out) > 128 {
		ext := filepath.Ext(out)
		if len(ext) > 16 {
			ext = ""
		}
		out = out[:128-len(ext)] + ext
	}
	if out == "" {
		out = "file"
	}
	return out
}

// MimeOf guesses a MIME type from the file extension.
func MimeOf(name string) string {
	ext := strings.ToLower(filepath.Ext(name))
	switch ext {
	case ".mp3":
		return "audio/mpeg"
	case ".m4a":
		return "audio/mp4"
	case ".ogg", ".oga", ".opus":
		return "audio/ogg"
	case ".flac":
		return "audio/flac"
	case ".wav":
		return "audio/wav"
	case ".aac":
		return "audio/aac"
	case ".mp4", ".m4v":
		return "video/mp4"
	case ".webm":
		return "video/webm"
	case ".mov":
		return "video/quicktime"
	case ".mkv":
		return "video/x-matroska"
	}
	if t := mime.TypeByExtension(ext); t != "" {
		return t
	}
	return "application/octet-stream"
}

var errTooLarge = httpx.NewError(413, "too_large", "Файл слишком большой")

// SaveMedia stores r as media/name (replacing an existing file).
func (s *Store) SaveMedia(id, name string, r io.Reader, limit int64) (*Media, error) {
	db, err := s.writable(id)
	if err != nil {
		return nil, err
	}
	if !ValidMediaName(name) {
		return nil, httpx.BadRequest("invalid_name", "Недопустимое имя файла: разрешены латинские буквы, цифры, '.', '-', '_'")
	}
	dir := filepath.Join(s.packDir(id), mediaDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	tmp, err := os.CreateTemp(dir, ".upload-*")
	if err != nil {
		return nil, err
	}
	defer os.Remove(tmp.Name())
	n, err := io.Copy(tmp, io.LimitReader(r, limit+1))
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		var mbe *http.MaxBytesError
		if errors.As(err, &mbe) {
			return nil, errTooLarge
		}
		return nil, err
	}
	if n > limit {
		return nil, errTooLarge
	}
	if err := os.Rename(tmp.Name(), filepath.Join(dir, name)); err != nil {
		return nil, err
	}
	s.touch(db)
	return &Media{Name: name, Mime: MimeOf(name), Size: n, URL: MediaURL(id, name)}, nil
}

func (s *Store) DeleteMedia(id, name string) error {
	db, err := s.writable(id)
	if err != nil {
		return err
	}
	p, err := s.MediaPath(id, name)
	if err != nil {
		return err
	}
	if err := os.Remove(p); err != nil {
		if os.IsNotExist(err) {
			return httpx.NotFound("Файл не найден")
		}
		return err
	}
	s.touch(db)
	return nil
}
