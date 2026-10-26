// Package discovery answers LAN broadcast probes so phones and TVs can find
// the server without typing an address (protocol §7).
package discovery

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net"
)

const probe = "SVOY_IGRA_DISCOVER"

// Run listens on udpPort until ctx ends. Errors are logged, never fatal:
// discovery is a convenience.
func Run(ctx context.Context, udpPort int, name string, httpPort int, version string) {
	pc, err := net.ListenPacket("udp4", fmt.Sprintf(":%d", udpPort))
	if err != nil {
		slog.Warn("LAN discovery disabled", "port", udpPort, "err", err)
		return
	}
	go func() {
		<-ctx.Done()
		_ = pc.Close()
	}()
	reply, _ := json.Marshal(map[string]any{"name": name, "port": httpPort, "version": version})
	slog.Info("LAN discovery listening", "udp", udpPort)
	buf := make([]byte, 256)
	for {
		n, addr, err := pc.ReadFrom(buf)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			continue
		}
		if string(buf[:n]) == probe {
			_, _ = pc.WriteTo(reply, addr)
		}
	}
}
