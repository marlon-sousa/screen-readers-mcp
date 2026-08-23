//go:build integration

// screenreader-mcp tests -- screenreader://info, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario. The resource is spec 0013's second capability
// mechanism -- SURFACE THE READER -- so what matters is that an agent reading it
// learns which reader it is driving and what that reader announced, at both ends
// of the connection lifecycle.
package integration_test

import (
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// With nothing connected the resource still exists and says so: "nothing, and
// here is why" is an answer, and a missing resource is not.
func TestTheInfoResourceExistsBeforeAnythingIsConnected(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	document := h.ReadInfo(t)

	if document["state"] != "disconnected" {
		t.Errorf("state = %v, want disconnected", document["state"])
	}
	if _, present := document["reader"]; present {
		t.Errorf("reader = %v, want absent when nothing is connected", document["reader"])
	}
}

// Acceptance criterion 5's second half.
func TestTheInfoResourceReportsTheConnectedReader(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
		Synth:  "espeak",
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	document := h.ReadInfo(t)

	if document["state"] != "connected" {
		t.Errorf("state = %v, want connected", document["state"])
	}
	if document["reader"] != "nvda" {
		t.Errorf("reader = %v, want nvda -- this is what lets the agent apply "+
			"what it already knows about the reader", document["reader"])
	}
	if document["readerVersion"] != "2026.1" {
		t.Errorf("readerVersion = %v, want 2026.1", document["readerVersion"])
	}
	if document["mode"] != "silent" {
		t.Errorf("mode = %v, want the capture mode in effect", document["mode"])
	}
	if document["synth"] != "espeak" {
		t.Errorf("synth = %v, want the reader's synthesizer", document["synth"])
	}

	capabilities, ok := document["capabilities"].([]any)
	if !ok || len(capabilities) == 0 {
		t.Fatalf("capabilities = %v, want what the reader announced", document["capabilities"])
	}

	// The transcript is reported as a PATH; its contents are deliberately not
	// exposed as a resource in v1. The reader's own log is NOT a path any more
	// (spec 0020 superseded 0009's capture file), so this document must carry
	// no readerLogPath at all rather than an empty one.
	if document["logPath"] == nil {
		t.Errorf("logPath = %v, want the session transcript's path", document["logPath"])
	}
	if _, present := document["readerLogPath"]; present {
		t.Errorf("readerLogPath = %v, want it absent: 0020 replaced the capture file "+
			"with the journal behind get_log", document["readerLogPath"])
	}
	if document["protocolVersion"] == nil {
		t.Error("protocolVersion is missing")
	}
}

// A reader that announced less is described honestly, without this server
// inventing capabilities on its behalf.
func TestTheInfoResourceReportsOnlyWhatTheReaderAnnounced(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Capabilities: []wire.Capability{wire.CapabilitySpeech},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	document := h.ReadInfo(t)

	capabilities, _ := document["capabilities"].([]any)
	if len(capabilities) != 1 || capabilities[0] != "speech" {
		t.Errorf("capabilities = %v, want exactly what hello announced", capabilities)
	}
}

// After a disconnect it goes back to describing nothing, rather than leaving a
// stale reader behind for the agent to trust.
func TestTheInfoResourceForgetsTheReaderOnDisconnect(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}
	if got := h.Call(t, "disconnect_reader", nil); got.IsError {
		t.Fatalf("disconnect_reader: %s", got.Text)
	}

	document := h.ReadInfo(t)

	if document["state"] != "disconnected" {
		t.Errorf("state = %v, want disconnected", document["state"])
	}
	if _, present := document["reader"]; present {
		t.Errorf("reader = %v, want the reader forgotten", document["reader"])
	}
}

// The persona belongs beside the reader for the same reason the reader is here:
// an agent asking "what am I driving?" also needs "what am I standing in for?",
// and the two together are what make a finding interpretable afterwards
// (spec 0029).
func TestTheInfoResourceReportsThePersona(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.ConnectAs(t, "validator"); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	if got := h.ReadInfo(t)["persona"]; got != "validator" {
		t.Errorf("persona = %v, want validator", got)
	}
}

func TestThePersonaIsAbsentWithNoSession(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	if got, present := h.ReadInfo(t)["persona"]; present {
		t.Errorf("persona = %v, want absent when no session is standing in for anything", got)
	}
}

// Attendance belongs beside the persona for the same reason the persona belongs
// beside the reader: an agent asking "what am I driving?" and "what am I
// standing in for?" also has to ask "is anybody listening?", and all three are
// one question asked three ways (spec 0038, entry 11.30).
//
// It is a SESSION CONSTANT, republished because the agent's memory of it is not
// constant. Before this, an agent whose context had been compacted could recover
// it only by disconnecting and reconnecting.
func TestTheInfoResourceReportsAttendance(t *testing.T) {
	attended := true
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader:   wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
		Attended: &attended,
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	sentence, _ := h.ReadInfo(t)["attendance"].(string)
	if sentence == "" {
		t.Fatal("attendance is missing; an agent that lost its context cannot ask again")
	}
	if !strings.Contains(sentence, "HUMAN IS EXPECTED") {
		t.Errorf("attendance = %q, want the sentence that says somebody is there", sentence)
	}
}

// The other side of the same fact. This is the one that fails towards silence if
// it is wrong in the opposite direction -- an agent told nobody is there when
// somebody is stops narrating to a person who can hear nothing else.
func TestTheInfoResourceReportsAnUnattendedMachine(t *testing.T) {
	attended := false
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{Attended: &attended})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	sentence, _ := h.ReadInfo(t)["attendance"].(string)
	if !strings.Contains(sentence, "UNATTENDED") {
		t.Errorf("attendance = %q, want the sentence that says the room is empty", sentence)
	}
}

// THE ANTI-DRIFT ASSERTION. The two surfaces share SilenceCap.Sentence, which is
// the real guarantee; this is the tripwire that fires if anyone ever renders one
// of them separately. A shortened form here was considered and rejected (0038):
// the sentence is written to be acted on, and an agent recovering from a
// compaction needs the instruction more than one reading it at connect, not less.
func TestInfoAndConnectReportTheSameAttendanceSentence(t *testing.T) {
	attended := true
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{Attended: &attended})

	connected := h.Connect(t)
	if connected.IsError {
		t.Fatalf("connect_reader: %s", connected.Text)
	}
	var result struct {
		SilenceCap string `json:"silenceCap"`
	}
	connected.Decode(t, &result)

	if got, _ := h.ReadInfo(t)["attendance"].(string); got != result.SilenceCap {
		t.Errorf("the two renderings have drifted:\n  info:    %q\n  connect: %q", got, result.SilenceCap)
	}
}

func TestAttendanceIsAbsentWithNoSession(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	if got, present := h.ReadInfo(t)["attendance"]; present {
		t.Errorf("attendance = %v, want absent: with no session there is nobody to be there", got)
	}
}
