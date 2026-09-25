//go:build conformance && windows

// screenreader-mcp tests -- the same whole session, over a REAL named pipe.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: conformance scenario, Windows only, running the whole session over a real named pipe.
package conformance_test

import "testing"

func TestAWholeSessionOverARealNamedPipe(t *testing.T) {
	runWholeSession(t, "pipe")
}
