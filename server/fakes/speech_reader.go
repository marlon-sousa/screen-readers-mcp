// screenreader-mcp fakes -- FakeSpeechReader: the SpeechReader port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/speech_reader.go.
// USED BY: the speech tool controller tests.
package fakes

import (
	"fmt"
	"strings"
	"sync"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type spokenEntry struct {
	text        string
	logPosition int
	// emittedAt is synthetic and monotonic, so tests pin no clock or timezone.
	emittedAt string
}

type FakeSpeechReader struct {
	mu        sync.Mutex
	spoken    []spokenEntry
	journal   int
	err       error
	finished  bool
	waitCalls []ports.SpeechWait
}

var _ ports.SpeechReader = (*FakeSpeechReader)(nil)

func NewFakeSpeechReader() *FakeSpeechReader { return &FakeSpeechReader{finished: true} }

// Speak gives each utterance its own journal position, so a wrongly passed coordinate shows.
func (f *FakeSpeechReader) Speak(text ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, one := range text {
		f.journal++
		f.spoken = append(f.spoken, spokenEntry{
			text:        one,
			logPosition: f.journal,
			emittedAt:   fmt.Sprintf("2026-08-16 09:04:%02d.000", f.journal),
		})
	}
}

// SpeakWithoutStamp records an utterance with no wall clock, as older bridges send.
func (f *FakeSpeechReader) SpeakWithoutStamp(text ...string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	for _, one := range text {
		f.journal++
		f.spoken = append(f.spoken, spokenEntry{text: one, logPosition: f.journal})
	}
}

func (f *FakeSpeechReader) AdvanceJournal(records int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.journal += records
}

func (f *FakeSpeechReader) JournalPosition() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.journal
}

func (f *FakeSpeechReader) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeSpeechReader) SetFinished(finished bool) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.finished = finished
}

func (f *FakeSpeechReader) Waits() []ports.SpeechWait {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]ports.SpeechWait(nil), f.waitCalls...)
}

func (f *FakeSpeechReader) SpeechSince(sinceIndex int) (ports.SpeechRange, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return ports.SpeechRange{}, f.err
	}
	if sinceIndex < 0 {
		sinceIndex = 0
	}
	if sinceIndex > len(f.spoken) {
		sinceIndex = len(f.spoken)
	}
	entries := make([]ports.SpeechEntry, 0, len(f.spoken)-sinceIndex)
	for i := sinceIndex; i < len(f.spoken); i++ {
		entries = append(entries, ports.SpeechEntry{
			Text:        f.spoken[i].text,
			Index:       i,
			LogPosition: f.spoken[i].logPosition,
			EmittedAt:   f.spoken[i].emittedAt,
		})
	}
	return ports.SpeechRange{
		Entries:   entries,
		FromIndex: sinceIndex,
		ToIndex:   len(f.spoken),
	}, nil
}

func (f *FakeSpeechReader) LastSpeech() (ports.LastSpeech, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return ports.LastSpeech{}, f.err
	}
	if len(f.spoken) == 0 {
		return ports.LastSpeech{Index: 0}, nil
	}
	last := f.spoken[len(f.spoken)-1]
	return ports.LastSpeech{
		Text:        last.text,
		Index:       len(f.spoken) - 1,
		LogPosition: last.logPosition,
	}, nil
}

func (f *FakeSpeechReader) NextSpeechIndex() (int, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return 0, f.err
	}
	return len(f.spoken), nil
}

func (f *FakeSpeechReader) WaitForSpeech(wait ports.SpeechWait) (ports.SpeechMatch, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.waitCalls = append(f.waitCalls, wait)
	if f.err != nil {
		return ports.SpeechMatch{}, f.err
	}
	from := 0
	if wait.AfterIndex != nil {
		from = *wait.AfterIndex
	}
	for i := from; i < len(f.spoken); i++ {
		if strings.Contains(f.spoken[i].text, wait.Text) {
			return ports.SpeechMatch{
				Found:       true,
				Index:       i,
				Text:        f.spoken[i].text,
				LogPosition: f.spoken[i].logPosition,
			}, nil
		}
	}
	// Not found is an answer, not an error; the position on a miss is the journal's current one.
	return ports.SpeechMatch{Found: false, Index: len(f.spoken), LogPosition: f.journal}, nil
}

func (f *FakeSpeechReader) WaitForSpeechToFinish(timeout time.Duration) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return false, f.err
	}
	return f.finished, nil
}
