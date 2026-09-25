// screenreader-mcp fakes -- FakeBrailleReader: the BrailleReader port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/braille_reader.go.
// USED BY: the get_braille tool controller tests.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type brailedEntry struct {
	text        string
	logPosition int
}

type FakeBrailleReader struct {
	mu      sync.Mutex
	brailed []brailedEntry
	journal int
	err     error
}

var _ ports.BrailleReader = (*FakeBrailleReader)(nil)

func NewFakeBrailleReader() *FakeBrailleReader { return &FakeBrailleReader{} }

// Braille gives each update its own journal position, so a wrongly passed coordinate shows.
func (f *FakeBrailleReader) Braille(text ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, one := range text {
		f.journal++
		f.brailed = append(f.brailed, brailedEntry{text: one, logPosition: f.journal})
	}
}

func (f *FakeBrailleReader) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeBrailleReader) BrailleSince(sinceIndex int) (ports.BrailleRange, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return ports.BrailleRange{}, f.err
	}
	if sinceIndex < 0 {
		sinceIndex = 0
	}
	if sinceIndex > len(f.brailed) {
		sinceIndex = len(f.brailed)
	}
	entries := make([]ports.BrailleEntry, 0, len(f.brailed)-sinceIndex)
	for i := sinceIndex; i < len(f.brailed); i++ {
		entries = append(entries, ports.BrailleEntry{
			Text:        f.brailed[i].text,
			Index:       i,
			LogPosition: f.brailed[i].logPosition,
		})
	}
	return ports.BrailleRange{
		Entries:   entries,
		FromIndex: sinceIndex,
		ToIndex:   len(f.brailed),
	}, nil
}
