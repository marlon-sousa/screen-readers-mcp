// screenreader-mcp fakes -- FakeTextTyper: the TextTyper port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double. MIRRORS domain/ports/text_typer.go.
// USED BY: the type_text tool controller tests.
//
// This one records, and legitimately so: typing has no return value worth
// asserting on, so "which strings were typed, in order" IS the requirement.
// A spy in a hand-written fake, not a mock framework.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// FakeTextTyper records the text it was asked to type.
type FakeTextTyper struct {
	mu       sync.Mutex
	typed    []string
	graces   []int
	announce []string
	err      error
	outcome  *ports.TypeOutcome
}

var _ ports.TextTyper = (*FakeTextTyper)(nil)

// NewFakeTextTyper builds a typer that accepts everything.
func NewFakeTextTyper() *FakeTextTyper { return &FakeTextTyper{} }

// FailWith makes every call return err, as SendInput being blocked would.
func (f *FakeTextTyper) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

// AnswerWith scripts the outcome every call returns, standing in for a reader
// that spoke while the text went in.
func (f *FakeTextTyper) AnswerWith(outcome ports.TypeOutcome) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.outcome = &outcome
}

// Graces is the grace window each call asked for, in order.
func (f *FakeTextTyper) Graces() []int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]int(nil), f.graces...)
}

// Announcements is what each call asked to be spoken to the human, in order.
func (f *FakeTextTyper) Announcements() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.announce...)
}

// Typed is every string this typer was asked to insert, in order.
func (f *FakeTextTyper) Typed() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.typed...)
}

func (f *FakeTextTyper) TypeText(text string, graceMs int, announce string) (ports.TypeOutcome, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return ports.TypeOutcome{}, f.err
	}
	f.typed = append(f.typed, text)
	f.graces = append(f.graces, graceMs)
	f.announce = append(f.announce, announce)
	if f.outcome != nil {
		return *f.outcome, nil
	}
	// Unscripted: the reader took the text and said nothing. The count is the
	// reader's answer in production, so the fake answers it here too -- in
	// characters, so an accented one counts once.
	return ports.TypeOutcome{Typed: len([]rune(text))}, nil
}
