// screenreader-mcp domain -- ToolContext's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package tools_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func context(t *testing.T, announced ...entities.Capability) tools.ToolContext {
	t.Helper()
	built := testsupport.NewConnection("nvda", announced...)
	return tools.ToolContext{Tool: "get_braille", Connection: built.Connection}
}

func TestAnAnnouncedCapabilityYieldsItsPort(t *testing.T) {
	ctx := context(t, entities.CapabilityBraille)

	braille, err := ctx.Braille()
	if err != nil {
		t.Fatalf("Braille() = %v, want the port the reader announced", err)
	}
	if braille == nil {
		t.Error("Braille() returned a nil port with no error")
	}
}

func TestAnUnannouncedCapabilityIsAStructuredError(t *testing.T) {
	ctx := context(t, entities.CapabilitySpeech)

	_, err := ctx.Braille()

	var capability *tools.CapabilityError
	if !errors.As(err, &capability) {
		t.Fatalf("Braille() = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityBraille {
		t.Errorf("Capability = %q, want braille", capability.Capability)
	}
	if capability.Reader != "nvda" {
		t.Errorf("Reader = %q, want the connected reader named", capability.Reader)
	}
	if capability.Tool != "get_braille" {
		t.Errorf("Tool = %q, want the tool that failed named", capability.Tool)
	}
	if !strings.Contains(err.Error(), "did not announce") {
		t.Errorf("message = %q, want it to say the reader did not announce it", err)
	}
}

func TestNoSessionAtAllSaysToConnectFirst(t *testing.T) {
	ctx := tools.ToolContext{Tool: "get_braille"}

	_, err := ctx.Braille()

	var capability *tools.CapabilityError
	if !errors.As(err, &capability) {
		t.Fatalf("Braille() = %v, want a *CapabilityError", err)
	}
	if capability.Reader != "" {
		t.Errorf("Reader = %q, want empty when nothing is connected", capability.Reader)
	}
	if !strings.Contains(err.Error(), "connect_reader") {
		t.Errorf("message = %q, want it to name the tool that fixes this", err)
	}
}

// A table, because the failure guarded against is one accessor added later that returns its field directly.
func TestEveryCapabilityAccessorGates(t *testing.T) {
	ctx := context(t) // a reader announcing nothing at all

	accessors := []struct {
		capability entities.Capability
		get        func() (any, error)
	}{
		{entities.CapabilitySpeech, func() (any, error) { return ctx.Speech() }},
		{entities.CapabilityBraille, func() (any, error) { return ctx.Braille() }},
		{entities.CapabilityGestures, func() (any, error) { return ctx.Gestures() }},
		{entities.CapabilityFocus, func() (any, error) { return ctx.Focus() }},
		{entities.CapabilityState, func() (any, error) { return ctx.State() }},
		{entities.CapabilityConfig, func() (any, error) { return ctx.Config() }},
	}

	for _, accessor := range accessors {
		t.Run(string(accessor.capability), func(t *testing.T) {
			_, err := accessor.get()

			var capability *tools.CapabilityError
			if !errors.As(err, &capability) {
				t.Fatalf("= %v, want a *CapabilityError", err)
			}
			if capability.Capability != accessor.capability {
				t.Errorf("Capability = %q, want %q", capability.Capability, accessor.capability)
			}
		})
	}
}

func TestAReaderAnnouncingEverythingYieldsEveryPort(t *testing.T) {
	ctx := context(t, testsupport.EveryCapability()...)

	if _, err := ctx.Speech(); err != nil {
		t.Errorf("Speech: %v", err)
	}
	if _, err := ctx.Braille(); err != nil {
		t.Errorf("Braille: %v", err)
	}
	if _, err := ctx.Gestures(); err != nil {
		t.Errorf("Gestures: %v", err)
	}
	if _, err := ctx.Focus(); err != nil {
		t.Errorf("Focus: %v", err)
	}
	if _, err := ctx.State(); err != nil {
		t.Errorf("State: %v", err)
	}
	if _, err := ctx.Config(); err != nil {
		t.Errorf("Config: %v", err)
	}
}

func TestSessionIsTheEstablishedSessionOrAnError(t *testing.T) {
	ctx := context(t, entities.CapabilitySpeech)

	session, err := ctx.Session()
	if err != nil {
		t.Fatalf("Session() = %v, want the live session", err)
	}
	if session.Reader.Name != "nvda" {
		t.Errorf("reader = %q, want nvda", session.Reader.Name)
	}

	empty := tools.ToolContext{Tool: "status"}
	if _, err := empty.Session(); err == nil {
		t.Error("Session() with no connection returned no error")
	}
}
