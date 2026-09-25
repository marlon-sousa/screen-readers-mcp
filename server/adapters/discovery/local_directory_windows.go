//go:build windows

// screenreader-mcp adapters -- the local namespace leaf (Windows).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: leaf adapter implementing the LocalDirectory seam by listing the Windows named-pipe namespace.
// BUILT BY: wiring/wiring.go, handed to LocalProbe.
package discovery

import (
	"os"

	discoveryports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery/ports"
)

const pipeNamespace = `\\.\pipe\`

type WindowsPipeDirectory struct{}

var _ discoveryports.LocalDirectory = (*WindowsPipeDirectory)(nil)

func NewLocalDirectory() *WindowsPipeDirectory { return &WindowsPipeDirectory{} }

// Names returns nil if the namespace cannot be read; a pipe name is already an endpoint's bare name.
func (d *WindowsPipeDirectory) Names() []string {
	entries, err := os.ReadDir(pipeNamespace)
	if err != nil {
		return nil
	}
	names := make([]string, 0, len(entries))
	for _, entry := range entries {
		names = append(names, entry.Name())
	}
	return names
}
