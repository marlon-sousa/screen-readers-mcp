// screenreader-mcp fakes -- FakeInteractPort: the Interact port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double for domain/ports/interact.go.
// USED BY: the announce, ask_user and wait_for_user_reply tool controller tests.
package fakes

import (
	"sync"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type FakeInteractPort struct {
	mu        sync.Mutex
	announced []string
	err       error
	polls     []time.Duration
	// Replies maps ticket to reply; set before a test runs.
	Replies map[string]ports.UserReply
	// Prompts maps ticket to prompt.
	Prompts map[string]string
}

var _ ports.Interact = (*FakeInteractPort)(nil)

func NewFakeInteractPort() *FakeInteractPort {
	return &FakeInteractPort{
		Replies: make(map[string]ports.UserReply),
		Prompts: make(map[string]string),
	}
}

func (f *FakeInteractPort) FailWith(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.err = err
}

func (f *FakeInteractPort) Announced() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string(nil), f.announced...)
}

func (f *FakeInteractPort) Announce(text string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	f.announced = append(f.announced, text)
	return nil
}

func (f *FakeInteractPort) AskUser(prompt string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return "", f.err
	}
	ticket := "ticket-" + prompt[:min(len(prompt), 8)]
	f.Prompts[ticket] = prompt
	return ticket, nil
}

func (f *FakeInteractPort) WaitForUserReply(ticket string, timeout time.Duration) (ports.UserReply, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	// Recorded even on the failure path, because tests assert on the resolved timeout.
	f.polls = append(f.polls, timeout)
	if f.err != nil {
		return ports.UserReply{}, f.err
	}
	if reply, ok := f.Replies[ticket]; ok {
		return reply, nil
	}
	return ports.UserReply{Answered: false}, nil
}

func (f *FakeInteractPort) Polls() []time.Duration {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]time.Duration(nil), f.polls...)
}
