// screenreader-mcp fakes -- FakeSessionDialer: the SessionDialer port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/session_dialer.go.
// USED BY: the connection controller tests, which assert no dial is made that the agent did not ask for.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type DialRequest struct {
	Reader  entities.ConfiguredReader
	Options ports.SessionOptions
}

type FakeSessionDialer struct {
	mu         sync.Mutex
	connection *ports.ReaderConnection
	err        error
	calls      []DialRequest
}

var _ ports.SessionDialer = (*FakeSessionDialer)(nil)

// NewFakeSessionDialer fails until told otherwise, so a test cannot connect by accident.
func NewFakeSessionDialer() *FakeSessionDialer { return &FakeSessionDialer{} }

func (f *FakeSessionDialer) Returns(connection *ports.ReaderConnection) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.connection = connection
	f.err = nil
}

func (f *FakeSessionDialer) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.connection = nil
	f.err = err
}

func (f *FakeSessionDialer) Calls() []DialRequest {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]DialRequest(nil), f.calls...)
}

func (f *FakeSessionDialer) Dial(reader entities.ConfiguredReader, opts ports.SessionOptions) (*ports.ReaderConnection, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, DialRequest{Reader: reader, Options: opts})
	if f.err != nil {
		return nil, f.err
	}
	if f.connection == nil {
		return nil, errNothingScripted
	}
	return f.connection, nil
}
