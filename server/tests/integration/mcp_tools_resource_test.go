//go:build integration

// screenreader-mcp tests -- screenreader://tools, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario for screenreader://tools, read the way an MCP client reads it.
package integration_test

import (
	"encoding/json"
	"reflect"
	"regexp"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

const toolsURI = "screenreader://tools"

func TestTheToolsDocumentIsReadableBeforeAnythingIsConnected(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	if !contains(h.ResourceURIs(t), toolsURI) {
		t.Fatalf("resources/list = %v, want the tools document among them", h.ResourceURIs(t))
	}

	document := h.ReadResourceText(t, toolsURI)
	if strings.TrimSpace(document) == "" {
		t.Fatal("the tools resource is empty")
	}
}

func TestTheToolsDocumentListsEveryToolExactlyOnceWithTheGateTheCatalogGivesIt(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadResourceText(t, toolsURI)

	registry := tools.BuildRegistry()
	catalog := registry.Catalog()
	sections := toolSections(document)

	for _, tool := range registry.All() {
		section, present := sections[tool.Name()]
		if !present {
			t.Errorf("%s is registered and the document does not describe it", tool.Name())
			continue
		}

		capability, _ := catalog.CapabilityOf(tool.Name())
		switch capability {
		case "":
			if !strings.Contains(section, "Ungated") {
				t.Errorf("%s is ungated and its section does not say so", tool.Name())
			}
		case entities.GatedByItsSteps:
			if !strings.Contains(section, "Gated by its steps") {
				t.Errorf("%s is gated by its steps and its section does not say so", tool.Name())
			}
			if strings.Contains(section, "**Gated on `") {
				t.Errorf("%s claims a single gating capability, which it does not have",
					tool.Name())
			}
		default:
			if !strings.Contains(section, "`"+string(capability)+"`") {
				t.Errorf("%s is gated on %q and its section never names that capability",
					tool.Name(), capability)
			}
			if !strings.Contains(document, capability.Meaning()) {
				t.Errorf("the document never says what %q means; the sentence lives on "+
					"the entity precisely so it cannot be left out", capability)
			}
		}
	}

	if len(sections) != len(registry.All()) {
		t.Errorf("the document describes %d tools and the registry has %d; it must name "+
			"no tool the registry does not have", len(sections), len(registry.All()))
	}
	for name := range sections {
		if _, known := registry.Lookup(name); !known {
			t.Errorf("the document describes %q, which is not a registered tool", name)
		}
	}
}

func TestEverySchemaInTheDocumentParsesAndMatchesTheToolsOwn(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadResourceText(t, toolsURI)
	sections := toolSections(document)

	for _, tool := range tools.BuildRegistry().All() {
		section, present := sections[tool.Name()]
		if !present {
			continue // reported by the test above
		}
		t.Run(tool.Name(), func(t *testing.T) {
			fenced := fencedJSON(section)
			if len(fenced) != 2 {
				t.Fatalf("found %d fenced JSON blocks, want the parameters and the result",
					len(fenced))
			}
			for at, want := range [][]byte{tool.InputSchema(), tool.OutputSchema()} {
				var published, declared any
				if err := json.Unmarshal([]byte(fenced[at]), &published); err != nil {
					t.Fatalf("schema %d does not parse: %v", at, err)
				}
				if err := json.Unmarshal(want, &declared); err != nil {
					t.Fatalf("the tool's own schema %d does not parse: %v", at, err)
				}
				if !reflect.DeepEqual(published, declared) {
					t.Errorf("schema %d in the document is not the tool's own:\ngot  %s\nwant %s",
						at, fenced[at], want)
				}
			}
		})
	}
}

func TestTheFrameNamesNoTool(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadResourceText(t, toolsURI)

	frame := document
	if at := strings.Index(document, "\n### `"); at >= 0 {
		frame = document[:at]
	}
	// Whole words, because two tool names are also ordinary English.
	for _, tool := range tools.BuildRegistry().All() {
		named := regexp.MustCompile(`\b` + regexp.QuoteMeta(tool.Name()) + `\b`)
		if named.MatchString(frame) {
			t.Errorf("the frame names %s; everything tool-specific is composed from the "+
				"registry, so a tool named in the prose is a fact nothing checks", tool.Name())
		}
	}
}

func TestTheDocumentStatesTheErrorConvention(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := strings.ToLower(h.ReadResourceText(t, toolsURI))

	for _, want := range []string{
		"iserror",
		"nothing is connected",
		"never announced",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the tools document never says %q", want)
		}
	}
}

// The tool descriptions it publishes may name a reader, so only the frame is checked.
func TestTheFrameNamesNoParticularReader(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadResourceText(t, toolsURI)

	frame := document
	if at := strings.Index(document, "\n## "); at >= 0 {
		frame = document[:at]
	}
	for _, forbidden := range []string{"NVDA", "JAWS", "TalkBack", "VoiceOver"} {
		if strings.Contains(frame, forbidden) {
			t.Errorf("the frame names %q; it describes what this server offers, not one reader",
				forbidden)
		}
	}
}

func toolSections(document string) map[string]string {
	sections := map[string]string{}
	for _, chunk := range strings.Split(document, "\n### `")[1:] {
		name, rest, found := strings.Cut(chunk, "`")
		if !found {
			continue
		}
		if _, twice := sections[name]; twice {
			sections[name+" (again)"] = rest
			continue
		}
		sections[name] = rest
	}
	return sections
}

func fencedJSON(section string) []string {
	var found []string
	for rest := section; ; {
		start := strings.Index(rest, "```json\n")
		if start < 0 {
			return found
		}
		rest = rest[start+len("```json\n"):]
		end := strings.Index(rest, "\n```")
		if end < 0 {
			return found
		}
		found = append(found, rest[:end])
		rest = rest[end:]
	}
}
