// screenreader-mcp adapters -- no reader's syntax in the text an agent reads.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Spec 0022 A.6 and A.7. THE SERVER OWNS THE RULE AND THE READER OWNS THE
// INSTANCES, and this is what makes that structural instead of remembered.
//
// WHY IT EXISTS. The rule is older than this test: guidance_resource.go has said
// since spec 0013 that the method document says "your reader's report-focus
// command", never "NVDA+Tab", because spec 0005 principle 2 forbids this server
// learning one reader's key map. It was applied to that one resource and to
// nothing else, because nothing enforced it anywhere else -- so it held where
// somebody remembered it and drifted where nobody did. An outside reader found
// the drift and we could not (board entry 11.24(a)): press_gesture's own
// description spelled a gesture "NVDA+f7" while the reader's document gave the
// literal form as "nvda+tab".
//
// It matters MORE under spec 0022's option (c) than it did before. Every tool is
// advertised from startup now, so press_gesture's description is read BEFORE any
// reader is chosen. An NVDA example there does not merely go stale -- it presumes
// a reader nobody has selected, in the always-visible surface, on a session that
// may turn out to be JAWS or TalkBack.
//
// WHY IT READS THE DECLARED SURFACE AND NOT THE SOURCE. A grep over server/ was
// the obvious proposal and it fails three ways:
//
//  1. The blocklist cannot be completed. Naming NVDA and JAWS catches today's
//     drift and misses the reader nobody has written yet.
//  2. "Reader syntax" is not lexically well-defined: `control+home` is a Windows
//     convention, `downArrow` is a key name.
//  3. IT WOULD FAIL ON THE FILE THAT DOCUMENTS THE RULE. guidance_resource.go
//     contains the literal "NVDA+Tab" inside the comment forbidding it; so do
//     press_gesture.go's header and gesture_sender.go's port doc. A gate that
//     fires on correct code is a gate somebody turns off.
//
// The corpus here is the DECLARED SURFACE: every tool's description and both
// schemas, plus the documents this adapter serves. It is bounded, it is exactly
// the bytes an agent reads, and comments fall outside it for free -- which
// dissolves (3) completely. Spec 0031 already built the enumeration.
//
// TWO PRONGS, so that neither has to be complete:
//
//   - Reader NAMES, taken from the CONFIGURATION rather than from a list here.
//     Self-maintaining: add a reader to defaults.json and this starts policing
//     its name for free, which is (1) solved without the source naming the
//     future.
//   - Key-combination SHAPE, which names no reader at all and so catches
//     `control+home` and an unwritten TalkBack spelling alike -- (2) solved.
//
// This is not a new mechanism. It is a second instance of the one spec 0031
// shipped in output_schema_test.go: assert a property over every tool in the
// registry, and fail when a new tool does not participate.
package mcp

import (
	"regexp"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/config"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
)

// placeholders are the reader-AGNOSTIC combination shapes the surface is allowed
// to use, because saying "a modifier and a key" is how you describe a gesture
// without naming one.
//
// SMALL AND EXPLICIT ON PURPOSE. This is an allowlist of things we deliberately
// wrote, which is reviewable; the blocklist rejected in the header was a list of
// things somebody else might write, which is not. Adding an entry here should
// feel like a decision -- if a new one is a real keystroke, it belongs in the
// reader's own document instead.
var placeholders = []string{
	"modifier+key",
}

// combination matches a key-combination shape: two or more `+`-joined tokens.
//
// Deliberately loose. It over-matches ordinary prose containing a plus sign,
// which is why the failure message quotes the match -- a false positive is
// cheap to read and to fix, and the alternative (a precise matcher that knows
// what a key name looks like) would be a reader's key map living here, which is
// the exact thing this file exists to keep out.
var combination = regexp.MustCompile(`\b[A-Za-z][A-Za-z0-9]*(?:\+[A-Za-z][A-Za-z0-9]*)+\b`)

// declaredSurface is every string this server puts in front of an agent.
func declaredSurface(t *testing.T) map[string]string {
	t.Helper()
	surface := map[string]string{}
	for _, tool := range tools.BuildRegistry().All() {
		// The COMPOSED description, exactly as the tool list carries it: the
		// precondition sentence is agent-facing text too, so it is held to the
		// same rule as everything else here.
		surface[tool.Name()+" description"] = precondition(tool) + tool.Description()
		surface[tool.Name()+" input schema"] = string(tool.InputSchema())
		surface[tool.Name()+" output schema"] = string(tool.OutputSchema())
	}
	// The documents this adapter serves, which are agent-facing for exactly the
	// same reason and reader-agnostic by their own charter.
	surface["screenreader://guidance preamble"] = guidancePreamble
	surface["screenreader://guidance method"] = guidanceMethod
	surface["screenreader://tools frame"] = toolsFrame
	surface["screenreader://reader-guidance frame"] = readerGuidanceFrame
	surface["reader-guidance unrecognised"] = readerGuidanceUnrecognised
	surface["reader-guidance no-session"] = readerGuidanceNoSession
	surface["reader-guidance unavailable"] = readerGuidanceUnavailable
	return surface
}

// PRONG ONE: no configured reader's name appears in the declared surface.
//
// The names come from the loader's embedded defaults, so this test learns about
// a new reader the moment the configuration does.
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

// PRONG TWO: no key-combination shape, whoever's it is.
//
// This is the prong that survives a reader we have never heard of, because it
// asks what the text LOOKS like rather than which product it belongs to.
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

// Every allowlisted placeholder must still be one this regexp would catch --
// otherwise the entry is dead, and a dead allowlist entry hides the day somebody
// changes the matcher and quietly stops enforcing anything.
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
