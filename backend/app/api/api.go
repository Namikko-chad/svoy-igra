// Package api holds the REST handlers (docs/<lang>/05-protocol.md §2).
package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"svoy-igra/app/config"
	"svoy-igra/app/game"
	"svoy-igra/app/httpx"
	"svoy-igra/app/ids"
	"svoy-igra/app/packs"
)

type API struct {
	cfg   *config.Config
	store *packs.Store
	games *game.Manager
}

func New(cfg *config.Config, store *packs.Store, games *game.Manager) *API {
	return &API{cfg: cfg, store: store, games: games}
}

// Register mounts every route on mux.
func (a *API) Register(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, _ *http.Request) {
		httpx.JSON(w, 200, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /api/info", a.info)
	mux.HandleFunc("GET /api/auth/me", a.me)
	mux.HandleFunc("GET /api/games", a.listGames)
	mux.HandleFunc("POST /api/games", a.createGame)
	mux.HandleFunc("GET /api/games/{pin}", a.getGame)
	mux.HandleFunc("POST /api/games/{pin}/join", a.joinGame)
	mux.HandleFunc("POST /api/games/{id}/watch", a.watchGame)
	mux.HandleFunc("GET /api/packs/{id}/media/{name}", a.serveMedia)
	mux.HandleFunc("GET /.well-known/assetlinks.json", a.assetLinks)
	mux.HandleFunc("POST /api/avatar", a.uploadAvatar)
	mux.HandleFunc("DELETE /api/avatar", a.deleteAvatar)
	mux.HandleFunc("GET /api/games/{id}/avatars/{file}", a.serveAvatar)

	host := a.requireAdmin
	mux.HandleFunc("GET /api/packs", host(a.listPacks))
	mux.HandleFunc("POST /api/packs", host(a.createPack))
	mux.HandleFunc("POST /api/packs/import", host(a.importPack))
	mux.HandleFunc("GET /api/packs/{id}", host(a.getPack))
	mux.HandleFunc("PATCH /api/packs/{id}", host(a.updatePack))
	mux.HandleFunc("DELETE /api/packs/{id}", host(a.deletePack))
	mux.HandleFunc("GET /api/packs/{id}/export", host(a.exportPack))
	mux.HandleFunc("POST /api/packs/{id}/copy", host(a.copyPack))
	mux.HandleFunc("POST /api/packs/{id}/lock", host(a.lockPack))
	mux.HandleFunc("POST /api/packs/{id}/rounds", host(a.createRound))
	mux.HandleFunc("PATCH /api/packs/{id}/rounds/{rid}", host(a.updateRound))
	mux.HandleFunc("DELETE /api/packs/{id}/rounds/{rid}", host(a.deleteRound))
	mux.HandleFunc("POST /api/packs/{id}/rounds/{rid}/categories", host(a.createCategory))
	mux.HandleFunc("PATCH /api/packs/{id}/categories/{cid}", host(a.updateCategory))
	mux.HandleFunc("DELETE /api/packs/{id}/categories/{cid}", host(a.deleteCategory))
	mux.HandleFunc("POST /api/packs/{id}/categories/{cid}/questions", host(a.createQuestion))
	mux.HandleFunc("PATCH /api/packs/{id}/questions/{qid}", host(a.updateQuestion))
	mux.HandleFunc("DELETE /api/packs/{id}/questions/{qid}", host(a.deleteQuestion))
	mux.HandleFunc("POST /api/packs/{id}/media", host(a.uploadMedia))
	mux.HandleFunc("DELETE /api/packs/{id}/media/{name}", host(a.deleteMedia))
	mux.HandleFunc("GET /api/game/export", host(a.exportGame))
	mux.HandleFunc("POST /api/game/import", host(a.importGame))

	mux.HandleFunc("/api/", func(w http.ResponseWriter, r *http.Request) {
		httpx.Fail(w, r, httpx.NotFound("Нет такого метода API"))
	})
}

// ---- auth ----

func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if t, ok := strings.CutPrefix(h, "Bearer "); ok {
		return strings.TrimSpace(t)
	}
	return ""
}

var errUnauthorized = httpx.NewError(401, "unauthorized", "Требуется вход")

type ctxKey struct{}

// requireAdmin admits an admin token of any game; the game is put in the
// request context for the game-file endpoints.
func (a *API) requireAdmin(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		e, role, _, ok := a.games.Resolve(bearer(r))
		if !ok {
			httpx.Fail(w, r, errUnauthorized)
			return
		}
		if role != game.RoleAdmin {
			httpx.Fail(w, r, httpx.NewError(403, "forbidden", "Доступно только администратору игры"))
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, e)))
	}
}

