package main

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"svoy-igra/app"
	"svoy-igra/app/config"
	"svoy-igra/app/packs"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "config:", err)
		os.Exit(2)
	}
	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: cfg.LogLevel})))

	if len(os.Args) > 1 {
		os.Exit(runCommand(cfg, os.Args[1:]))
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if err := app.Run(ctx, cfg); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

// runCommand handles operator commands:
//
//	svoy-igra unlock-pack <id>   remove the lock from a pack
//	svoy-igra healthcheck        exit 0 when the local server answers /api/health
func runCommand(cfg *config.Config, args []string) int {
	if len(args) == 1 && args[0] == "healthcheck" {
		return healthcheck(cfg)
	}
	if len(args) != 2 || args[0] != "unlock-pack" {
		fmt.Fprintln(os.Stderr, "usage: svoy-igra [healthcheck | unlock-pack <pack-id>]")
		return 2
	}
	store, err := packs.NewStore(cfg.DataDir, cfg.TempDir(), cfg.MaxUploadBytes())
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	defer store.Close()
	if err := store.SetLocked(args[1], false); err != nil {
		fmt.Fprintln(os.Stderr, "unlock-pack:", err)
		return 1
	}
	fmt.Println("unlocked", args[1])
	return 0
}

// healthcheck probes the local server; used by the container image, which
// has no shell or HTTP client of its own.
func healthcheck(cfg *config.Config) int {
	client := http.Client{Timeout: 3 * time.Second}
	res, err := client.Get(fmt.Sprintf("http://127.0.0.1:%d/api/health", cfg.Port))
	if err != nil {
		fmt.Fprintln(os.Stderr, "healthcheck:", err)
		return 1
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		fmt.Fprintln(os.Stderr, "healthcheck: status", res.StatusCode)
		return 1
	}
	return 0
}
