// screenreader-mcp adapters -- the LocalDirectory seam.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter seam between adapters, invisible to the domain.
// IMPLEMENTED BY: adapters/discovery/local_directory_windows.go, local_directory_posix.go, and a fake in tests.
// USED BY: adapters/discovery/local_probe.go.
package ports

type LocalDirectory interface {
	// Names returns bare endpoint names; an unreadable namespace is an empty list, not an error.
	Names() []string
}
