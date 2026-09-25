// screenreader-mcp domain -- decodeParams' tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// In-package, because decodeParams is unexported.
package tools

import (
	"encoding/json"
	"strings"
	"testing"
)

type connectish struct {
	Reader    string   `json:"reader"`
	Normalize bool     `json:"normalize"`
	Timeout   int      `json:"timeout"`
	Modes     []string `json:"modes"`
}

func TestATypeMismatchGainsTheHypothesisAndKeepsTheOriginalDetail(t *testing.T) {
	var into connectish
	err := decodeParams(json.RawMessage(`{"reader":"nvda","normalize":"true"}`), &into)
	if err == nil {
		t.Fatal("a string for a boolean decoded without error")
	}
	message := err.Error()

	for _, want := range []string{`"normalize":"true"`, "cannot unmarshal string"} {
		if !strings.Contains(message, want) {
			t.Errorf("the original detail lost %q:\n%s", want, message)
		}
	}
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

func TestNoArgumentsIsNotAFailure(t *testing.T) {
	var into connectish
	if err := decodeParams(nil, &into); err != nil {
		t.Fatalf("a call with no arguments was rejected: %v", err)
	}
}
