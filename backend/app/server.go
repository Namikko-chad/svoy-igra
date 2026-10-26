// Package app wires the server: config → packs store → game engine →
// websocket hub → REST API → optional static frontend → LAN discovery.
package app

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"svoy-igra/app/api"
	"svoy-igra/app/config"
	"svoy-igra/app/discovery"
	"svoy-igra/app/game"
	"svoy-igra/app/packs"
	"svoy-igra/app/ws"
)

type server struct {
	store   *packs.Store
	games   *game.Manager
	hub     *ws.Hub
	handler http.Handler
}

// build wires the components without starting anything.
func build(cfg *config.Config) (*server, error) {
	if err := os.MkdirAll(cfg.DataDir, 0o755); err != nil {
		return nil, fmt.Errorf("create DATA_DIR: %w", err)
	}
	// Staging area for uploads/exports; leftovers of a crash are dropped.
	_ = os.RemoveAll(cfg.TempDir())
	if err := os.MkdirAll(cfg.TempDir(), 0o755); err != nil {
		return nil, fmt.Errorf("create temp dir: %w", err)
	}
	store, err := packs.NewStore(cfg.DataDir, cfg.TempDir(), cfg.MaxUploadBytes())
	if err != nil {
		return nil, err
	}
	games, err := game.NewManager(store, cfg.DataDir, time.Duration(cfg.GameIdleMin)*time.Minute, cfg.MaxGames)
	if err != nil {
		return nil, err
	}
	hub := ws.New(games)

	mux := http.NewServeMux()
	api.New(cfg, store, games).Register(mux)
	mux.Handle("GET /api/ws", hub)
	if cfg.StaticDir != "" {
		mux.Handle("/", spa(cfg.StaticDir))
	}
	return &server{store: store, games: games, hub: hub, handler: logRequests(cors(cfg.CORSOrigins, mux))}, nil
}

// start runs the background loops until ctx ends; wait for them with the WaitGroup.
func (s *server) start(ctx context.Context, wg *sync.WaitGroup) {
	wg.Go(func() { s.games.Run(ctx) })
	wg.Go(func() { s.hub.Run(ctx) })
}

// Run starts everything and blocks until ctx ends, then shuts down cleanly.
func Run(ctx context.Context, cfg *config.Config) error {
	s, err := build(cfg)
	if err != nil {
		return err
	}
	defer s.store.Close()

	srv := &http.Server{
		Addr:              fmt.Sprintf("%s:%d", cfg.Host, cfg.Port),
		Handler:           s.handler,
		ReadHeaderTimeout: 10 * time.Second,
	}

	runCtx, stop := context.WithCancel(context.Background())
	var wg sync.WaitGroup
	s.start(runCtx, &wg)
	if cfg.DiscoveryPort > 0 {
		wg.Go(func() { discovery.Run(runCtx, cfg.DiscoveryPort, cfg.ServerName, cfg.Port, config.Version) })
	}

	errCh := make(chan error, 1)
	go func() {
		slog.Info("server listening", "addr", srv.Addr, "data", cfg.DataDir, "static", cfg.StaticDir, "version", config.Version)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
		close(errCh)
	}()

	select {
	case <-ctx.Done():
	case err := <-errCh:
		stop()
		wg.Wait()
		return err
	}
	slog.Info("shutting down")
	stop() // closes sockets first: hijacked connections are not drained by Shutdown
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = srv.Shutdown(shutdownCtx)
	wg.Wait()
	return nil
}

// spa serves the built frontend; unknown non-API paths get index.html.
func spa(dir string) http.Handler {
	files := http.FileServer(http.Dir(dir))
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		p := filepath.Join(dir, filepath.Clean("/"+r.URL.Path))
		if info, err := os.Stat(p); err != nil || info.IsDir() {
			if r.URL.Path != "/" {
				w.Header().Set("Cache-Control", "no-cache")
				http.ServeFile(w, r, filepath.Join(dir, "index.html"))
				return
			}
		}
		if strings.HasPrefix(r.URL.Path, "/assets/") {
			w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
		}
		files.ServeHTTP(w, r)
	})
}

func cors(origins []string, next http.Handler) http.Handler {
	any := slices.Contains(origins, "*")
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && (any || slices.Contains(origins, origin)) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Expose-Headers", "Content-Disposition")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// Unwrap lets http.ResponseController reach Hijack for the websocket upgrade.
func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/api/") || r.URL.Path == "/api/ws" {
			next.ServeHTTP(w, r)
			return
		}
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: 200}
		next.ServeHTTP(sw, r)
		slog.Info("http", "method", r.Method, "path", r.URL.Path, "status", sw.status, "ms", time.Since(start).Milliseconds())
	})
}
