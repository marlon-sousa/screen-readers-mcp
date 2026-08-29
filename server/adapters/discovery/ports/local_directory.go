// screenreader-mcp adapters -- the LocalDirectory seam.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter seam -- a port BETWEEN adapters, invisible to the domain.
// IMPLEMENTED BY: adapters/discovery/local_directory_windows.go (the named-pipe
// namespace) and local_directory_posix.go (a directory of socket files), plus a
// fake in tests.
// USED BY: adapters/discovery/local_probe.go, which holds every decision about
// what a name in that listing means.
//
// The seam exists so the one interesting rule -- a configured endpoint name is
// matched against the listing, and a name in the listing NEVER becomes an
// endpoint -- is unit-tested against a scripted listing, while the files that
// touch the OS have nothing in them to get wrong.
//
// It is also where the two hosts are made to answer in one vocabulary: whatever
// namespace a platform has, what comes back is the bare NAMES an endpoint is
// configured with, so the probe never learns which host it is on.
package ports

// LocalDirectory is the raw namespace local endpoints appear in.
type LocalDirectory interface {
	// Names returns the endpoint names currently present, with no path prefix
	// and no filename suffix. Best effort: an unreadable namespace is an empty
	// list, not an error, because "we could not look" and "nothing is
	// listening" lead to the same honest answer -- liveness unknown or not
	// listening, never a failed tool call.
	Names() []string
}
