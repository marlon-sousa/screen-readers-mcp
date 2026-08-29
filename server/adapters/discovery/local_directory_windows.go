//go:build windows

// screenreader-mcp adapters -- the local namespace leaf (Windows).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: LEAF adapter. IMPLEMENTS the LocalDirectory seam by reading the Windows
// named-pipe namespace, and does nothing else. Its POSIX sibling is
// local_directory_posix.go.
// BUILT BY: wiring/wiring.go, handed to LocalProbe.
//
// Reading `\\.\pipe\` as a directory is what makes liveness knowable without
// dialing, which matters because the bridge serves one session at a time. There
// is no test file: what a name in the listing MEANS is decided one layer up, in
// local_probe.go, which is tested against a scripted listing.
package discovery

import (
	"os"

	discoveryports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery/ports"
)

// pipeNamespace is the directory the named-pipe namespace is exposed as.
const pipeNamespace = `\\.\pipe\`

// WindowsPipeDirectory lists the named pipes present on this machine.
type WindowsPipeDirectory struct{}

var _ discoveryports.LocalDirectory = (*WindowsPipeDirectory)(nil)

// NewLocalDirectory builds the platform's directory listing.
func NewLocalDirectory() *WindowsPipeDirectory { return &WindowsPipeDirectory{} }

// Names lists the namespace, or nothing if it cannot be read. A pipe name is
// already the bare name an endpoint is configured with, so nothing is trimmed.
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
