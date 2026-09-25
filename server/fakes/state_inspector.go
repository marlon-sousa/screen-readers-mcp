// screenreader-mcp fakes -- FakeStateInspector: the StateInspector port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/state_inspector.go.
// USED BY: the get_state tool controller tests.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeStateInspector struct {
	mu    sync.Mutex
	state ports.ReaderState
	err   error
}

var _ ports.StateInspector = (*FakeStateInspector)(nil)

func NewFakeStateInspector() *FakeStateInspector { return &FakeStateInspector{} }

func (f *FakeStateInspector) SetState(state ports.ReaderState) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.state = state
}

func (f *FakeStateInspector) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeStateInspector) State() (ports.ReaderState, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return ports.ReaderState{}, f.err
	}
	return f.state, nil
}
