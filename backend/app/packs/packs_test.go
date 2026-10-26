package packs

import (
	"archive/zip"
	"os"
	"path/filepath"
	"reflect"
	"testing"
)

func TestSplitBlocks(t *testing.T) {
	got := SplitBlocks("abc123def456", "Кто это?\n\n![фото](media:a b.jpg)\nи ещё ![](media:clip.MP4) конец ![](https://x.org/s.mp3?x=1)")
	want := []Block{
		{Type: "text", Markdown: "Кто это?\n\n![фото](media:a b.jpg)\nи ещё"},
		{Type: "video", URL: "/api/packs/abc123def456/media/clip.MP4"},
		{Type: "text", Markdown: "конец"},
		{Type: "audio", URL: "https://x.org/s.mp3?x=1"},
	}
	// "a b.jpg" has a space, which is not a valid link destination: stays text.
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %#v", got)
	}
	if b := SplitBlocks("p", "   "); len(b) != 0 {
		t.Fatalf("empty: %#v", b)
	}
	if b := SplitBlocks("p", "![x](media:k.png)"); len(b) != 1 || b[0].Type != "image" || b[0].Alt != "x" {
		t.Fatalf("single: %#v", b)
	}
}

func TestSanitizeMediaName(t *testing.T) {
	for in, want := range map[string]string{
		"Фото кота.JPG":    "foto_kota.JPG",
		"../../etc/passwd": "passwd",
		".hidden":          "hidden",
		"съёмка №1.mp4":    "semka__1.mp4",
	} {
		if got := SanitizeMediaName(in); got != want || !ValidMediaName(got) {
			t.Errorf("%q → %q, want %q", in, got, want)
		}
	}
}

func TestReorder(t *testing.T) {
	s, err := NewStore(t.TempDir(), "", 1<<20)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	p, _ := s.Create("P")
	r, _ := s.CreateRound(p.ID, "R", "")
	c, _ := s.CreateCategory(p.ID, r.ID, "C")
	var ids []int64
	for range 3 {
		q, err := s.CreateQuestion(p.ID, c.ID, QuestionInput{})
		if err != nil {
			t.Fatal(err)
		}
		ids = append(ids, q.ID)
	}
	pos := 0
	if _, err := s.UpdateQuestion(p.ID, ids[2], QuestionInput{Position: &pos}); err != nil {
		t.Fatal(err)
	}
	if err := s.DeleteQuestion(p.ID, ids[0]); err != nil {
		t.Fatal(err)
	}
	full, _ := s.Get(p.ID)
	qs := full.Rounds[0].Categories[0].Questions
	if len(qs) != 2 || qs[0].ID != ids[2] || qs[0].Position != 0 || qs[1].ID != ids[1] || qs[1].Position != 1 {
		t.Fatalf("order %+v", qs)
	}
	for range 9 {
		if _, err := s.CreateCategory(p.ID, r.ID, "x"); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := s.CreateCategory(p.ID, r.ID, "11th"); err == nil {
		t.Fatal("11th category accepted")
	}
}

func TestImportRejectsTraversal(t *testing.T) {
	s, _ := NewStore(t.TempDir(), "", 1<<20)
	defer s.Close()
	path := filepath.Join(t.TempDir(), "evil.dub")
	f, _ := os.Create(path)
	zw := zip.NewWriter(f)
	w, _ := zw.Create("media/../../evil.sh")
	_, _ = w.Write([]byte("x"))
	_ = zw.Close()
	_ = f.Close()
	if _, err := s.Import(path); err == nil {
		t.Fatal("traversal accepted")
	}
	list, _ := s.List()
	if len(list) != 0 {
		t.Fatal("a rejected import left a pack behind")
	}
}