func gameOf(r *http.Request) *game.Engine { return r.Context().Value(ctxKey{}).(*game.Engine) }

func (a *API) info(w http.ResponseWriter, _ *http.Request) {
	var web any
	if a.cfg.WebURL != "" {
		web = a.cfg.WebURL
	}
	httpx.JSON(w, 200, map[string]any{"name": a.cfg.ServerName, "version": config.Version, "serverNow": time.Now().UnixMilli(), "webUrl": web})
}

// linkBase is where share links point: WEB_URL, else the web page that sent
// the request (Origin), else the address the request came to.
func (a *API) linkBase(r *http.Request) string {
	if a.cfg.WebURL != "" {
		return a.cfg.WebURL
	}
	if o := r.Header.Get("Origin"); strings.HasPrefix(o, "http://") || strings.HasPrefix(o, "https://") {
		return o
	}
	scheme := "http"
	if r.TLS != nil {
		scheme = "https"
	}
	if p := r.Header.Get("X-Forwarded-Proto"); p == "http" || p == "https" {
		scheme = p
	}
	host := r.Host
	if fh := r.Header.Get("X-Forwarded-Host"); fh != "" {
		host = strings.TrimSpace(strings.Split(fh, ",")[0])
	}
	return scheme + "://" + host
}

func (a *API) me(w http.ResponseWriter, r *http.Request) {
	token := bearer(r)
	if e, _, _, ok := a.games.Resolve(token); ok {
		if res, ok := e.Me(token); ok {
			httpx.JSON(w, 200, res)
			return
		}
	}
	httpx.Fail(w, r, errUnauthorized)
}

func (a *API) listGames(w http.ResponseWriter, _ *http.Request) {
	httpx.JSON(w, 200, a.games.List())
}

