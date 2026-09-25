//go:build integration

// screenreader-mcp tests -- screenreader://session-record, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario for screenreader://session-record, which must cost the bridge no round trip.
package integration_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestTheSessionRecordExistsBeforeAnythingIsConnected(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	document := h.ReadSessionRecord(t)

	calls, ok := document["calls"].([]any)
	if !ok {
		t.Fatalf("calls = %v, want an empty list rather than null", document["calls"])
	}
	if len(calls) != 0 {
		t.Errorf("calls = %v, want nothing recorded before any tool ran", calls)
	}
	if document["note"] == nil || document["note"] == "" {
		t.Error("the record carries no note explaining what it is not")
	}
}

func TestTheRecordCoversAWholeSessionWithNoBridgeCallAdded(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
		Synth:  "espeak",
	})
	h.Bridge.Handle(wire.CommandGetSpeech, func(json.RawMessage) (any, error) {
		return wire.SpeechResult{
			Entries:   []wire.SpeechEntry{{Text: "Edit  blank", Index: 1, LogPosition: 12}},
			FromIndex: 0,
			ToIndex:   1,
		}, nil
	})

	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader failed: %s", got.Text)
	}

	before := len(h.Bridge.Received())
	if got := h.Call(t, "get_speech", map[string]any{"since_index": 0}); got.IsError {
		t.Fatalf("get_speech failed: %s", got.Text)
	}
	if got := h.Call(t, "status", nil); got.IsError {
		t.Fatalf("status failed: %s", got.Text)
	}
	afterWork := len(h.Bridge.Received())

	document := h.ReadSessionRecord(t)
	afterReading := len(h.Bridge.Received())

	if afterReading != afterWork {
		t.Errorf("reading the record sent %d command(s) to the bridge, want none",
			afterReading-afterWork)
	}
	if afterWork <= before {
		t.Fatal("the scenario sent no commands at all, so it proves nothing")
	}

	var names []string
	for _, entry := range document["calls"].([]any) {
		names = append(names, entry.(map[string]any)["tool"].(string))
	}
	for _, want := range []string{"connect_reader", "get_speech", "status"} {
		found := false
		for _, name := range names {
			if name == want {
				found = true
			}
		}
		if !found {
			t.Errorf("the record is missing %q; it holds %v", want, names)
		}
	}
}

func TestTheRecordKeepsWhatWasAskedAndWhatCameBack(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	h.Bridge.Handle(wire.CommandGetSpeech, func(json.RawMessage) (any, error) {
		return wire.SpeechResult{
			Entries:   []wire.SpeechEntry{{Text: "Documents  list", Index: 1, LogPosition: 12}},
			FromIndex: 0,
			ToIndex:   1,
		}, nil
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader failed: %s", got.Text)
	}
	if got := h.Call(t, "get_speech", map[string]any{"since_index": 0}); got.IsError {
		t.Fatalf("get_speech failed: %s", got.Text)
	}

	var recorded map[string]any
	for _, entry := range h.ReadSessionRecord(t)["calls"].([]any) {
		call := entry.(map[string]any)
		if call["tool"] == "get_speech" {
			recorded = call
		}
	}
	if recorded == nil {
		t.Fatal("get_speech is not in the record")
	}

	params, _ := recorded["params"].(string)
	result, _ := recorded["result"].(string)
	if params == "" || result == "" {
		t.Fatalf("recorded %+v, want both the request and the answer", recorded)
	}
	if !strings.Contains(result, "Documents  list") {
		t.Errorf("result = %q, want what the reader actually said", result)
	}
}

func TestTheRecordSaysWhatTheSessionIsStandingInFor(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.ConnectAs(t, "validator"); got.IsError {
		t.Fatalf("connect_reader failed: %s", got.Text)
	}

	if got := h.ReadSessionRecord(t)["persona"]; got != "validator" {
		t.Errorf("persona = %v, want validator", got)
	}
}

// The record evicts oldest-first, so the persona lives on the document and not only in the recorded connect call.
func TestThePersonaSurvivesTheConnectCallAgeingOutOfTheRecord(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.ConnectAs(t, "expert"); got.IsError {
		t.Fatalf("connect_reader failed: %s", got.Text)
	}

	for i := 0; i < entities.MaxRecordedCalls; i++ {
		if got := h.Call(t, "status", map[string]any{}); got.IsError {
			t.Fatalf("status failed on call %d: %s", i, got.Text)
		}
	}

	document := h.ReadSessionRecord(t)
	for _, entry := range document["calls"].([]any) {
		if entry.(map[string]any)["tool"] == "connect_reader" {
			t.Fatal("connect_reader is still in the record; this test proves nothing " +
				"unless it has been evicted")
		}
	}
	if got := document["persona"]; got != "expert" {
		t.Errorf("persona = %v, want expert to outlive the call that declared it", got)
	}
}
