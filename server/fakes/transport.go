// screenreader-mcp fakes -- FakeTransport: the Transport seam double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for the adapters/ports/transport.go seam.
// USED BY: adapters/bridge tests.
//
// An unscripted read is idle: it returns os.ErrDeadlineExceeded and advances the fake clock by one PollInterval.
package fakes

import (
	"io"
	"os"
	"sync"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
)

type step struct {
	data []byte
	err  error
}

type FakeTransport struct {
	mu      sync.Mutex
	clock   *FakeClock
	steps   []step
	written []byte
	closed  bool
	onWrite func(request []byte)
}

var _ adapterports.Transport = (*FakeTransport)(nil)

// NewFakeTransport accepts a nil clock for tests that never wait.
func NewFakeTransport(clock *FakeClock) *FakeTransport {
	return &FakeTransport{clock: clock}
}

// QueueRead chunks need not align with frame boundaries.
func (t *FakeTransport) QueueRead(data []byte) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.steps = append(t.steps, step{data: data})
}

func (t *FakeTransport) QueueLine(line string) {
	t.QueueRead([]byte(line + "\n"))
}

func (t *FakeTransport) QueueEOF() {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.steps = append(t.steps, step{err: io.EOF})
}

func (t *FakeTransport) QueueError(err error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.steps = append(t.steps, step{err: err})
}

// OnWrite runs respond after each complete write, with the bytes just written.
func (t *FakeTransport) OnWrite(respond func(request []byte)) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.onWrite = respond
}

func (t *FakeTransport) Read(p []byte) (int, error) {
	t.mu.Lock()
	if len(t.steps) == 0 {
		clock := t.clock
		t.mu.Unlock()
		if clock != nil {
			clock.Advance(adapterports.PollInterval)
		}
		return 0, os.ErrDeadlineExceeded
	}
	next := t.steps[0]
	if next.err != nil {
		t.steps = t.steps[1:]
		t.mu.Unlock()
		return 0, next.err
	}
	n := copy(p, next.data)
	if n == len(next.data) {
		t.steps = t.steps[1:]
	} else {
		t.steps[0].data = next.data[n:]
	}
	t.mu.Unlock()
	return n, nil
}

func (t *FakeTransport) Write(p []byte) (int, error) {
	t.mu.Lock()
	if t.closed {
		t.mu.Unlock()
		return 0, os.ErrClosed
	}
	t.written = append(t.written, p...)
	respond := t.onWrite
	request := append([]byte(nil), p...)
	t.mu.Unlock()
	if respond != nil {
		respond(request)
	}
	return len(p), nil
}

func (t *FakeTransport) Close() error {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.closed = true
	return nil
}

func (t *FakeTransport) Written() []byte {
	t.mu.Lock()
	defer t.mu.Unlock()
	return append([]byte(nil), t.written...)
}

func (t *FakeTransport) Closed() bool {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.closed
}
