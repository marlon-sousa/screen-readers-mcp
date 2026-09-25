// screenreader-mcp fakes -- FakeTextTyper: the TextTyper port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/text_typer.go.
// USED BY: the type_text tool controller tests.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeTextTyper struct {
	mu       sync.Mutex
	typed    []string
	graces   []int
	announce []string
	err      error
	outcome  *ports.TypeOutcome
}

var _ ports.TextTyper = (*FakeTextTyper)(nil)

func NewFakeTextTyper() *FakeTextTyper { return &FakeTextTyper{} }

func (f *FakeTextTyper) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeTextTyper) AnswerWith(outcome ports.TypeOutcome) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.outcome = &outcome
}

func (f *FakeTextTyper) Graces() []int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]int(nil), f.graces...)
}

func (f *FakeTextTyper) Announcements() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.announce...)
}

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
	// Unscripted: the reader said nothing, and Typed counts characters, not bytes, as in production.
	return ports.TypeOutcome{Typed: len([]rune(text))}, nil
}
