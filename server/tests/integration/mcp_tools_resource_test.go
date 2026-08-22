//go:build integration

// screenreader-mcp tests -- screenreader://tools, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario. Spec 0031: the server publishes WHAT it offers,
// as a document, so an agent never has to read Go source to find out what it
// can call.
//
// These are mostly the third of Part 4's three measures against drift, and that
// measure is close to tautological given the first -- every per-tool line is
// composed from the registry, so of course it agrees with the registry. The
// redundancy is deliberate: it is the guard that survives somebody deciding,
// reasonably, to hand-tune one entry. The day the composition is replaced by
// prose, these fail.
//
// Asserted here rather than in the adapter's own tests because what matters is
// what an MCP CLIENT reads: the resource being listed, being readable with
// nothing connected, and carrying the whole registry.
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

// The point of the whole entry: an agent that has connected nothing can still
// find out what there is. The reporter's client showed four tools; the document
// shows all of them, and it is readable at that moment rather than after.
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

// STATIC AND COMPLETE (2.1): the gated tools are described with no reader in
// sight. Filtering to what is currently callable would reproduce exactly the
// failure the document exists to fix.
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
			// The third gating value (spec 0036). Its section must say what
			// is actually so -- gated by what the CALL asks for -- and must
			// not name a capability, because there is no one capability to
			// name and inventing one would be the lie the value exists to
			// avoid.
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

// Both schemas reach the agent as authored, so they can be copied rather than
// paraphrased -- which is the reason they are fenced JSON at all (2.3).
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

// MEASURE 2 (Part 4): the embedded frame is a preamble and the error convention,
// and nothing tool-specific. What this stops is the next helpful edit putting a
// copy of the truth where nothing checks it -- a hand-written list beside a
// composed one, agreeing on the day it is written and never again.
//
// Read through the served document rather than from the Go variable, so what is
// asserted is what an agent reads: everything before the first tool section.
func TestTheFrameNamesNoTool(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadResourceText(t, toolsURI)

	frame := document
	if at := strings.Index(document, "\n### `"); at >= 0 {
		frame = document[:at]
	}
	// Whole words, because two tool names are also ordinary English -- the
	// frame is entitled to say that a reader ANNOUNCES its capabilities, which
	// is the wire contract's own word, and not entitled to mention `announce`.
	for _, tool := range tools.BuildRegistry().All() {
		named := regexp.MustCompile(`\b` + regexp.QuoteMeta(tool.Name()) + `\b`)
		if named.MatchString(frame) {
			t.Errorf("the frame names %s; everything tool-specific is composed from the "+
				"registry, so a tool named in the prose is a fact nothing checks", tool.Name())
		}
	}
}

// The error convention, stated once and in prose (2.4). It is exactly the class
// of thing an outsider has to infer by triggering it and an insider never
// notices is missing, so the phrases are guarded rather than left to survive a
// tidy-up.
func TestTheDocumentStatesTheErrorConvention(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := strings.ToLower(h.ReadResourceText(t, toolsURI))

	for _, want := range []string{
		// A failure is a readable result, not a transport fault.
		"iserror",
		// And the two capability failures, which have completely different
		// remedies and are already distinguished by CapabilityError.
		"nothing is connected",
		"never announced",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the tools document never says %q", want)
		}
	}
}

// Spec 0005 principle 2, applied to this document as it already is to the
// guidance one: it names the CAPABILITY that gates a tool and never a reader.
// The tool descriptions it publishes verbatim may name one -- press_gesture's
// gives an NVDA example on purpose -- so this checks the frame, which is the
// part this file writes.
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

// toolSections splits the document into one chunk per tool, keyed by name. The
// heading form is the composition's own, which is what makes "appears exactly
// once" checkable at all: a second heading for the same tool would collide here.
func toolSections(document string) map[string]string {
	sections := map[string]string{}
	for _, chunk := range strings.Split(document, "\n### `")[1:] {
		name, rest, found := strings.Cut(chunk, "`")
		if !found {
			continue
		}
		if _, twice := sections[name]; twice {
			// Reported as a missing section by the caller's count check, and
			// worth saying plainly here rather than silently overwriting.
			sections[name+" (again)"] = rest
			continue
		}
		sections[name] = rest
	}
	return sections
}

// fencedJSON pulls the ```json blocks out of one section, in order.
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
