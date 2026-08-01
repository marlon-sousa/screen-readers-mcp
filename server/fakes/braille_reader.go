// screenreader-mcp fakes -- FakeBrailleReader: the BrailleReader port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double. MIRRORS domain/ports/braille_reader.go.
// USED BY: 10b's get_braille tool controller tests.
//
// Note what it is NOT for: a reader without braille is tested by handing over no
// BrailleReader at all, which is the whole point of splitting the ports by
// capability. This fake stands in for a reader that HAS braille.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// brailedEntry is one display update and where it sits on the journal timeline.
type brailedEntry struct {
	text        string
	logPosition int
}

// FakeBrailleReader is an in-memory braille log.
type FakeBrailleReader struct {
	mu      sync.Mutex
	brailed []brailedEntry
	journal int
	err     error
}

var _ ports.BrailleReader = (*FakeBrailleReader)(nil)

// NewFakeBrailleReader builds an empty log.
func NewFakeBrailleReader() *FakeBrailleReader { return &FakeBrailleReader{} }

// Braille appends what the display showed.
//
// The stand-in journal advances by one per update, so consecutive entries get
// DIFFERENT positions and a tool cannot pass the coordinate through wrongly and
// still look right (spec 0021).
func (f *FakeBrailleReader) Braille(text ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, one := range text {
		f.journal++
		f.brailed = append(f.brailed, brailedEntry{text: one, logPosition: f.journal})
	}
}

// FailWith makes every call return err.
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
