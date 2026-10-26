package game

import (
	"encoding/json"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"

	"svoy-igra/app/httpx"
)

// AvatarFileRe matches the names the server gives avatar files.
var AvatarFileRe = regexp.MustCompile(`^[a-f0-9]{16}\.(png|jpg|webp|gif)$`)

func (e *Engine) avatarURL(file string) *string {
	if file == "" {
		return nil
	}
	return ptr("/api/games/" + e.id + "/avatars/" + file)
}

func (e *Engine) avatarExists(file string) bool {
	if file == "" || !AvatarFileRe.MatchString(file) || e.avatarDir == "" {
		return false
	}
	_, err := os.Stat(filepath.Join(e.avatarDir, file))
	return err == nil
}

func (e *Engine) dropAvatarFile(file string) {
	if file == "" || !AvatarFileRe.MatchString(file) {
		return
	}
	if err := os.Remove(filepath.Join(e.avatarDir, file)); err != nil && !os.IsNotExist(err) {
		slog.Warn("remove avatar", "file", file, "err", err)
	}
}

// AvatarDir is where this game's avatar files live.
func (e *Engine) AvatarDir() string { return e.avatarDir }

// AvatarPath resolves a served avatar file, or "".
func (e *Engine) AvatarPath(file string) string {
	e.mu.Lock()
	defer e.mu.Unlock()
	if !e.avatarExists(file) {
		return ""
	}
	return filepath.Join(e.avatarDir, file)
}

// SetAvatar sets (file != "") or clears the avatar of a player or of the
// host; the previous file is deleted. It returns the new URL.
func (e *Engine) SetAvatar(role Role, playerID, token, file string) (*string, error) {
	var url *string
	err := e.do(func() error {
		if e.closed {
			return ErrGameNotFound
		}
		var slot *string
		switch {
		case role == RolePlayer && e.player(playerID) != nil:
			slot = &e.player(playerID).Avatar
		case role == RoleHost && token == e.hostToken:
			slot = &e.hostAvatar
		default:
			return httpx.NewError(403, "forbidden", "Аватар могут ставить только игроки и ведущий")
		}
		if *slot != file {
			e.dropAvatarFile(*slot)
			*slot = file
		}
		url = e.avatarURL(file)
		e.changed(ScopeAll)
		return nil
	})
	return url, err
}

func (e *Engine) cmdClearAvatar(_ Role, _ string, data json.RawMessage) error {
	var in struct {
		PlayerID string `json:"playerId"`
	}
	if err := decode(data, &in); err != nil {
		return err
	}
	if in.PlayerID == "" {
		e.dropAvatarFile(e.hostAvatar)
		e.hostAvatar = ""
	} else {
		p := e.player(in.PlayerID)
		if p == nil {
			return errNotFound("Игрок не найден")
		}
		e.dropAvatarFile(p.Avatar)
		p.Avatar = ""
	}
	e.changed(ScopeAll)
	return nil
}
