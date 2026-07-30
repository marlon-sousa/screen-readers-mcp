// screenreader-mcp domain -- the ask_user tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Its own file, alongside announce_test.go, for the same reason that one is
// separate: the subject is a HUMAN on the other end. What is worth protecting
// here is that the ticket comes back for the agent to poll with, that an empty
// question never reaches the tester (who would hear two beeps, a pause, and an
// instruction to answer a question they were never asked), and that the gate is
// structural.
package tools_test

import (
	"errors"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestAskUserPresentsThePromptAndReturnsATicket(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.AskUser{}).WithConnection(built.Connection)

	var reply struct {
		Ticket string `json:"ticket"`
	}
	result, err := call.Run(`{"prompt":"Plug in the braille display, then acknowledge."}`)
	if err != nil {
		t.Fatalf("ask_user: %v", err)
	}
	decode(t, result, &reply)

	if reply.Ticket == "" {
		t.Error("ticket is empty; the agent has nothing to poll with")
	}
	prompt, ok := built.Interact.Prompts[reply.Ticket]
	if !ok {
		t.Fatalf("ticket %q was not the one the prompt was filed under", reply.Ticket)
	}
	if prompt != "Plug in the braille display, then acknowledge." {
		t.Errorf("presented %q, want the prompt unchanged", prompt)
	}
}

// A question with no words is two cue beeps and an instruction to answer
// something never asked -- strictly worse for the tester than no prompt at all.
func TestAskUserRefusesEmptyAndWhitespacePrompts(t *testing.T) {
	for _, params := range []string{`{"prompt":""}`, `{"prompt":"   "}`, `{"prompt":"\n\t"}`} {
		built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
		call := testsupport.NewToolCall(&tools.AskUser{}).WithConnection(built.Connection)

		if _, err := call.Run(params); err == nil {
			t.Errorf("ask_user(%s) was accepted", params)
		}
		if len(built.Interact.Prompts) != 0 {
			t.Errorf("ask_user(%s) reached the reader as %v", params, built.Interact.Prompts)
		}
	}
}

// The gate, structurally: a bridge that cannot reach a human never announces
// `interact`, so the port was never handed over.
func TestAskUserIsRefusedWhenTheReaderDidNotAnnounceInteract(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.AskUser{}).WithConnection(built.Connection)

	_, err := call.Run(`{"prompt":"anything"}`)

	var capability *tools.CapabilityError
	if !asCapabilityError(err, &capability) {
		t.Fatalf("ask_user = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityInteract {
		t.Errorf("Capability = %q, want interact", capability.Capability)
	}
}

func TestAskUserWithNothingConnectedSaysToConnectFirst(t *testing.T) {
	call := testsupport.NewToolCall(&tools.AskUser{})

	_, err := call.Run(`{"prompt":"anything"}`)

	var capability *tools.CapabilityError
	if !asCapabilityError(err, &capability) {
		t.Fatalf("ask_user = %v, want a *CapabilityError", err)
	}
	if capability.Reader != "" {
		t.Errorf("Reader = %q, want empty when nothing is connected", capability.Reader)
	}
}

// A second outstanding prompt is a bridge-side error (only one window at a
// time). The session survives it, so the tool must surface it rather than
// swallow it and leave the agent believing it has two tickets.
func TestAskUserSurfacesABridgeFailure(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.AskUser{}).WithConnection(built.Connection)
	built.Interact.FailWith(errors.New("a prompt is already outstanding"))

	if _, err := call.Run(`{"prompt":"anything"}`); err == nil {
		t.Error("a refused prompt was reported as success")
	}
}
