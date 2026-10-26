// Package config reads the server configuration from the environment.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// Version is the server version reported by /api/info and LAN discovery.
const Version = "6.2.0"

type Config struct {
	Host          string
	Port          int
	DataDir       string
	StaticDir     string
	GameIdleMin   int
	MaxGames      int
	AndroidPkg    string
	AndroidSHA256 []string
	DiscoveryPort int
	ServerName    string
	WebURL        string
	MaxUploadMB   int64
	LogLevel      slog.Level
	CORSOrigins   []string
}

func Load() (*Config, error) {
	c := &Config{
		Host:          env("SERVER_HOST", "0.0.0.0"),
		Port:          envInt("SERVER_PORT", 3050),
		DataDir:       env("DATA_DIR", "./data"),
		StaticDir:     env("STATIC_DIR", ""),
		GameIdleMin:   envInt("GAME_IDLE_MINUTES", 60),
		MaxGames:      envInt("MAX_GAMES", 100),
		AndroidPkg:    env("ANDROID_PACKAGE", "dev.svoyigra.mobile"),
		AndroidSHA256: splitList(env("ANDROID_CERT_SHA256", "")),
		DiscoveryPort: envInt("DISCOVERY_PORT", 3051),
		ServerName:    env("SERVER_NAME", "Своя игра"),
		WebURL:        strings.TrimRight(env("WEB_URL", ""), "/"),
		MaxUploadMB:   int64(envInt("MAX_UPLOAD_MB", 1024)),
		CORSOrigins:   splitList(env("CORS_ORIGINS", "*")),
	}
	switch strings.ToLower(env("LOG_LEVEL", "info")) {
	case "debug":
		c.LogLevel = slog.LevelDebug
	case "warn", "warning":
		c.LogLevel = slog.LevelWarn
	case "error":
		c.LogLevel = slog.LevelError
	default:
		c.LogLevel = slog.LevelInfo
	}

	var errs []error
	if c.GameIdleMin <= 0 {
		errs = append(errs, errors.New("GAME_IDLE_MINUTES must be positive"))
	}
	if c.MaxGames <= 0 {
		errs = append(errs, errors.New("MAX_GAMES must be positive"))
	}
	if c.Port <= 0 || c.Port > 65535 {
		errs = append(errs, fmt.Errorf("SERVER_PORT %d is out of range", c.Port))
	}
	if c.MaxUploadMB <= 0 {
		errs = append(errs, errors.New("MAX_UPLOAD_MB must be positive"))
	}
	return c, errors.Join(errs...)
}

// TempDir is where uploads and exports are staged: on the data disk, because
// the container image has no /tmp and packs can be large.
func (c *Config) TempDir() string { return filepath.Join(c.DataDir, "tmp") }

// MaxUploadBytes is the upload / unpacked-archive limit in bytes.
func (c *Config) MaxUploadBytes() int64 { return c.MaxUploadMB << 20 }

func env(key, def string) string {
	if v, ok := os.LookupEnv(key); ok {
		return strings.TrimSpace(v)
	}
	return def
}

func envInt(key string, def int) int {
	v := env(key, "")
	if v == "" {
		return def
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return def
	}
	return n
}

func splitList(s string) []string {
	var out []string
	for _, p := range strings.Split(s, ",") {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
