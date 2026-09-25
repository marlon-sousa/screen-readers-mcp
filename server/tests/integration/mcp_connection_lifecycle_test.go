//go:build integration

// screenreader-mcp tests -- the agent-driven connection lifecycle, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario asserting only what an MCP client sees, with everything real but the bridge.
package integration_test

import (
	"slices"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

var ungated = []string{"connect_reader", "disconnect_reader", "list_readers", "status"}

func advertised(t *testing.T, h *testsupport.MCPHarness) []string {
	t.Helper()
	names := h.ToolNames(t)
	slices.Sort(names)
	return names
}

func TestAFreshServerAdvertisesEveryToolAndHasDialedNothing(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	names := advertised(t, h)
	for _, name := range ungated {
		if !slices.Contains(names, name) {
			t.Errorf("tools/list = %v, want the ungated %q present", names, name)
		}
	}
	if !slices.Contains(names, "get_speech") {
		t.Errorf("tools/list = %v, want gated tools advertised before connecting", names)
	}
	if got := h.Call(t, "get_speech", map[string]any{"since_index": 0}); !got.IsError {
		t.Error("get_speech ran with nothing connected")
	}

	if got := h.Bridge.Received(); len(got) != 0 {
		t.Errorf("the bridge was sent %v before any agent asked", got)
	}

	var status struct {
		State string `json:"state"`
		Live  *bool  `json:"live"`
	}
	h.Call(t, "status", nil).Decode(t, &status)
	if status.State != "disconnected" {
		t.Errorf("status state = %q, want disconnected", status.State)
	}
	if status.Live != nil {
		t.Errorf("live = %v, want absent when there is no session to ping", *status.Live)
	}
}

func TestListReadersReportsTheConfiguredReadersWithoutDialing(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	var listing struct {
		Readers []struct {
			Reader    string `json:"reader"`
			Endpoints []struct {
				Endpoint string `json:"endpoint"`
				Liveness string `json:"liveness"`
			} `json:"endpoints"`
		} `json:"readers"`
	}
	h.Call(t, "list_readers", nil).Decode(t, &listing)

	// The listing also carries every reader the binary ships a default for, so the harness's reader is found by name.
	var nvda *struct {
		Reader    string `json:"reader"`
		Endpoints []struct {
			Endpoint string `json:"endpoint"`
			Liveness string `json:"liveness"`
		} `json:"endpoints"`
	}
	for i := range listing.Readers {
		if listing.Readers[i].Reader == "nvda" {
			nvda = &listing.Readers[i]
		}
	}
	if nvda == nil || len(nvda.Endpoints) == 0 {
		t.Fatalf("readers = %+v, want the configured nvda reader among them", listing.Readers)
	}
	// Probing a TCP endpoint would occupy the bridge's single session slot.
	if nvda.Endpoints[0].Liveness != "unknown" {
		t.Errorf("liveness = %q, want unknown for a TCP endpoint", nvda.Endpoints[0].Liveness)
	}
	if got := h.Bridge.Received(); len(got) != 0 {
		t.Errorf("list_readers dialed the bridge: %v", got)
	}
}

func TestConnectingHandshakesAndDescribesTheSession(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})

	result := h.Connect(t)
	if result.IsError {
		t.Fatalf("connect_reader failed: %s", result.Text)
	}

	var connected struct {
		Reader        string   `json:"reader"`
		ReaderVersion string   `json:"readerVersion"`
		Endpoint      string   `json:"endpoint"`
		Capabilities  []string `json:"capabilities"`
		Mode          string   `json:"mode"`
		LogPath       string   `json:"logPath"`
	}
	result.Decode(t, &connected)

	if connected.Reader != "nvda" || connected.ReaderVersion != "2026.1" {
		t.Errorf("reader = %q %q, want what hello announced",
			connected.Reader, connected.ReaderVersion)
	}
	if !strings.HasPrefix(connected.Endpoint, "tcp:") {
		t.Errorf("endpoint = %q, want the one that answered", connected.Endpoint)
	}
	if connected.Mode != "silent" {
		t.Errorf("mode = %q, want silent", connected.Mode)
	}
	if connected.LogPath == "" {
		t.Error("session log path must be reported")
	}
	if got := h.Bridge.Received(); len(got) == 0 || got[0] != wire.CommandHello {
		t.Errorf("the bridge was sent %v; hello must come first", got)
	}
}

