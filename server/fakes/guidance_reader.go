// screenreader-mcp fakes -- FakeGuidanceReader: the GuidanceReader port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double. MIRRORS domain/ports/guidance_reader.go.
// USED BY: the reader-guidance controller's tests, whose whole subject is HOW
// MANY TIMES the port is asked -- so the call count here is not incidental
// bookkeeping, it is the assertion (spec 0029 4.4: fetched once, cached for the
// session, refetched after a reconnect).

package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// FakeGuidanceReader answers with a scripted document and counts the asking.
type FakeGuidanceReader struct {
	mu sync.Mutex

	// Result is what Guidance returns.
	Result ports.ReaderGuidance

	// Err, when set, is returned instead -- a bridge that announced the
	// capability and then refused the command.
	Err error

	calls int
}

var _ ports.GuidanceReader = (*FakeGuidanceReader)(nil)

// NewFakeGuidanceReader builds a reader answering for `user`, recognised.
func NewFakeGuidanceReader() *FakeGuidanceReader {
	return &FakeGuidanceReader{
		Result: ports.ReaderGuidance{
			Persona:    "user",
			Recognised: true,
			Text:       "# fakereader's vocabulary\n\nPress the fake key.\n",
		},
	}
}

// Calls is how many round trips were made.
func (f *FakeGuidanceReader) Calls() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.calls
}

func (f *FakeGuidanceReader) Guidance() (ports.ReaderGuidance, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls++
	if f.Err != nil {
		return ports.ReaderGuidance{}, f.Err
	}
	return f.Result, nil
}
