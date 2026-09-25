//go:build !windows

// screenreader-mcp adapters -- the local endpoint on POSIX: a Unix socket.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: leaf adapter that resolves the local endpoint to an AF_UNIX socket path and dials it.
// BUILT BY: adapters/bridge/endpoint.go.
// USED BY: adapters/bridge/json_lines_client.go, through the Transport seam.
package bridge

import (
	"os"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// localDialer resolves the path at build time, so an unusable socket path is reported when the configuration is read.
func localDialer(address string) (adapterports.Dialer, error) {
	path, err := entities.LocalSocketPath(address, localSocketDirs())
	if err != nil {
		return nil, err
	}
	return func() (adapterports.Transport, error) {
		return dialNet("unix", path, DefaultConnectTimeout)
	}, nil
}

// localSocketDirs passes an undeterminable home directory on as empty; the entity decides whether that matters.
func localSocketDirs() entities.LocalSocketDirs {
	home, err := os.UserHomeDir()
	if err != nil {
		home = ""
	}
	return entities.LocalSocketDirs{RuntimeDir: os.Getenv("XDG_RUNTIME_DIR"), Home: home}
}
