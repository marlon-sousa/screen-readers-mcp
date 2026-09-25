// screenreader-mcp fakes -- FakeGuidanceReader: the GuidanceReader port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/guidance_reader.go.
// USED BY: the reader-guidance controller's tests, which assert on its call count.

package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeGuidanceReader struct {
	mu sync.Mutex

	Result ports.ReaderGuidance

	Err error

	calls int
}

var _ ports.GuidanceReader = (*FakeGuidanceReader)(nil)

func NewFakeGuidanceReader() *FakeGuidanceReader {
	return &FakeGuidanceReader{
		Result: ports.ReaderGuidance{
			Persona:    "user",
			Recognised: true,
			Text:       "# fakereader's vocabulary\n\nPress the fake key.\n",
		},
	}
}

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
