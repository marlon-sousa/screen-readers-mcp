//go:build !windows

// screenreader-mcp adapters -- the local namespace leaf (POSIX).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: LEAF adapter. IMPLEMENTS the LocalDirectory seam by reading the
// directory POSIX bridges bind their sockets in, and does nothing else. Its
// Windows sibling is local_directory_windows.go.
// BUILT BY: wiring/wiring.go, handed to LocalProbe.
//
// It decides nothing: WHERE that directory is, and which filename stands for
// which endpoint name, are in domain/entities/local_socket.go, which is pure
// and tested on every host. This file reads the environment and the directory.
//
// Until spec 0044 the non-Windows leaf returned an empty list, so every
// endpoint on macOS reported liveness UNKNOWN by construction. A directory of
// socket files answers the question honestly, so list_readers starts working on
// the host lane 3 is built on.
package discovery

import (
	"os"

	discoveryports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// SocketDirectory lists the local endpoints with a socket file on this machine.
type SocketDirectory struct{}

var _ discoveryports.LocalDirectory = (*SocketDirectory)(nil)

// NewLocalDirectory builds the platform's directory listing.
func NewLocalDirectory() *SocketDirectory { return &SocketDirectory{} }

// Names lists the socket files, as the endpoint names they stand for.
//
// A directory that does not exist yet -- no bridge has ever run here -- reads
// exactly like one with nothing in it, which is the honest answer either way.
func (d *SocketDirectory) Names() []string {
	home, err := os.UserHomeDir()
	if err != nil {
		home = ""
	}
	dir, err := entities.LocalSocketDir(entities.LocalSocketDirs{
		RuntimeDir: os.Getenv("XDG_RUNTIME_DIR"),
		Home:       home,
	})
	if err != nil {
		return nil
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		if name, ok := entities.LocalSocketName(entry.Name()); ok {
			names = append(names, name)
		}
	}
	return names
}
