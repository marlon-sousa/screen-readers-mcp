//go:build integration

// screenreader-mcp tests -- screenreader://info, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario for screenreader://info across the connection lifecycle.
package integration_test

import (
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

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

// The two surfaces share SilenceCap.Sentence; this fires if either is ever rendered separately.
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
