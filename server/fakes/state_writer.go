// screenreader-mcp fakes -- FakeStateWriter: the StateWriter port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double. MIRRORS domain/ports/state_writer.go.
// USED BY: the set_state tool controller tests.
//
// It COMPARES INSIDE ITSELF, the way the real bridge compares inside the reader:
// asking for the mode it already holds moves nothing and reports nothing. That
// keeps the property under test where it belongs -- a server-side controller
// that started comparing on its own would show up here as a redundant write
// rather than pass quietly.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// FakeStateWriter holds a mode and records every request.
type FakeStateWriter struct {
	mu sync.Mutex

	state ports.ReaderState
	err   error

	// Requests is every write asked for, including the ones that moved
	// nothing: "the tool dispatched" and "the mode moved" are two facts.
	Requests []ports.StateWrite
}

var _ ports.StateWriter = (*FakeStateWriter)(nil)

// NewFakeStateWriter builds a writer holding a zero state.
func NewFakeStateWriter() *FakeStateWriter { return &FakeStateWriter{} }

// SetHeldState seeds the state the writer starts from and reports back.
func (f *FakeStateWriter) SetHeldState(state ports.ReaderState) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.state = state
}

// FailWith makes every write return err -- how the real bridge reports a focus
// that is not a browsable document.
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
