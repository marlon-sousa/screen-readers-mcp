// screenreader-mcp domain -- the get_log / set_log_level tools' tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// The bridge owns the windows and maxEntries defaults, so ports.GetLogParams must keep omitempty on them or an omitted field is sent as zero.
package tools_test

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

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

func TestOmittedBoundsAreAbsentOnTheWireSoTheBridgeDefaultsApply(t *testing.T) {
	encoded, err := json.Marshal(ports.GetLogParams{})
	if err != nil {
		t.Fatalf("marshaling: %v", err)
	}

	// A zero anchor sent explicitly would collide with the command anchor and get every unanchored get_log refused.
	for _, field := range []string{
		"windows", "maxEntries", "commandId", "minLevel", "sincePosition", "lastSeconds",
	} {
		if strings.Contains(string(encoded), field) {
			t.Errorf("%q is present in %s; sending it unasked either overrides the "+
				"bridge's default with nothing or collides with another anchor", field, encoded)
		}
	}
}

func TestGetLogPassesThePositionAnchorThrough(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"sincePosition": 41}`); err != nil {
		t.Fatalf("get_log: %v", err)
	}

	got := built.LogReader.LastParams
	if got.SincePosition == nil || *got.SincePosition != 41 {
		t.Errorf("sincePosition = %v, want the cursor the agent held", got.SincePosition)
	}
	if got.CommandID != nil || got.LastSeconds != nil {
		t.Error("a position anchor also sent one of the other two anchors")
	}
}

func TestGetLogTreatsPositionZeroAsARealAnchor(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"sincePosition": 0}`); err != nil {
		t.Fatalf("get_log: %v", err)
	}

	got := built.LogReader.LastParams
	if got.SincePosition == nil || *got.SincePosition != 0 {
		t.Errorf("sincePosition = %v, want an explicit 0", got.SincePosition)
	}
}

func TestGetLogPassesTheTimeAnchorThrough(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"lastSeconds": 10.5}`); err != nil {
		t.Fatalf("get_log: %v", err)
	}

	got := built.LogReader.LastParams
	if got.LastSeconds == nil || *got.LastSeconds != 10.5 {
		t.Errorf("lastSeconds = %v, want 10.5", got.LastSeconds)
	}
}

func TestGetLogForwardsTwoAnchorsSoTheReaderCanRefuseThem(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"sincePosition": 3, "commandId": 7}`); err != nil {
		t.Fatalf("get_log: %v", err)
	}

	got := built.LogReader.LastParams
	if got.SincePosition == nil || got.CommandID == nil {
		t.Error("one of the two anchors was dropped, so the reader could not refuse them")
	}
}

func TestGetLogReturnsTheSliceTheReaderGave(t *testing.T) {
	from, to := 5, 7
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.SliceResult = ports.LogSliceResult{
		Text:            "IO - speech.speech.speak (09:17:40.724):\nSpeaking [hello]",
		Entries:         1,
		Matched:         4000,
		Truncated:       true,
		NextPosition:    412,
		FromCommandID:   &from,
		ToCommandID:     &to,
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
		NextPosition    int    `json:"nextPosition"`
		FromCommandID   *int   `json:"fromCommandId"`
		ToCommandID     *int   `json:"toCommandId"`
		CapturedAtLevel string `json:"capturedAtLevel"`
	}
	decode(t, result, &slice)

	if slice.Entries != 1 || slice.Matched != 4000 || !slice.Truncated {
		t.Errorf("entries/matched/truncated = %d/%d/%v, want 1/4000/true",
			slice.Entries, slice.Matched, slice.Truncated)
	}
	if slice.NextPosition != 412 {
		t.Errorf("nextPosition = %d, want 412", slice.NextPosition)
	}
	if slice.FromCommandID == nil || *slice.FromCommandID != 5 ||
		slice.ToCommandID == nil || *slice.ToCommandID != 7 {
		t.Errorf("command range = %v..%v, want 5..7", slice.FromCommandID, slice.ToCommandID)
	}
	if slice.CapturedAtLevel != "io" {
		t.Errorf("capturedAtLevel = %q, want io", slice.CapturedAtLevel)
	}
	if !strings.Contains(slice.Text, "Speaking [hello]") {
		t.Errorf("text = %q, want the reader's own line", slice.Text)
	}
}

