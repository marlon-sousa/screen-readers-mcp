// screenreader-mcp fakes -- FakeStateWriter: the StateWriter port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/state_writer.go.
// USED BY: the set_state tool controller tests.
//
// It compares inside itself, as the real bridge does, so asking for the held mode moves nothing.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeStateWriter struct {
	mu sync.Mutex

	state ports.ReaderState
	err   error

	// Requests includes the writes that moved nothing.
	Requests []ports.StateWrite
}

var _ ports.StateWriter = (*FakeStateWriter)(nil)

func NewFakeStateWriter() *FakeStateWriter { return &FakeStateWriter{} }

func (f *FakeStateWriter) SetHeldState(state ports.ReaderState) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.state = state
}

func (f *FakeStateWriter) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeStateWriter) SetState(request ports.StateWrite) (ports.StateWriteResult, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.Requests = append(f.Requests, request)
	if f.err != nil {
		return ports.StateWriteResult{}, f.err
	}
	changed := []string{}
	if request.BrowseMode != nil && *request.BrowseMode != f.state.BrowseMode {
		f.state.BrowseMode = *request.BrowseMode
		changed = append(changed, "browseMode")
	}
	return ports.StateWriteResult{State: f.state, Changed: changed}, nil
}
