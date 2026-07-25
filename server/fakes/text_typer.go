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
	mu    sync.Mutex
	typed []string
	err   error
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

// Typed is every string this typer was asked to insert, in order.
func (f *FakeTextTyper) Typed() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.typed...)
}

func (f *FakeTextTyper) TypeText(text string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	f.typed = append(f.typed, text)
	return nil
}
