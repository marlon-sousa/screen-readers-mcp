// screenreader-mcp domain -- the announce tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package tools_test

import (
	"errors"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestAnnounceSpeaksTheTextAndEchoesIt(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.Announce{}).WithConnection(built.Connection)

	var spoken struct {
		Announced string `json:"announced"`
	}
	result, err := call.Run(`{"text":"I am stuck on a password field."}`)
	if err != nil {
		t.Fatalf("announce: %v", err)
	}
	decode(t, result, &spoken)

	said := built.Interact.Announced()
	if len(said) != 1 || said[0] != "I am stuck on a password field." {
		t.Errorf("announced %v, want the text unchanged", said)
	}
	if spoken.Announced != "I am stuck on a password field." {
		t.Errorf("result = %q, want the text echoed", spoken.Announced)
	}
}

func TestAnnounceRefusesEmptyAndWhitespaceText(t *testing.T) {
	for _, params := range []string{`{"text":""}`, `{"text":"   "}`, `{"text":"\n\t"}`} {
		built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
		call := testsupport.NewToolCall(&tools.Announce{}).WithConnection(built.Connection)

		if _, err := call.Run(params); err == nil {
			t.Errorf("announce(%s) was accepted", params)
		}
		if said := built.Interact.Announced(); len(said) != 0 {
			t.Errorf("announce(%s) reached the reader as %v", params, said)
		}
	}
}

func TestAnnounceIsRefusedWhenTheReaderDidNotAnnounceIt(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.Announce{}).WithConnection(built.Connection)

	_, err := call.Run(`{"text":"hello"}`)

	var capability *tools.CapabilityError
	if !asCapabilityError(err, &capability) {
		t.Fatalf("announce = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityInteract {
		t.Errorf("Capability = %q, want interact", capability.Capability)
	}
	if capability.Reader != "nvda" {
		t.Errorf("Reader = %q, want the connected reader named", capability.Reader)
	}
}

func TestAnnounceWithNothingConnectedSaysToConnectFirst(t *testing.T) {
	call := testsupport.NewToolCall(&tools.Announce{})

	_, err := call.Run(`{"text":"hello"}`)

	var capability *tools.CapabilityError
	if !asCapabilityError(err, &capability) {
		t.Fatalf("announce = %v, want a *CapabilityError", err)
	}
	if capability.Reader != "" {
		t.Errorf("Reader = %q, want empty when nothing is connected", capability.Reader)
	}
}

func TestAnnounceSurfacesABridgeFailure(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityInteract)
	call := testsupport.NewToolCall(&tools.Announce{}).WithConnection(built.Connection)
	built.Interact.FailWith(errors.New("no synth loaded"))

	if _, err := call.Run(`{"text":"hello"}`); err == nil {
		t.Error("a failing announcement was reported as success")
	}
}