func TestStatusProvesALiveSessionOnTheWire(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	var status struct {
		State   string `json:"state"`
		Live    *bool  `json:"live"`
		Session *struct {
			Reader string `json:"reader"`
		} `json:"session"`
	}
	h.Call(t, "status", nil).Decode(t, &status)

	if status.State != "connected" {
		t.Errorf("state = %q, want connected", status.State)
	}
	if status.Live == nil || !*status.Live {
		t.Errorf("live = %v, want true", status.Live)
	}
	if status.Session == nil || status.Session.Reader != "nvda" {
		t.Errorf("session = %+v, want the live session described", status.Session)
	}
	if !slices.Contains(h.Bridge.Received(), wire.CommandPing) {
		t.Error("status answered without a round trip; it must ask the wire")
	}
}

func TestConnectingWhileConnectedIsRefused(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader failed: %s", got.Text)
	}

	second := h.Connect(t)
	if !second.IsError {
		t.Fatal("a second connect_reader succeeded")
	}
	if !strings.Contains(second.Text, "disconnect_reader") {
		t.Errorf("error = %q, want it to say what to do instead", second.Text)
	}

	var status struct {
		State string `json:"state"`
	}
	h.Call(t, "status", nil).Decode(t, &status)
	if status.State != "connected" {
		t.Errorf("state = %q after a refused connect, want the session untouched", status.State)
	}
}

func TestDisconnectingSendsByeAndLeavesTheToolListStanding(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	before := advertised(t, h)
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	if got := h.Call(t, "disconnect_reader", nil); got.IsError {
		t.Fatalf("disconnect_reader failed: %s", got.Text)
	}

	if !h.Bridge.SawBye() {
		t.Error("the bridge never saw bye")
	}
	if names := advertised(t, h); !slices.Equal(names, before) {
		t.Errorf("tools/list = %v, want it unchanged at %v", names, before)
	}
}

func TestAProtocolMismatchIsReportedAndTheServerKeepsRunning(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{ProtocolVersion: 99})

	result := h.Connect(t)
	if !result.IsError {
		t.Fatal("a protocol mismatch connected successfully")
	}
	if !strings.Contains(result.Text, "99") {
		t.Errorf("error = %q, want both versions named", result.Text)
	}

	var status struct {
		State  string `json:"state"`
		Reason string `json:"reason"`
	}
	h.Call(t, "status", nil).Decode(t, &status)
	if status.State != "incompatible" {
		t.Errorf("state = %q, want incompatible", status.State)
	}
	if !strings.Contains(status.Reason, "99") {
		t.Errorf("reason = %q, want it to keep naming the versions", status.Reason)
	}
}

func TestAnUnknownReaderNamesTheOnesThatExist(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	// A valid persona, since persona is validated first and would otherwise be the error reported.
	result := h.Call(t, "connect_reader", map[string]any{
		"reader": "narrator", "mode": "silent", "persona": "user",
	})
	if !result.IsError {
		t.Fatal("connecting to an unknown reader succeeded")
	}
	if !strings.Contains(result.Text, "nvda") {
		t.Errorf("error = %q, want the known readers listed", result.Text)
	}
	if got := h.Bridge.Received(); len(got) != 0 {
		t.Errorf("an unknown reader was dialed: %v", got)
	}
}

func TestReconnectingAfterADisconnectOpensAFreshSession(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}
	if got := h.Call(t, "disconnect_reader", nil); got.IsError {
		t.Fatalf("disconnect_reader: %s", got.Text)
	}
	if got := h.Connect(t); got.IsError {
		t.Fatalf("reconnecting: %s", got.Text)
	}

	var status struct {
		State string `json:"state"`
	}
	h.Call(t, "status", nil).Decode(t, &status)
	if status.State != "connected" {
		t.Errorf("state = %q, want connected again", status.State)
	}
}

func TestAToolFailureIsAReadableResultRatherThanAProtocolError(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	result := h.Call(t, "connect_reader", map[string]any{
		"reader": "nvda", "mode": "whispered",
	})
	if !result.IsError {
		t.Fatal("an invalid capture mode was accepted")
	}
	if !strings.Contains(result.Text, "silent") {
		t.Errorf("error = %q, want the valid modes listed in a readable result", result.Text)
	}
}
