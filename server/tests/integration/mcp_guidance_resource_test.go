//go:build integration

// screenreader-mcp tests -- screenreader://guidance, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario. Spec 0023: the server publishes HOW to drive a
// reader, not only what can be called.
//
// Asserting on prose is usually a bad trade, so this file asserts only the three
// things the spec actually decided and that would be silently wrong if broken:
// the document is reachable before connecting (it is advice for the agent that
// has not started yet), it is reader-agnostic (spec 0005 principle 2 applies to
// what we TELL the agent, not only to what the code branches on), and every
// screenreader:// URI a tool description points at is really published.
//
// That last one is the valuable one. Four tool descriptions now end with "see
// screenreader://guidance", and a dangling pointer in a tool description is
// invisible to every other test in the tree: nothing fails, the agent simply
// gets a resource-not-found at the moment it took our advice.
package integration_test

import (
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// It is advice about how to start, so it has to be readable before starting.
func TestTheGuidanceIsReadableBeforeAnythingIsConnected(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	if !contains(h.ResourceURIs(t), "screenreader://guidance") {
		t.Fatalf("resources/list = %v, want the guidance among them", h.ResourceURIs(t))
	}

	document := h.ReadGuidance(t)
	if strings.TrimSpace(document) == "" {
		t.Fatal("the guidance resource is empty")
	}
}

// The two claims the spec makes about the content, in the agent's own terms.
// Phrases rather than sentences, so rewording the document does not fail this,
// but removing what it is FOR does.
func TestTheGuidanceStatesTheRuleAndTheSettleStep(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadGuidance(t)

	for _, want := range []string{
		// Part 1's diagnosis: an ok result is not evidence the effect happened.
		"delivery, not consequence",
		// The primitive that closes the gap, named so the agent can call it.
		"wait_for_speech_to_finish",
		// The escape hatch, so a stuck agent asks instead of guessing.
		"ask_user",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the guidance never mentions %q", want)
		}
	}
}

// Spec 0005 principle 2, applied to prose: the server hands the agent a METHOD
// and never one reader's key map. The agent knows NVDA's and JAWS's already, and
// screenreader://info tells it which one is connected -- so a key combo appearing
// here would be this server growing an opinion about a particular reader in the
// one place nobody thinks to check.
func TestTheGuidanceNamesNoParticularReadersKeys(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadGuidance(t)

	for _, forbidden := range []string{"NVDA+", "insert+", "capsLock+", "JAWSKey"} {
		if strings.Contains(document, forbidden) {
			t.Errorf("the guidance contains %q; it must describe the method, not one reader's keys",
				forbidden)
		}
	}
}

// Every screenreader:// URI a tool description points the agent at must exist.
// Read from the REGISTRY rather than from tools/list, so gated tools are covered
// without a connection: a broken pointer in press_gesture's description is
// exactly as bad whether or not this test bothered to connect a reader.
func TestEveryResourceAToolPointsAtIsPublished(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	published := h.ResourceURIs(t)

	for _, tool := range tools.BuildRegistry().All() {
		for _, uri := range resourceURIsIn(tool.Description()) {
			if !contains(published, uri) {
				t.Errorf("%s's description points at %s, which is not published; resources/list = %v",
					tool.Name(), uri, published)
			}
		}
	}
}

// resourceURIsIn pulls every screenreader:// URI out of a description, stopping
// each at the first character a URI cannot contain -- the descriptions embed them
// mid-sentence, so trailing punctuation has to come off. Note the colon is NOT a
// terminator: the scheme contains one, and treating it as punctuation truncates
// every URI to "screenreader".
func resourceURIsIn(description string) []string {
	const scheme = "screenreader://"
	var found []string
	for rest := description; ; {
		start := strings.Index(rest, scheme)
		if start < 0 {
			return found
		}
		rest = rest[start+len(scheme):]
		end := strings.IndexFunc(rest, func(r rune) bool {
			return strings.ContainsRune(" ,.;)\n\"'", r)
		})
		if end < 0 {
			end = len(rest)
		}
		found = append(found, scheme+rest[:end])
		rest = rest[end:]
	}
}

func contains(haystack []string, needle string) bool {
	for _, candidate := range haystack {
		if candidate == needle {
			return true
		}
	}
	return false
}
