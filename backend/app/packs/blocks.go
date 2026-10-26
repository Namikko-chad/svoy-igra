package packs

import (
	"encoding/json"
	"net/url"
	"path"
	"regexp"
	"strings"
)

// Block is one piece of a question as clients render it: a markdown text run
// or a single media item. See docs/<lang>/05-protocol.md §3.
type Block struct {
	Type     string `json:"type"` // text | image | video | audio
	Markdown string `json:"markdown,omitempty"`
	URL      string `json:"url,omitempty"`
	Alt      string `json:"alt,omitempty"`
}

// MarshalJSON emits {type, markdown} for text and {type, url, alt} for media.
func (b Block) MarshalJSON() ([]byte, error) {
	if b.Type == "text" {
		return json.Marshal(struct {
			Type     string `json:"type"`
			Markdown string `json:"markdown"`
		}{b.Type, b.Markdown})
	}
	return json.Marshal(struct {
		Type string `json:"type"`
		URL  string `json:"url"`
		Alt  string `json:"alt"`
	}{b.Type, b.URL, b.Alt})
}

var mediaRef = regexp.MustCompile(`!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)`)

var (
	videoExt = map[string]bool{"mp4": true, "webm": true, "mov": true, "m4v": true, "mkv": true}
	audioExt = map[string]bool{"mp3": true, "ogg": true, "oga": true, "wav": true, "m4a": true, "aac": true, "flac": true, "opus": true}
)

// MediaKind returns image, video or audio for a file name or URL.
func MediaKind(src string) string {
	if i := strings.IndexAny(src, "?#"); i >= 0 {
		src = src[:i]
	}
	ext := strings.TrimPrefix(strings.ToLower(path.Ext(src)), ".")
	switch {
	case videoExt[ext]:
		return "video"
	case audioExt[ext]:
		return "audio"
	default:
		return "image"
	}
}

// MediaURL is the public URL of a pack media file.
func MediaURL(packID, name string) string {
	return "/api/packs/" + url.PathEscape(packID) + "/media/" + url.PathEscape(name)
}

// SplitBlocks turns question markdown into blocks: every image-syntax
// reference becomes a media block, the text between becomes text blocks.
func SplitBlocks(packID, md string) []Block {
	blocks := []Block{}
	addText := func(s string) {
		if s = strings.TrimSpace(s); s != "" {
			blocks = append(blocks, Block{Type: "text", Markdown: s})
		}
	}
	last := 0
	for _, m := range mediaRef.FindAllStringSubmatchIndex(md, -1) {
		addText(md[last:m[0]])
		alt := md[m[2]:m[3]]
		src := md[m[4]:m[5]]
		u := src
		if name, ok := strings.CutPrefix(src, "media:"); ok {
			u = MediaURL(packID, name)
		}
		blocks = append(blocks, Block{Type: MediaKind(src), URL: u, Alt: alt})
		last = m[1]
	}
	addText(md[last:])
	return blocks
}
