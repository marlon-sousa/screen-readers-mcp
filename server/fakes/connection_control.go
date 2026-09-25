// screenreader-mcp fakes -- FakeConnectionControl: the ConnectionControl double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for the ConnectionControl interface in domain/controllers/tools/tool_context.go.
// USED BY: the four ungated tool controllers' tests.
package fakes

import (
	"errors"
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type ConnectRequest struct {
	Reader  string
	Options ports.SessionOptions
}

type FakeConnectionControl struct {
	mu sync.Mutex

	listing    entities.ReaderListing
	status     entities.ConnectionStatus
	connection *ports.ReaderConnection
	connectErr error
	disconnErr error
	verifyErr  error
	// suppressing nil means the bridge did not say.
	suppressing *bool

	connects    []ConnectRequest
	disconnects int
	verifies    int
}

var _ tools.ConnectionControl = (*FakeConnectionControl)(nil)

func NewFakeConnectionControl() *FakeConnectionControl {
	return &FakeConnectionControl{
		status: entities.ConnectionStatus{State: entities.Disconnected},
	}
}

func (f *FakeConnectionControl) SetListing(listing entities.ReaderListing) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.listing = listing
}

func (f *FakeConnectionControl) SetStatus(status entities.ConnectionStatus) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.status = status
}

func (f *FakeConnectionControl) SetConnection(connection *ports.ReaderConnection) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.connection = connection
	f.connectErr = nil
}

func (f *FakeConnectionControl) FailConnectWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.connectErr = err
}

func (f *FakeConnectionControl) FailDisconnectWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.disconnErr = err
}

func (f *FakeConnectionControl) ReportSuppressing(suppressing bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.suppressing = &suppressing
}

func (f *FakeConnectionControl) FailVerifyWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.verifyErr = err
}

func (f *FakeConnectionControl) Connects() []ConnectRequest {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]ConnectRequest(nil), f.connects...)
}

func (f *FakeConnectionControl) Disconnects() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.disconnects
}

func (f *FakeConnectionControl) Verifies() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.verifies
}

func (f *FakeConnectionControl) List() entities.ReaderListing {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.listing
}

func (f *FakeConnectionControl) Connect(readerName string, opts ports.SessionOptions) (*ports.ReaderConnection, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.connects = append(f.connects, ConnectRequest{Reader: readerName, Options: opts})
	if f.connectErr != nil {
		return nil, f.connectErr
	}
	if f.connection == nil {
		return nil, errNothingScripted
	}
	// The real dialer copies the persona from the options, so the fake does too.
	f.connection.Session.Persona = opts.Persona
	f.status = entities.ConnectionStatus{State: entities.Connected}
	return f.connection, nil
}

func (f *FakeConnectionControl) Disconnect() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.disconnects++
	if f.disconnErr != nil {
		return f.disconnErr
	}
	f.connection = nil
	f.status = entities.ConnectionStatus{State: entities.Disconnected}
	return nil
}

func (f *FakeConnectionControl) Status() entities.ConnectionStatus {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.status
}

func (f *FakeConnectionControl) Current() *ports.ReaderConnection {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.connection
}

// Verify drops the session only on a lost connection, as the real controller does;
// any other failure leaves it standing.
func (f *FakeConnectionControl) Verify() (ports.PingReport, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.verifies++
	if f.verifyErr == nil {
		return ports.PingReport{Suppressing: f.suppressing}, nil
	}
	if errors.Is(f.verifyErr, ports.ErrConnectionLost) {
		f.connection = nil
		f.status = entities.ConnectionStatus{State: entities.Disconnected, Reason: f.verifyErr.Error()}
	}
	return ports.PingReport{}, f.verifyErr
}
