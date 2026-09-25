// screenreader-mcp fakes -- FakeSessionLifecycle: the SessionLifecycle double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for the SessionLifecycle interface in domain/ports/session_dialer.go.
// USED BY: the connection controller tests.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeSessionLifecycle struct {
	mu      sync.Mutex
	pings   int
	byes    int
	closes  int
	pingErr error
	byeErr  error
	// suppressing nil means the bridge did not say.
	suppressing *bool
}

var _ ports.SessionLifecycle = (*FakeSessionLifecycle)(nil)

func NewFakeSessionLifecycle() *FakeSessionLifecycle { return &FakeSessionLifecycle{} }

func (f *FakeSessionLifecycle) FailPingWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.pingErr = err
}

func (f *FakeSessionLifecycle) ReportSuppressing(suppressing bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.suppressing = &suppressing
}

func (f *FakeSessionLifecycle) FailByeWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.byeErr = err
}

func (f *FakeSessionLifecycle) Pings() int  { return f.count(&f.pings) }
func (f *FakeSessionLifecycle) Byes() int   { return f.count(&f.byes) }
func (f *FakeSessionLifecycle) Closes() int { return f.count(&f.closes) }

func (f *FakeSessionLifecycle) Ping() (ports.PingReport, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.pings++
	if f.pingErr != nil {
		// The real client also returns an empty report on a failed probe.
		return ports.PingReport{}, f.pingErr
	}
	return ports.PingReport{Suppressing: f.suppressing}, nil
}

func (f *FakeSessionLifecycle) Bye() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.byes++
	return f.byeErr
}

func (f *FakeSessionLifecycle) Close() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.closes++
	return nil
}

func (f *FakeSessionLifecycle) count(field *int) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return *field
}
