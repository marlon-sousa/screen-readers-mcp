// screenreader-mcp fakes -- FakeGestureSender: the GestureSender port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/gesture_sender.go.
// USED BY: the press_gesture tool controller tests.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeGestureSender struct {
	mu       sync.Mutex
	pressed  [][]string
	graces   []int
	announce []string
	err      error
	outcome  *ports.GestureOutcome
}

var _ ports.GestureSender = (*FakeGestureSender)(nil)

func NewFakeGestureSender() *FakeGestureSender { return &FakeGestureSender{} }

func (f *FakeGestureSender) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeGestureSender) AnswerWith(outcome ports.GestureOutcome) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.outcome = &outcome
}

func (f *FakeGestureSender) Graces() []int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]int(nil), f.graces...)
}

// Announcements holds an empty string for a call that announced nothing.
func (f *FakeGestureSender) Announcements() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.announce...)
}

func (f *FakeGestureSender) Pressed() [][]string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([][]string(nil), f.pressed...)
}

func (f *FakeGestureSender) PressGestures(ids []string, graceMs int, announce string) (ports.GestureOutcome, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return ports.GestureOutcome{}, f.err
	}
	f.pressed = append(f.pressed, append([]string(nil), ids...))
	f.graces = append(f.graces, graceMs)
	f.announce = append(f.announce, announce)
	if f.outcome != nil {
		return *f.outcome, nil
	}
	// Unscripted: every id still gets a span, because a silent key is reported, never omitted.
	presses := make([]ports.GesturePress, 0, len(ids))
	for _, id := range ids {
		presses = append(presses, ports.GesturePress{Gesture: id})
	}
	return ports.GestureOutcome{Pressed: presses}, nil
}
