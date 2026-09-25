// screenreader-mcp fakes -- FakeClock: the Clock port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/clock.go.
// USED BY: tests only; wiring builds adapters/system_clock.go instead.
package fakes

import (
	"sync"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// FakeClock only moves when a test tells it to; Sleep is an instant advance.
type FakeClock struct {
	mu      sync.Mutex
	now     time.Time
	slept   []time.Duration
	onSleep func(d time.Duration)
}

var _ ports.Clock = (*FakeClock)(nil)

func NewFakeClock() *FakeClock {
	return &FakeClock{now: time.Date(2026, time.July, 22, 12, 0, 0, 0, time.UTC)}
}

func (c *FakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

// Sleep records each duration, for tests where the cadence is the requirement.
func (c *FakeClock) Sleep(d time.Duration) {
	c.mu.Lock()
	c.now = c.now.Add(d)
	c.slept = append(c.slept, d)
	hook := c.onSleep
	c.mu.Unlock()
	if hook != nil {
		hook(d)
	}
}

// Advance moves the clock without recording a sleep.
func (c *FakeClock) Advance(d time.Duration) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.now = c.now.Add(d)
}

func (c *FakeClock) Slept() []time.Duration {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]time.Duration(nil), c.slept...)
}

// OnSleep runs a hook after each Sleep, to make something happen while the code under test waits.
func (c *FakeClock) OnSleep(hook func(d time.Duration)) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.onSleep = hook
}
