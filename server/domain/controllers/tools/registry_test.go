// screenreader-mcp domain -- the Registry's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package tools_test

import (
	"encoding/json"
	"slices"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
)

func TestTheUngatedFourAreAlwaysRegistered(t *testing.T) {
	registry := tools.BuildRegistry()

	for _, name := range []string{"list_readers", "connect_reader", "disconnect_reader", "status"} {
		tool, known := registry.Lookup(name)
		if !known {
			t.Errorf("%s is not registered", name)
			continue
		}
		if tool.Capability() != "" {
			t.Errorf("%s is gated on %q; the four discovery tools must be ungated, "+
				"or an agent could not reconnect after a disconnect", name, tool.Capability())
		}
	}
}

func TestPingEchoAndByeAreNotTools(t *testing.T) {
	registry := tools.BuildRegistry()

	for _, name := range []string{"ping", "echo", "bye"} {
		if _, known := registry.Lookup(name); known {
			t.Errorf("%q is registered as a tool; spec 0013 says it must not be", name)
		}
	}
}

func TestTheCatalogCoversExactlyTheRegisteredTools(t *testing.T) {
	registry := tools.BuildRegistry()
	catalog := registry.Catalog()

	for _, tool := range registry.All() {
		capability, known := catalog.CapabilityOf(tool.Name())
		if !known {
			t.Errorf("%s is registered but the catalog does not know it", tool.Name())
		}
		if capability != tool.Capability() {
			t.Errorf("%s is gated on %q in the catalog and %q on the tool",
				tool.Name(), capability, tool.Capability())
		}
	}

	registered := make([]string, 0, len(registry.All()))
	for _, tool := range registry.All() {
		registered = append(registered, tool.Name())
	}
	for _, name := range catalog.All() {
		if !slices.Contains(registered, name) {
			t.Errorf("the catalog knows %q, which is not a registered tool", name)
		}
	}
}

func TestEveryToolIsCompleteEnoughToBind(t *testing.T) {
	for _, tool := range tools.BuildRegistry().All() {
		t.Run(tool.Name(), func(t *testing.T) {
			if tool.Name() == "" {
				t.Error("has no name")
			}
			if len(tool.Description()) < 40 {
				t.Errorf("description is %d characters; it is the agent-facing "+
					"contract and most of what this tool is for",
					len(tool.Description()))
			}

			var schema map[string]any
			if err := json.Unmarshal(tool.InputSchema(), &schema); err != nil {
				t.Fatalf("input schema is not valid JSON: %v", err)
			}
			// The SDK panics at registration on an input schema that is not an object schema.
			if schema["type"] != "object" {
				t.Errorf(`input schema type = %v, want "object"`, schema["type"])
			}

			// The SDK checks the output schema the same way.
			var output map[string]any
			if err := json.Unmarshal(tool.OutputSchema(), &output); err != nil {
				t.Fatalf("output schema is not valid JSON: %v", err)
			}
			if output["type"] != "object" {
				t.Errorf(`output schema type = %v, want "object"`, output["type"])
			}
		})
	}
}

func TestToolNamesAreUnique(t *testing.T) {
	seen := map[string]bool{}
	for _, tool := range tools.BuildRegistry().All() {
		if seen[tool.Name()] {
			t.Errorf("%q is registered twice", tool.Name())
		}
		seen[tool.Name()] = true
	}
}

func TestLookupDoesNotInventTools(t *testing.T) {
	if _, known := tools.BuildRegistry().Lookup("nonsense"); known {
		t.Error("Lookup found a tool that does not exist")
	}
}
