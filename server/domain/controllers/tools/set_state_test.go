// screenreader-mcp domain -- the set_state tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package tools_test

import (
	"errors"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

type setStateOutput struct {
	State struct {
		BrowseMode string `json:"browseMode"`
		SpeechMode string `json:"speechMode"`
		SleepMode  bool   `json:"sleepMode"`
		InputHelp  bool   `json:"inputHelp"`
	} `json:"state"`
	Changed []string `json:"changed"`
}

func TestSetStateMovesTheModeAndSaysSo(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityState)
	built.StateWrite.SetHeldState(ports.ReaderState{BrowseMode: "focus", SpeechMode: "talk"})
	call := testsupport.NewToolCall(&tools.SetState{}).WithConnection(built.Connection)

	result, err := call.Run(`{"browse_mode":"browse"}`)
	if err != nil {
		t.Fatalf("set_state: %v", err)
	}
	var out setStateOutput
	decode(t, result, &out)

	if out.State.BrowseMode != "browse" {
		t.Errorf("state after: got %q, want browse", out.State.BrowseMode)
	}
	if len(out.Changed) != 1 || out.Changed[0] != "browseMode" {
		t.Errorf("changed: got %v, want [browseMode]", out.Changed)
	}
}

func TestSetStateAlreadyThereChangesNothing(t *testing.T) {
	// An empty changed is a success meaning the reader was already there; a failed write is an error.
	built := testsupport.NewConnection("nvda", entities.CapabilityState)
	built.StateWrite.SetHeldState(ports.ReaderState{BrowseMode: "browse", SpeechMode: "talk"})
	call := testsupport.NewToolCall(&tools.SetState{}).WithConnection(built.Connection)

	result, err := call.Run(`{"browse_mode":"browse"}`)
	if err != nil {
		t.Fatalf("set_state: %v", err)
	}
	var out setStateOutput
	decode(t, result, &out)

	if len(out.Changed) != 0 {
		t.Errorf("changed: got %v, want empty", out.Changed)
	}
	if out.State.BrowseMode != "browse" {
		t.Errorf("state after: got %q, want browse", out.State.BrowseMode)
	}
	// Dispatched all the same: the compare belongs inside the reader.
	if len(built.StateWrite.Requests) != 1 {
		t.Errorf("requests: got %d, want 1 -- the controller must not compare on its own", len(built.StateWrite.Requests))
	}
}

func TestSetStateNeedsAModeToSet(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityState)
	call := testsupport.NewToolCall(&tools.SetState{}).WithConnection(built.Connection)

	if _, err := call.Run(`{}`); err == nil {
		t.Fatal("an empty call must be refused, not sent to change nothing")
	}
	if len(built.StateWrite.Requests) != 0 {
		t.Errorf("an empty call reached the reader: %v", built.StateWrite.Requests)
	}
}

func TestSetStateForwardsTheReadersRefusal(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityState)
	built.StateWrite.FailWith(errors.New("the focused object is not a browsable document"))
	call := testsupport.NewToolCall(&tools.SetState{}).WithConnection(built.Connection)

	_, err := call.Run(`{"browse_mode":"focus"}`)
	if err == nil {
		t.Fatal("want the reader's refusal, got success")
	}
	if got := err.Error(); got != "the focused object is not a browsable document" {
		t.Errorf("refusal: got %q, want it carried through unchanged", got)
	}
}

func TestSetStateIsGatedOnState(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityFocus)
	call := testsupport.NewToolCall(&tools.SetState{}).WithConnection(built.Connection)

	_, err := call.Run(`{"browse_mode":"browse"}`)
	var capability *tools.CapabilityError
	if !asCapabilityError(err, &capability) {
		t.Fatalf("want a CapabilityError, got %v", err)
	}
	if capability.Capability != entities.CapabilityState {
		t.Errorf("gate: got %q, want state", capability.Capability)
	}
}
