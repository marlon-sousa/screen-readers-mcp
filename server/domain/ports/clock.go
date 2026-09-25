// screenreader-mcp domain -- the Clock port.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, monotonic time plus sleeping.
// IMPLEMENTED BY: adapters/system_clock.go, and fakes/clock.go in tests.
// USED BY: the bridge client's request deadlines and the connection controller's heartbeat.
package ports

import "time"

type Clock interface {
	// Now is monotonic; only differences between readings are meaningful.
	Now() time.Time

	Sleep(d time.Duration)
}
