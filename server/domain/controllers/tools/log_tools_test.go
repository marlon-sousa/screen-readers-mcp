// screenreader-mcp domain -- the get_log / set_log_level tools' tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Spec 0020's test plan, item 13: gating, parameter pass-through, and bounds.
//
// The pass-through tests earn their keep because of one non-obvious coupling:
// the DEFAULTS for `windows` and `maxEntries` live in the BRIDGE, not here. Go
// decodes an omitted integer as 0, and ports.GetLogParams tags both `omitempty`,
// so the zero is dropped from the wire object and the bridge applies 1 and 200.
// Drop the `omitempty` and every agent that omitted the field silently starts
// asking for zero windows and zero entries -- which is why it is asserted below
// rather than left to be discovered live.
package tools_test

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// -- get_log ------------------------------------------------------------------

func TestGetLogPassesEveryFilterThrough(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	_, err := call.Run(`{
		"commandId": 7,
		"windows": 3,
		"minLevel": "debug",
		"contains": ["COMError"],
		"exclude": ["speech.speech.speak"],
		"fields": ["level", "message"],
		"maxEntries": 50
	}`)
	if err != nil {
		t.Fatalf("get_log: %v", err)
	}

	got := built.LogReader.LastParams
	if got.CommandID == nil || *got.CommandID != 7 {
		t.Errorf("commandId = %v, want the anchor the agent named", got.CommandID)
	}
	if got.Windows != 3 {
		t.Errorf("windows = %d, want 3", got.Windows)
	}
	if got.MinLevel == nil || *got.MinLevel != "debug" {
		t.Errorf("minLevel = %v, want debug", got.MinLevel)
	}
	if len(got.Contains) != 1 || got.Contains[0] != "COMError" {
		t.Errorf("contains = %v, want [COMError]", got.Contains)
	}
	if len(got.Exclude) != 1 || got.Exclude[0] != "speech.speech.speak" {
		t.Errorf("exclude = %v, want [speech.speech.speak]", got.Exclude)
	}
	if len(got.Fields) != 2 || got.Fields[0] != "level" || got.Fields[1] != "message" {
		t.Errorf("fields = %v, want [level message]", got.Fields)
	}
	if got.MaxEntries != 50 {
		t.Errorf("maxEntries = %d, want 50", got.MaxEntries)
	}
}

// The anchor is OPTIONAL: omitted means "the most recently marked command", and
// that has to reach the bridge as an absent field rather than as command id 0.
func TestGetLogOmitsTheAnchorWhenTheAgentDidNot(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{}`); err != nil {
		t.Fatalf("get_log: %v", err)
	}

	if built.LogReader.LastParams.CommandID != nil {
		t.Errorf("commandId = %v, want nil so the bridge picks the latest",
			built.LogReader.LastParams.CommandID)
	}
}

// The coupling this file's header is about, asserted on the actual wire bytes.
func TestOmittedBoundsAreAbsentOnTheWireSoTheBridgeDefaultsApply(t *testing.T) {
	encoded, err := json.Marshal(ports.GetLogParams{})
	if err != nil {
		t.Fatalf("marshaling: %v", err)
	}

	for _, field := range []string{"windows", "maxEntries", "commandId", "minLevel"} {
		if strings.Contains(string(encoded), field) {
			t.Errorf("%q is present in %s; a zero sent explicitly would override the "+
				"bridge's default (1 window / 200 entries) with nothing", field, encoded)
		}
	}
}

func TestGetLogReturnsTheSliceTheReaderGave(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.SliceResult = ports.LogSliceResult{
		Text:            "IO - speech.speech.speak (09:17:40.724):\nSpeaking [hello]",
		Entries:         1,
		Matched:         4000,
		Truncated:       true,
		FromCommandID:   5,
		ToCommandID:     7,
		CapturedAtLevel: "io",
	}
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	result, err := call.Run(`{}`)
	if err != nil {
		t.Fatalf("get_log: %v", err)
	}

	var slice struct {
		Text            string `json:"text"`
		Entries         int    `json:"entries"`
		Matched         int    `json:"matched"`
		Truncated       bool   `json:"truncated"`
		FromCommandID   int    `json:"fromCommandId"`
		ToCommandID     int    `json:"toCommandId"`
		CapturedAtLevel string `json:"capturedAtLevel"`
	}
	decode(t, result, &slice)

	// matched >> entries with truncated set is the shape that tells an agent to
	// filter harder rather than to page blindly, so every part of it must survive.
	if slice.Entries != 1 || slice.Matched != 4000 || !slice.Truncated {
		t.Errorf("entries/matched/truncated = %d/%d/%v, want 1/4000/true",
			slice.Entries, slice.Matched, slice.Truncated)
	}
	if slice.FromCommandID != 5 || slice.ToCommandID != 7 {
		t.Errorf("command range = %d..%d, want 5..7", slice.FromCommandID, slice.ToCommandID)
	}
	if slice.CapturedAtLevel != "io" {
		t.Errorf("capturedAtLevel = %q, want io", slice.CapturedAtLevel)
	}
	if !strings.Contains(slice.Text, "Speaking [hello]") {
		t.Errorf("text = %q, want the reader's own line", slice.Text)
	}
}

func TestGetLogIsRefusedWhenTheReaderDidNotAnnounceLog(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	_, err := call.Run(`{}`)

	var capability *tools.CapabilityError
	if !errors.As(err, &capability) {
		t.Fatalf("get_log = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityLog {
		t.Errorf("Capability = %q, want log", capability.Capability)
	}
}

// The bridge refuses an unknown field name rather than quietly omitting a
// column; that refusal is the agent's answer, so it must not be swallowed here.
func TestGetLogSurfacesABridgeRefusal(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.Err = errors.New("unknown log field(s) levl: want any of ...")
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"fields":["levl"]}`); err == nil {
		t.Error("a rejected projection was reported as success")
	}
}

