// screenreader-mcp fakes -- FakeGestureSender: the GestureSender port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double. MIRRORS domain/ports/gesture_sender.go.
// USED BY: 10b's press_gesture tool controller tests.
//
// This one records AND answers. "Which ids were sent, in which order" is still
// the requirement -- a spy in a hand-written fake, not a mock framework -- but
// since spec 0025 a press also reports what the reader said within its grace
// window, so the fake carries a scripted outcome to hand back.
package fakes

import (
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// FakeGestureSender records the gestures it was asked to press.
type FakeGestureSender struct {
	mu       sync.Mutex
	pressed  [][]string
	graces   []int
	announce []string
	err      error
	outcome  *ports.GestureOutcome
}

var _ ports.GestureSender = (*FakeGestureSender)(nil)

// NewFakeGestureSender builds a sender that accepts everything.
func NewFakeGestureSender() *FakeGestureSender { return &FakeGestureSender{} }

// FailWith makes every press return err, as a reader that rejected an unknown
// gesture id would.
func (f *FakeGestureSender) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

// AnswerWith scripts the outcome every press returns, standing in for a reader
// that spoke within the grace window.
func (f *FakeGestureSender) AnswerWith(outcome ports.GestureOutcome) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.outcome = &outcome
}

// Graces is the grace window each call asked for, in order -- the fake cannot
// wait, so recording what it was ASKED is the only honest observation of it.
func (f *FakeGestureSender) Graces() []int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]int(nil), f.graces...)
}

// Announcements is what each call asked to be spoken to the human, in order.
// An empty string is a real entry: it records a call that announced nothing.
func (f *FakeGestureSender) Announcements() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.announce...)
}

// Pressed is every call's id list, in order.
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
	// Unscripted: a reader that heard the keys and said nothing. Every id still
	// gets a span, because a silent key is reported, never omitted.
	presses := make([]ports.GesturePress, 0, len(ids))
	for _, id := range ids {
		presses = append(presses, ports.GesturePress{Gesture: id})
	}
	return ports.GestureOutcome{Pressed: presses}, nil
}
