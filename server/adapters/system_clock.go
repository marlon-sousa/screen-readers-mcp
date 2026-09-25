// screenreader-mcp adapters -- SystemClock: the Clock leaf.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: leaf adapter implementing the Clock port with the real clock.
// BUILT BY: wiring/wiring.go.
// USED BY: everything that reads time, through the port.
package adapters

import (
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type SystemClock struct{}

var _ ports.Clock = (*SystemClock)(nil)

func NewSystemClock() *SystemClock { return &SystemClock{} }

func (c *SystemClock) Now() time.Time { return time.Now() }

func (c *SystemClock) Sleep(d time.Duration) { time.Sleep(d) }
