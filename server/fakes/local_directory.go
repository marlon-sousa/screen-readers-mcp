// screenreader-mcp fakes -- FakeLocalDirectory: the LocalDirectory seam double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double. MIRRORS adapters/discovery/ports/local_directory.go.
// USED BY: adapters/discovery tests.
//
// A scripted namespace is what lets the interesting rule be tested on any
// platform: that a listed endpoint nobody configured is never reported, and
// never becomes something an agent can connect to.
package fakes

import discoveryports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery/ports"

// FakeLocalDirectory returns a fixed listing.
type FakeLocalDirectory struct {
	names []string
}

var _ discoveryports.LocalDirectory = (*FakeLocalDirectory)(nil)

// NewFakeLocalDirectory builds a directory listing exactly these names.
func NewFakeLocalDirectory(names ...string) *FakeLocalDirectory {
	return &FakeLocalDirectory{names: names}
}

func (d *FakeLocalDirectory) Names() []string {
	return append([]string(nil), d.names...)
}
