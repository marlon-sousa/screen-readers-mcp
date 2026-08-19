//go:build integration

// screenreader-mcp tests -- screenreader://session-record, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario. Spec 0021's item 15: the server's own record of a
// session, built from traffic that already passes through it, covering a whole
// session WITH NO BRIDGE CALL ADDED. That last clause is the deliverable and the
// hardest thing to check -- so this scenario counts what the bridge was asked as
// well as what the record holds, and fails if the record cost a round trip.
//
// The record exists because connect_reader hands an agent `logPath` and nothing
// else, and for a remote bridge that names a file the agent cannot open. It does
// NOT replace the reader-side transcript: see domain/entities/session_record.go
// for the two audiences.
package integration_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// Like the info resource, it exists before anything is connected: an agent
// asking what it has done deserves an empty list, not a missing resource.
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
	// The note is how an agent learns the reader-side transcript exists at all.
	if document["note"] == nil || document["note"] == "" {
		t.Error("the record carries no note explaining what it is not")
	}
}

// The deliverable, in one scenario: connect, work, read the record back, and
// find the whole sequence in it.
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

	// Reading the record must cost the bridge NOTHING: it is built from traffic
	// that already happened, which is the whole reason it needs no wire surface.
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

// What was asked and what came back, not bare tool names: a record an agent
// cannot reconstruct a session from is not worth publishing.
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

// -- the persona on the document (spec 0029) ----------------------------------

// The declaration is what makes a record interpretable: the same call log is a
// pass from one stance and a finding from another.
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

// THE REASON IT IS ON THE DOCUMENT and not left to be read out of the recorded
// connect_reader call: the record is BOUNDED and evicts oldest-first, so in a
// long session the very call carrying the declaration ages out of the record
// that exists to preserve it. Driven past the cap here rather than argued.
func TestThePersonaSurvivesTheConnectCallAgeingOutOfTheRecord(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.ConnectAs(t, "expert"); got.IsError {
		t.Fatalf("connect_reader failed: %s", got.Text)
	}

	// One more call than the record holds, so the connect is certainly gone.
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