// -- set_log_level ------------------------------------------------------------

func TestSetLogLevelPassesTheLevelThrough(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.LevelResult = ports.LogLevelResult{Level: "debug", Previous: "info"}
	call := testsupport.NewToolCall(&tools.SetLogLevel{}).WithConnection(built.Connection)

	result, err := call.Run(`{"level":"debug"}`)
	if err != nil {
		t.Fatalf("set_log_level: %v", err)
	}

	if built.LogReader.LastLevel != "debug" {
		t.Errorf("level = %q, want debug", built.LogReader.LastLevel)
	}
	var level struct {
		Level    string `json:"level"`
		Previous string `json:"previous"`
	}
	decode(t, result, &level)
	// `previous` is what makes the change reversible by hand and auditable in the
	// transcript, so it is part of the contract rather than a nicety.
	if level.Level != "debug" || level.Previous != "info" {
		t.Errorf("level/previous = %q/%q, want debug/info", level.Level, level.Previous)
	}
}

func TestSetLogLevelIsRefusedWhenTheReaderDidNotAnnounceLog(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.SetLogLevel{}).WithConnection(built.Connection)

	_, err := call.Run(`{"level":"debug"}`)

	var capability *tools.CapabilityError
	if !errors.As(err, &capability) {
		t.Fatalf("set_log_level = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityLog {
		t.Errorf("Capability = %q, want log", capability.Capability)
	}
}

// warning/error are get_log minLevel filters. Setting the reader's own floor to
// either would silence warnings in the USER's log for the rest of the session,
// so the schema must not offer them -- an agent picks from the enum it is shown.
func TestSetLogLevelSchemaOffersOnlySettableLevels(t *testing.T) {
	var schema struct {
		Properties struct {
			Level struct {
				Enum []string `json:"enum"`
			} `json:"level"`
		} `json:"properties"`
	}
	if err := json.Unmarshal((&tools.SetLogLevel{}).InputSchema(), &schema); err != nil {
		t.Fatalf("decoding the schema: %v", err)
	}

	want := map[string]bool{"debug": true, "io": true, "debugwarning": true, "info": true}
	if len(schema.Properties.Level.Enum) != len(want) {
		t.Fatalf("enum = %v, want exactly %d settable levels",
			schema.Properties.Level.Enum, len(want))
	}
	for _, level := range schema.Properties.Level.Enum {
		if !want[level] {
			t.Errorf("enum offers %q, which cannot be set on the reader", level)
		}
	}
}

// get_log's minLevel is the opposite case: warning and error are exactly what an
// agent filters on most, so they must stay offered there.
func TestGetLogSchemaOffersEveryFilterLevel(t *testing.T) {
	var schema struct {
		Properties struct {
			MinLevel struct {
				Enum []string `json:"enum"`
			} `json:"minLevel"`
		} `json:"properties"`
	}
	if err := json.Unmarshal((&tools.GetLog{}).InputSchema(), &schema); err != nil {
		t.Fatalf("decoding the schema: %v", err)
	}

	for _, want := range []string{"debug", "io", "debugwarning", "info", "warning", "error"} {
		found := false
		for _, level := range schema.Properties.MinLevel.Enum {
			if level == want {
				found = true
			}
		}
		if !found {
			t.Errorf("minLevel enum is missing %q: %v", want, schema.Properties.MinLevel.Enum)
		}
	}
}

func TestSetLogLevelSurfacesABridgeRefusal(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.Err = errors.New("log level 'error' cannot be set on the reader")
	call := testsupport.NewToolCall(&tools.SetLogLevel{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"level":"error"}`); err == nil {
		t.Error("a refused level was reported as success")
	}
}
