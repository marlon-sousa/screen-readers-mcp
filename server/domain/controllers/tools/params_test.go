// screenreader-mcp domain -- decodeParams' tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Spec 0034 (board entry 11.26). What is being pinned is the hint's SCOPE as
// much as its content: a hypothesis that shows up on every decode failure is
// noise, and noise is skipped, so the tests that matter most here are the ones
// asserting where it does NOT appear.
//
// In-package, because decodeParams is the package's own boilerplate and has no
// business being exported to be tested.
package tools

import (
	"encoding/json"
	"strings"
	"testing"
)

// connectish stands in for a tool's params struct: one optional boolean of the
// shape that caused the run's failure, plus neighbours of other types.
type connectish struct {
	Reader    string   `json:"reader"`
	Normalize bool     `json:"normalize"`
	Timeout   int      `json:"timeout"`
	Modes     []string `json:"modes"`
}

// The failure the entry was opened for, end to end: a string where the schema
// published by the running server says boolean.
func TestATypeMismatchGainsTheHypothesisAndKeepsTheOriginalDetail(t *testing.T) {
	var into connectish
	err := decodeParams(json.RawMessage(`{"reader":"nvda","normalize":"true"}`), &into)
	if err == nil {
		t.Fatal("a string for a boolean decoded without error")
	}
	message := err.Error()

	// The precise part survives: it is what a developer fixes from.
	for _, want := range []string{`"normalize":"true"`, "cannot unmarshal string"} {
		if !strings.Contains(message, want) {
			t.Errorf("the original detail lost %q:\n%s", want, message)
		}
	}
	// And the hypothesis is added, hedged, with both remedies named.
	for _, want := range []string{
		`value for "normalize" is a string, but this tool takes a boolean`,
		"may be holding a tool schema older than this server build",
		"screenreader://tools",
		"only the human at the keyboard",
	} {
		if !strings.Contains(message, want) {
			t.Errorf("the hint is missing %q:\n%s", want, message)
		}
	}
}

// The Go type is translated into the vocabulary the published schemas are
// written in, because the whole hint exists to send the reader to one.
func TestTheHintNamesTheTypeAsTheSchemaSpellsIt(t *testing.T) {
	for _, hint := range []struct {
		name      string
		arguments string
		want      string
	}{
		{"number for boolean", `{"normalize":1}`,
			`value for "normalize" is a number, but this tool takes a boolean`},
		{"boolean for string", `{"reader":true}`,
			`value for "reader" is a boolean, but this tool takes a string`},
		{"string for number", `{"timeout":"30"}`,
			`value for "timeout" is a string, but this tool takes a number`},
		{"string for array", `{"modes":"live"}`,
			`value for "modes" is a string, but this tool takes an array`},
	} {
		t.Run(hint.name, func(t *testing.T) {
			var into connectish
			err := decodeParams(json.RawMessage(hint.arguments), &into)
			if err == nil {
				t.Fatalf("%s decoded without error", hint.arguments)
			}
			if !strings.Contains(err.Error(), hint.want) {
				t.Errorf("want %q in:\n%s", hint.want, err.Error())
			}
		})
	}
}

// SCOPE. Malformed JSON is not evidence of a stale schema, and attaching the
// hypothesis to it would teach the next reader to skip the hypothesis.
func TestMalformedJSONDoesNotGainTheHint(t *testing.T) {
	var into connectish
	err := decodeParams(json.RawMessage(`{"reader":`), &into)
	if err == nil {
		t.Fatal("truncated JSON decoded without error")
	}
	if strings.Contains(err.Error(), "screenreader://tools") {
		t.Errorf("malformed JSON collected the staleness hint:\n%s", err.Error())
	}
}

// The two cases that produce no error at all, asserted so the hint's honest
// limit is a fact of the code rather than a claim in the spec. A field no struct
// declares is IGNORED, and an absent one is left at its zero value -- so the
// mirror failure (a client still sending a parameter this build removed) is
// silent, and so is the dangerous middle row of the spec's table.
func TestAnUnknownFieldAndAnAbsentOneDoNotFailAtAll(t *testing.T) {
	var into connectish
	if err := decodeParams(json.RawMessage(`{"reader":"nvda","retired":"x"}`), &into); err != nil {
		t.Fatalf("an unknown field failed to decode, so the hint's scope note is wrong: %v", err)
	}
	if into.Reader != "nvda" {
		t.Errorf("reader = %q, want the declared field still decoded", into.Reader)
	}
	if into.Normalize {
		t.Error("normalize came back true; an absent field must stay at its zero value")
	}
}

// EMPTY IS VALID, and it predates this entry: a tool whose parameters are all
// optional is called with no `arguments` member at all.
func TestNoArgumentsIsNotAFailure(t *testing.T) {
	var into connectish
	if err := decodeParams(nil, &into); err != nil {
		t.Fatalf("a call with no arguments was rejected: %v", err)
	}
}
