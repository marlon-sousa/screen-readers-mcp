// screenreader-mcp domain -- the ask_user tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
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

func TestAskUserSurfacesABridgeFailure(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.AskUser{}).WithConnection(built.Connection)
	built.Interact.FailWith(errors.New("a prompt is already outstanding"))

	if _, err := call.Run(`{"prompt":"anything"}`); err == nil {
		t.Error("a refused prompt was reported as success")
	}
}