func TestAPositionAnchoredSliceReportsNoCommandRange(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.SliceResult = ports.LogSliceResult{
		Text:            "INFO - core (09:17:40.724):\nfocus changed",
		Entries:         1,
		Matched:         1,
		NextPosition:    99,
		FromCommandID:   nil,
		ToCommandID:     nil,
		CapturedAtLevel: "info",
	}
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	result, err := call.Run(`{"sincePosition": 98}`)
	if err != nil {
		t.Fatalf("get_log: %v", err)
	}

	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshaling: %v", err)
	}
	if strings.Contains(string(encoded), "fromCommandId") {
		t.Errorf("%s reports a command range for a read that has none", encoded)
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

func TestGetLogSurfacesABridgeRefusal(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.Err = errors.New("unknown log field(s) levl: want any of ...")
	call := testsupport.NewToolCall(&tools.GetLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"fields":["levl"]}`); err == nil {
		t.Error("a rejected projection was reported as success")
	}
}

func TestGetLogPositionReturnsTheMarkTheReaderGave(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.MarkResult = ports.LogPosition{Position: 412, Time: "2026-07-31 09:17:40.724"}
	call := testsupport.NewToolCall(&tools.GetLogPosition{}).WithConnection(built.Connection)

	result, err := call.Run(`{}`)
	if err != nil {
		t.Fatalf("get_log_position: %v", err)
	}

	var mark struct {
		Position int    `json:"position"`
		Time     string `json:"time"`
	}
	decode(t, result, &mark)
	if mark.Position != 412 {
		t.Errorf("position = %d, want 412", mark.Position)
	}
	if mark.Time != "2026-07-31 09:17:40.724" {
		t.Errorf("time = %q, want the reader's own stamp", mark.Time)
	}
}

func TestGetLogPositionFetchesNoRecords(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.GetLogPosition{}).WithConnection(built.Connection)

	result, err := call.Run(`{}`)
	if err != nil {
		t.Fatalf("get_log_position: %v", err)
	}

	if built.LogReader.LastParams.SincePosition != nil || built.LogReader.PositionCall != 1 {
		t.Errorf("get_log_position read a slice: %d position calls, params %+v",
			built.LogReader.PositionCall, built.LogReader.LastParams)
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshaling: %v", err)
	}
	if strings.Contains(string(encoded), "text") {
		t.Errorf("%s carries records; the mark is meant to be cheap", encoded)
	}
}

func TestGetLogPositionIsRefusedWhenTheReaderDidNotAnnounceLog(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.GetLogPosition{}).WithConnection(built.Connection)

	_, err := call.Run(`{}`)

	var capability *tools.CapabilityError
	if !errors.As(err, &capability) {
		t.Fatalf("get_log_position = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityLog {
		t.Errorf("Capability = %q, want log", capability.Capability)
	}
}

func TestWaitForLogPassesTheFilterAndTimeoutThrough(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.WaitForLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"min_level":"error","contains":["COMError"],"timeout":30}`); err != nil {
		t.Fatalf("wait_for_log: %v", err)
	}

	got := built.LogReader.LastWait
	if got.MinLevel == nil || *got.MinLevel != "error" {
		t.Errorf("minLevel = %v, want error", got.MinLevel)
	}
	if len(got.Contains) != 1 || got.Contains[0] != "COMError" {
		t.Errorf("contains = %v, want [COMError]", got.Contains)
	}
	if got.Timeout != 30*time.Second {
		t.Errorf("timeout = %s, want 30s", got.Timeout)
	}
}

func TestWaitForLogReportsAMissAsAnAnswer(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.MatchResult = ports.LogMatch{Found: false, Position: 88}
	call := testsupport.NewToolCall(&tools.WaitForLog{}).WithConnection(built.Connection)

	result, err := call.Run(`{"min_level":"error"}`)
	if err != nil {
		t.Fatalf("a wait that matched nothing was reported as an error: %v", err)
	}

	var match struct {
		Found    bool   `json:"found"`
		Position int    `json:"position"`
		Text     string `json:"text"`
	}
	decode(t, result, &match)
	if match.Found {
		t.Error("found = true for a miss")
	}
	if match.Position != 88 {
		t.Errorf("position = %d, want the journal's current 88", match.Position)
	}
}

func TestWaitForLogReturnsTheMatchAndAPositionPastIt(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	built.LogReader.MatchResult = ports.LogMatch{
		Found:    true,
		Position: 89,
		Text:     "ERROR - core (09:17:40.724):\nCOMError from IAccessible",
	}
	call := testsupport.NewToolCall(&tools.WaitForLog{}).WithConnection(built.Connection)

	result, err := call.Run(`{"min_level":"error"}`)
	if err != nil {
		t.Fatalf("wait_for_log: %v", err)
	}

	var match struct {
		Found    bool   `json:"found"`
		Position int    `json:"position"`
		Text     string `json:"text"`
	}
	decode(t, result, &match)
	if !match.Found || match.Position != 89 {
		t.Errorf("found/position = %v/%d, want true/89", match.Found, match.Position)
	}
	if !strings.Contains(match.Text, "COMError") {
		t.Errorf("text = %q, want the record that triggered the wait", match.Text)
	}
}

func TestWaitForLogRefusesAWaitWithNoFilter(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.WaitForLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"timeout": 5}`); err == nil {
		t.Error("a wait with neither min_level nor contains was accepted")
	}
	if built.LogReader.WaitCalls != 0 {
		t.Error("the unfiltered wait still reached the reader")
	}
}

func TestWaitForLogClampsATimeoutThatWouldOutliveTheSession(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.WaitForLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"min_level":"error","timeout": 600}`); err != nil {
		t.Fatalf("wait_for_log: %v", err)
	}

	if built.LogReader.LastWait.Timeout > 110*time.Second {
		t.Errorf("timeout = %s, want it clamped to the reader's own limit",
			built.LogReader.LastWait.Timeout)
	}
}

func TestWaitForLogLeavesAnOmittedTimeoutToTheReader(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityLog)
	call := testsupport.NewToolCall(&tools.WaitForLog{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"min_level":"error"}`); err != nil {
		t.Fatalf("wait_for_log: %v", err)
	}

	if built.LogReader.LastWait.Timeout != 0 {
		t.Errorf("timeout = %s, want the zero that means 'the reader decides'",
			built.LogReader.LastWait.Timeout)
	}
}

func TestWaitForLogIsRefusedWhenTheReaderDidNotAnnounceLog(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.WaitForLog{}).WithConnection(built.Connection)

	_, err := call.Run(`{"min_level":"error"}`)

	var capability *tools.CapabilityError
	if !errors.As(err, &capability) {
		t.Fatalf("wait_for_log = %v, want a *CapabilityError", err)
	}
	if capability.Capability != entities.CapabilityLog {
		t.Errorf("Capability = %q, want log", capability.Capability)
	}
}

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

// Setting the reader's own floor to warning or error would silence warnings in the user's log for the rest of the session.
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
