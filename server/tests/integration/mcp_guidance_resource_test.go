//go:build integration

// screenreader-mcp tests -- screenreader://guidance, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario for screenreader://guidance.
package integration_test

import (
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

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

// Phrases rather than sentences, so rewording the document does not fail this test.
func TestTheGuidanceStatesTheRuleAndTheSettleStep(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadGuidance(t)

	for _, want := range []string{
		"delivery, plus whatever arrived in time",
		"you are about to do it twice",
		"wait_for_speech_to_finish",
		"ask_user",
		"the desktop's job",
		"discrete press and release",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the guidance never mentions %q", want)
		}
	}
}

func TestTheGuidancePointsAtTheToolsDocument(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	if !strings.Contains(h.ReadGuidance(t), "screenreader://tools") {
		t.Error("the guidance never mentions screenreader://tools, so an agent reading " +
			"the method document is not told the reference document exists")
	}
}

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

func TestTheGuidanceNamesNoParticularDesktopsKeys(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadGuidance(t)

	for _, forbidden := range []string{"alt+tab", "windows+tab", "control+alt+tab", "command+tab"} {
		if strings.Contains(strings.ToLower(document), forbidden) {
			t.Errorf("the guidance contains %q; it must describe the method, not one desktop's keys",
				forbidden)
		}
	}
}

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

// The colon is not a terminator: the scheme contains one.
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

func TestTheGuidanceProfilesEveryPersonaTheServerAccepts(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadGuidance(t)

	for _, persona := range entities.AllPersonas() {
		if !strings.Contains(document, persona.String()) {
			t.Errorf("the guidance never names the %q persona", persona)
		}
		if !strings.Contains(document, persona.Question()) {
			t.Errorf("the guidance never asks %q's question, %q", persona, persona.Question())
		}
		if !strings.Contains(document, persona.Profile()) {
			t.Errorf("the guidance does not carry %q's profile; it is composed from "+
				"the domain precisely so the two cannot drift", persona)
		}
	}
}

func TestTheGuidanceStatesTheVocabularyRuleAndWhenToChoose(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	document := h.ReadGuidance(t)

	for _, want := range []string{
		"re-reads what is already there",
		"reaches what focus cannot",
		"before you connect",
		"ask them before you connect",
	} {
		if !strings.Contains(strings.ToLower(document), strings.ToLower(want)) {
			t.Errorf("the guidance never says %q", want)
		}
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