func (a *API) createGame(w http.ResponseWriter, r *http.Request) {
	var in struct {
		AdminPin string `json:"adminPin"`
		Title    string `json:"title"`
	}
	if err := httpx.Decode(r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := a.games.Create(in.Title, in.AdminPin, a.linkBase(r))
	respond(w, r, 201, res, err)
}

func (a *API) getGame(w http.ResponseWriter, r *http.Request) {
	e, err := a.games.ByPIN(r.PathValue("pin"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.JSON(w, 200, e.Info())
}

func (a *API) joinGame(w http.ResponseWriter, r *http.Request) {
	e, err := a.games.ByPIN(r.PathValue("pin"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	var in struct {
		Role     string `json:"role"`
		Name     string `json:"name"`
		AdminPin string `json:"adminPin"`
	}
	if err := httpx.Decode(r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := e.Join(game.Role(in.Role), in.Name, in.AdminPin)
	if errors.Is(err, game.ErrInvalidAdminPin) {
		time.Sleep(500 * time.Millisecond) // slows PIN guessing
	}
	respond(w, r, 200, res, err)
}

// watchGame lets a screen show a game from the public list without its PIN.
func (a *API) watchGame(w http.ResponseWriter, r *http.Request) {
	e, err := a.games.ByID(r.PathValue("id"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := e.Watch()
	respond(w, r, 200, res, err)
}

const maxAvatarBytes = 2 << 20

var avatarExt = map[string]string{"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp", "image/gif": "gif"}

func (a *API) uploadAvatar(w http.ResponseWriter, r *http.Request) {
	token := bearer(r)
	e, role, pid, ok := a.games.Resolve(token)
	if !ok {
		httpx.Fail(w, r, errUnauthorized)
		return
	}
	if role != game.RolePlayer && role != game.RoleHost {
		httpx.Fail(w, r, httpx.NewError(403, "forbidden", "Аватар могут ставить только игроки и ведущий"))
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxAvatarBytes+64<<10)
	file, _, err := r.FormFile("file")
	if err != nil {
		httpx.Fail(w, r, uploadErr(err))
		return
	}
	defer file.Close()
	data, err := io.ReadAll(io.LimitReader(file, maxAvatarBytes+1))
	if err != nil {
		httpx.Fail(w, r, uploadErr(err))
		return
	}
	if len(data) > maxAvatarBytes {
		httpx.Fail(w, r, httpx.NewError(413, "too_large", "Картинка больше 2 МБ"))
		return
	}
	ext, ok := avatarExt[http.DetectContentType(data)]
	if !ok {
		httpx.Fail(w, r, httpx.BadRequest("invalid_image", "Нужна картинка PNG, JPEG, WebP или GIF"))
		return
	}
	if err := os.MkdirAll(e.AvatarDir(), 0o755); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	name := ids.Hex(8) + "." + ext
	if err := os.WriteFile(filepath.Join(e.AvatarDir(), name), data, 0o644); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	url, err := e.SetAvatar(role, pid, token, name)
	if err != nil {
		_ = os.Remove(filepath.Join(e.AvatarDir(), name))
		httpx.Fail(w, r, err)
		return
	}
	httpx.JSON(w, 200, map[string]any{"avatarUrl": url})
}

func (a *API) deleteAvatar(w http.ResponseWriter, r *http.Request) {
	token := bearer(r)
	e, role, pid, ok := a.games.Resolve(token)
	if !ok {
		httpx.Fail(w, r, errUnauthorized)
		return
	}
	_, err := e.SetAvatar(role, pid, token, "")
	respond(w, r, 204, nil, err)
}

func (a *API) serveAvatar(w http.ResponseWriter, r *http.Request) {
	e, err := a.games.ByID(r.PathValue("id"))
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Аватар не найден"))
		return
	}
	path := e.AvatarPath(r.PathValue("file"))
	if path == "" {
		httpx.Fail(w, r, httpx.NotFound("Аватар не найден"))
		return
	}
	// File names change on every upload, so the content never changes.
	w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	http.ServeFile(w, r, path)
}

func (a *API) assetLinks(w http.ResponseWriter, r *http.Request) {
	if len(a.cfg.AndroidSHA256) == 0 {
		httpx.Fail(w, r, httpx.NotFound("App Links не настроены"))
		return
	}
	httpx.JSON(w, 200, []any{map[string]any{
		"relation": []string{"delegate_permission/common.handle_all_urls"},
		"target": map[string]any{
			"namespace":                "android_app",
			"package_name":             a.cfg.AndroidPkg,
			"sha256_cert_fingerprints": a.cfg.AndroidSHA256,
		},
	}})
}

// ---- packs ----

func (a *API) listPacks(w http.ResponseWriter, r *http.Request) {
	list, err := a.store.List()
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.JSON(w, 200, list)
}

func (a *API) createPack(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Title string `json:"title"`
	}
	if err := httpx.Decode(r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	in.Title = strings.TrimSpace(in.Title)
	if in.Title == "" {
		httpx.Fail(w, r, httpx.BadRequest("invalid_title", "Название не может быть пустым"))
		return
	}
	p, err := a.store.Create(in.Title)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.JSON(w, 201, p)
}

// saveUpload writes the multipart field "file" to a temp file and returns
// its path and original name. The caller removes the file.
func (a *API) saveUpload(w http.ResponseWriter, r *http.Request) (string, string, error) {
	r.Body = http.MaxBytesReader(w, r.Body, a.cfg.MaxUploadBytes()+1<<20)
	mr, err := r.MultipartReader()
	if err != nil {
		return "", "", httpx.BadRequest("invalid_upload", "Ожидается multipart/form-data с полем file")
	}
	for {
		part, err := mr.NextPart()
		if err == io.EOF {
			return "", "", httpx.BadRequest("invalid_upload", "В запросе нет поля file")
		}
		if err != nil {
			return "", "", uploadErr(err)
		}
		if part.FormName() != "file" {
			continue
		}
		tmp, err := os.CreateTemp(a.cfg.TempDir(), "upload-*")
		if err != nil {
			return "", "", err
		}
		_, err = io.Copy(tmp, part)
		if cerr := tmp.Close(); err == nil {
			err = cerr
		}
		if err != nil {
			os.Remove(tmp.Name())
			return "", "", uploadErr(err)
		}
		return tmp.Name(), part.FileName(), nil
	}
}

func uploadErr(err error) error {
	var mbe *http.MaxBytesError
	if errors.As(err, &mbe) {
		return httpx.NewError(413, "too_large", "Файл слишком большой")
	}
	return httpx.BadRequest("invalid_upload", "Загрузка прервана")
}

func (a *API) importPack(w http.ResponseWriter, r *http.Request) {
	path, _, err := a.saveUpload(w, r)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	defer os.Remove(path)
	sum, err := a.store.Import(path)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.JSON(w, 201, sum)
}

func (a *API) getPack(w http.ResponseWriter, r *http.Request) {
	p, err := a.store.Get(r.PathValue("id"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.JSON(w, 200, p)
}

func (a *API) updatePack(w http.ResponseWriter, r *http.Request) {
	var in packs.MetaInput
	if err := httpx.Decode(r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	sum, err := a.store.UpdateMeta(r.PathValue("id"), in)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.JSON(w, 200, sum)
}

func (a *API) deletePack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if a.games.PackInUse(id) {
		httpx.Fail(w, r, httpx.Conflict("pack_in_use", "Пак используется в одной из игр"))
		return
	}
	if err := a.store.Delete(id); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

func (a *API) copyPack(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Title string `json:"title"`
	}
	if err := httpx.Decode(r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	p, err := a.store.Copy(r.PathValue("id"), in.Title)
	respond(w, r, 201, p, err)
}

func (a *API) lockPack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if err := a.store.SetLocked(id, true); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	sum, err := a.store.Summary(id)
	respond(w, r, 200, sum, err)
}

var unsafeFileChars = regexp.MustCompile(`[\\/:*?"<>|\x00-\x1f]+`)

func attachment(w http.ResponseWriter, name string) {
	name = strings.TrimSpace(unsafeFileChars.ReplaceAllString(name, "_"))
	if name == "" {
		name = "file"
	}
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": name}))
	w.Header().Set("Access-Control-Expose-Headers", "Content-Disposition")
}

func (a *API) exportPack(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	sum, err := a.store.Summary(id)
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	// Build into a temp file first so a failure still yields a proper error.
	tmp, err := os.CreateTemp(a.cfg.TempDir(), "export-*.dub")
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	defer os.Remove(tmp.Name())
	defer tmp.Close()
	if err := a.store.Export(id, tmp); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	attachment(w, sum.Title+".dub")
	w.Header().Set("Content-Type", "application/octet-stream")
	http.ServeContent(w, r, "", time.UnixMilli(sum.UpdatedAt), tmp)
}

func intPath(r *http.Request, key string) (int64, error) {
	n, err := strconv.ParseInt(r.PathValue(key), 10, 64)
	if err != nil {
		return 0, httpx.NotFound("Не найдено")
	}
	return n, nil
}

type nameInput struct {
	Name     *string `json:"name"`
	Position *int    `json:"position"`
	Kind     *string `json:"kind"`
}

func (a *API) createRound(w http.ResponseWriter, r *http.Request) {
	var in nameInput
	if err := httpx.Decode(r, &in); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := a.store.CreateRound(r.PathValue("id"), deref(in.Name), deref(in.Kind))
	respond(w, r, 201, res, err)
}

func (a *API) updateRound(w http.ResponseWriter, r *http.Request) {
	id, err := intPath(r, "rid")
	var in nameInput
	if err == nil {
		err = httpx.Decode(r, &in)
	}
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := a.store.UpdateRound(r.PathValue("id"), id, in.Name, in.Position, in.Kind)
	respond(w, r, 200, res, err)
}

func (a *API) deleteRound(w http.ResponseWriter, r *http.Request) {
	id, err := intPath(r, "rid")
	if err == nil {
		err = a.store.DeleteRound(r.PathValue("id"), id)
	}
	respond(w, r, 204, nil, err)
}

func (a *API) createCategory(w http.ResponseWriter, r *http.Request) {
	rid, err := intPath(r, "rid")
	var in nameInput
	if err == nil {
		err = httpx.Decode(r, &in)
	}
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := a.store.CreateCategory(r.PathValue("id"), rid, deref(in.Name))
	respond(w, r, 201, res, err)
}

func (a *API) updateCategory(w http.ResponseWriter, r *http.Request) {
	id, err := intPath(r, "cid")
	var in nameInput
	if err == nil {
		err = httpx.Decode(r, &in)
	}
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := a.store.UpdateCategory(r.PathValue("id"), id, in.Name, in.Position)
	respond(w, r, 200, res, err)
}

func (a *API) deleteCategory(w http.ResponseWriter, r *http.Request) {
	id, err := intPath(r, "cid")
	if err == nil {
		err = a.store.DeleteCategory(r.PathValue("id"), id)
	}
	respond(w, r, 204, nil, err)
}

func (a *API) createQuestion(w http.ResponseWriter, r *http.Request) {
	cid, err := intPath(r, "cid")
	var in packs.QuestionInput
	if err == nil {
		err = httpx.Decode(r, &in)
	}
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := a.store.CreateQuestion(r.PathValue("id"), cid, in)
	respond(w, r, 201, res, err)
}

func (a *API) updateQuestion(w http.ResponseWriter, r *http.Request) {
	id, err := intPath(r, "qid")
	var in packs.QuestionInput
	if err == nil {
		err = httpx.Decode(r, &in)
	}
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	res, err := a.store.UpdateQuestion(r.PathValue("id"), id, in)
	respond(w, r, 200, res, err)
}

func (a *API) deleteQuestion(w http.ResponseWriter, r *http.Request) {
	id, err := intPath(r, "qid")
	if err == nil {
		err = a.store.DeleteQuestion(r.PathValue("id"), id)
	}
	respond(w, r, 204, nil, err)
}

func (a *API) uploadMedia(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !a.store.Exists(id) {
		httpx.Fail(w, r, packs.ErrNotFound)
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, a.cfg.MaxUploadBytes()+1<<20)
	mr, err := r.MultipartReader()
	if err != nil {
		httpx.Fail(w, r, httpx.BadRequest("invalid_upload", "Ожидается multipart/form-data с полем file"))
		return
	}
	name := ""
	for {
		part, err := mr.NextPart()
		if err == io.EOF {
			httpx.Fail(w, r, httpx.BadRequest("invalid_upload", "В запросе нет поля file"))
			return
		}
		if err != nil {
			httpx.Fail(w, r, uploadErr(err))
			return
		}
		switch part.FormName() {
		case "name":
			b, _ := io.ReadAll(io.LimitReader(part, 256))
			name = strings.TrimSpace(string(b))
		case "file":
			if name == "" {
				name = packs.SanitizeMediaName(part.FileName())
			}
			m, err := a.store.SaveMedia(id, name, part, a.cfg.MaxUploadBytes())
			if err != nil {
				var mbe *http.MaxBytesError
				if errors.As(err, &mbe) {
					err = uploadErr(err)
				}
				httpx.Fail(w, r, err)
				return
			}
			httpx.JSON(w, 201, m)
			return
		}
	}
}

func (a *API) deleteMedia(w http.ResponseWriter, r *http.Request) {
	respond(w, r, 204, nil, a.store.DeleteMedia(r.PathValue("id"), r.PathValue("name")))
}

func (a *API) serveMedia(w http.ResponseWriter, r *http.Request) {
	path, err := a.store.MediaPath(r.PathValue("id"), r.PathValue("name"))
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	f, err := os.Open(path)
	if err != nil {
		httpx.Fail(w, r, httpx.NotFound("Файл не найден"))
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		httpx.Fail(w, r, httpx.NotFound("Файл не найден"))
		return
	}
	w.Header().Set("Content-Type", packs.MimeOf(filepath.Base(path)))
	w.Header().Set("Cache-Control", "public, max-age=300")
	http.ServeContent(w, r, "", info.ModTime(), f)
}

// ---- game file ----

func (a *API) exportGame(w http.ResponseWriter, r *http.Request) {
	e := gameOf(r)
	f := e.Export()
	attachment(w, "game-"+e.PIN()+"-"+time.Now().UTC().Format("20060102-150405")+".json")
	httpx.JSON(w, 200, f)
}

func (a *API) importGame(w http.ResponseWriter, r *http.Request) {
	var f game.File
	ct, _, _ := mime.ParseMediaType(r.Header.Get("Content-Type"))
	if ct == "multipart/form-data" {
		path, _, err := a.saveUpload(w, r)
		if err != nil {
			httpx.Fail(w, r, err)
			return
		}
		defer os.Remove(path)
		b, err := os.ReadFile(path)
		if err == nil {
			err = json.Unmarshal(b, &f)
		}
		if err != nil {
			httpx.Fail(w, r, httpx.BadRequest("invalid_game_file", "Файл игры не читается как JSON"))
			return
		}
	} else {
		r.Body = http.MaxBytesReader(w, r.Body, 64<<20)
		if err := json.NewDecoder(r.Body).Decode(&f); err != nil {
			httpx.Fail(w, r, httpx.BadRequest("invalid_game_file", "Файл игры не читается как JSON"))
			return
		}
	}
	if err := gameOf(r).Import(&f); err != nil {
		httpx.Fail(w, r, err)
		return
	}
	httpx.NoContent(w)
}

// ---- helpers ----

func deref(p *string) string {
	if p == nil {
		return ""
	}
	return *p
}

func respond(w http.ResponseWriter, r *http.Request, status int, v any, err error) {
	if err != nil {
		httpx.Fail(w, r, err)
		return
	}
	if status == 204 {
		httpx.NoContent(w)
		return
	}
	httpx.JSON(w, status, v)
}
