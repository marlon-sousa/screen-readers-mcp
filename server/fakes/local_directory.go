// screenreader-mcp fakes -- FakeLocalDirectory: the LocalDirectory seam double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for adapters/discovery/ports/local_directory.go.
// USED BY: adapters/discovery tests.
package fakes

import discoveryports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery/ports"

type FakeLocalDirectory struct {
	names []string
}

var _ discoveryports.LocalDirectory = (*FakeLocalDirectory)(nil)

func NewFakeLocalDirectory(names ...string) *FakeLocalDirectory {
	return &FakeLocalDirectory{names: names}
}

func (d *FakeLocalDirectory) Names() []string {
	return append([]string(nil), d.names...)
}
