//go:build !windows

// screenreader-mcp adapters -- the local namespace leaf (POSIX).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: leaf adapter implementing the LocalDirectory seam by listing the directory POSIX bridges bind their sockets in.
// BUILT BY: wiring/wiring.go, handed to LocalProbe.
package discovery

import (
	"os"

	discoveryports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

type SocketDirectory struct{}

var _ discoveryports.LocalDirectory = (*SocketDirectory)(nil)

func NewLocalDirectory() *SocketDirectory { return &SocketDirectory{} }

// Names reads a directory that does not exist yet exactly like an empty one.
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
