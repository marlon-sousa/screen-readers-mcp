// screenreader-mcp adapters -- no reader's syntax in the text an agent reads.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package mcp

import (
	"regexp"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/config"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
)

// placeholders are the reader-agnostic shapes the surface may use; a real keystroke belongs in the reader's own document instead.
var placeholders = []string{
	"modifier+key",
}

// combination deliberately over-matches prose with a plus sign; the failure message quotes the match so a false positive is cheap to fix.
var combination = regexp.MustCompile(`\b[A-Za-z][A-Za-z0-9]*(?:\+[A-Za-z][A-Za-z0-9]*)+\b`)

func declaredSurface(t *testing.T) map[string]string {
	t.Helper()
	surface := map[string]string{}
	for _, tool := range tools.BuildRegistry().All() {
		surface[tool.Name()+" description"] = precondition(tool) + tool.Description()
		surface[tool.Name()+" input schema"] = string(tool.InputSchema())
		surface[tool.Name()+" output schema"] = string(tool.OutputSchema())
	}
	surface["screenreader://guidance preamble"] = guidancePreamble
	surface["screenreader://guidance method"] = guidanceMethod
	surface["screenreader://tools frame"] = toolsFrame
	surface["screenreader://reader-guidance frame"] = readerGuidanceFrame
	surface["reader-guidance unrecognised"] = readerGuidanceUnrecognised
	surface["reader-guidance no-session"] = readerGuidanceNoSession
	surface["reader-guidance unavailable"] = readerGuidanceUnavailable
	return surface
}

func TestNoConfiguredReaderIsNamedInTheDeclaredSurface(t *testing.T) {
	loaded, err := config.Load(config.Options{})
	if err != nil {
		t.Fatalf("loading the embedded defaults: %v", err)
	}
	readers := loaded.Readers()
	if len(readers) == 0 {
		t.Fatal("the embedded defaults name no readers; this test would prove nothing")
	}

	for where, text := range declaredSurface(t) {
		lowered := strings.ToLower(text)
		for _, reader := range readers {
			if strings.Contains(lowered, strings.ToLower(reader.Name)) {
				t.Errorf("%s names the reader %q.\n"+
					"The server owns the RULE and the reader owns the INSTANCES "+
					"(spec 0005 principle 2, spec 0022 A.6). Say what shape a "+
					"gesture has and point at screenreader://reader-guidance, "+
					"which the connect_reader result now carries in full.",
					where, reader.Name)
			}
		}
	}
}

func TestNoKeyCombinationIsSpelledInTheDeclaredSurface(t *testing.T) {
	for where, text := range declaredSurface(t) {
		for _, match := range combination.FindAllString(text, -1) {
			if isPlaceholder(match) {
				continue
			}
			t.Errorf("%s spells the key combination %q.\n"+
				"Reader syntax belongs in the reader's own document, which the "+
				"bridge GENERATES out of the reader and which reaches the agent "+
				"in connect_reader's result. This text is read before any reader "+
				"is chosen, so a combination here presumes one nobody selected.",
				where, match)
		}
	}
}

// A placeholder the matcher would not catch is a dead allowlist entry.
func TestEveryPlaceholderIsOneTheMatcherWouldOtherwiseCatch(t *testing.T) {
	for _, allowed := range placeholders {
		if !combination.MatchString(allowed) {
			t.Errorf("the placeholder %q is not a combination shape at all; "+
				"it is allowlisting nothing and should be deleted", allowed)
		}
	}
}

func isPlaceholder(match string) bool {
	for _, allowed := range placeholders {
		if strings.EqualFold(match, allowed) {
			return true
		}
	}
	return false
}
