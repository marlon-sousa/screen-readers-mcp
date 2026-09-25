//go:build integration

// screenreader-mcp tests -- capability enforcement, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario at the MCP boundary, with everything below the client real except the bridge.
// Enforcement is keyed on capability strings, never reader names, so every bridge here is called "nvda".
package integration_test

import (
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

var everyGatedTool = []string{
	"announce", "ask_user", "get_braille", "get_config", "get_document_snapshot",
	"get_focus_info",
	"get_last_speech", "get_log", "get_log_position", "get_next_speech_index",
	"get_speech", "get_state", "press_gesture", "run_sequence", "set_config",
	"set_log_level", "set_state",
	"type_text", "wait_for_log", "wait_for_speech", "wait_for_speech_to_finish",
	"wait_for_user_reply",
}

// The empty slice is non-nil on purpose: nil in BridgeOptions means every capability.
func nvda(capabilities ...wire.Capability) testsupport.BridgeOptions {
	if capabilities == nil {
		capabilities = []wire.Capability{}
	}
	return testsupport.BridgeOptions{
		Reader:       wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
		Capabilities: capabilities,
	}
}

func TestTheAdvertisedListIsIdenticalBeforeDuringAndAfterASession(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})

	want := append(append([]string{}, everyGatedTool...), ungated...)
	slices.Sort(want)

	beforeConnecting := advertised(t, h)
	if !slices.Equal(beforeConnecting, want) {
		t.Fatalf("tools/list = %v before connecting, want the whole surface %v",
			beforeConnecting, want)
	}

	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader failed: %s", got.Text)
	}

	if got := advertised(t, h); !slices.Equal(got, beforeConnecting) {
		t.Errorf("tools/list = %v after connecting, want it unchanged at %v",
			got, beforeConnecting)
	}

	h.Bridge.Handle(wire.CommandGetSpeech, func(json.RawMessage) (any, error) {
		return wire.SpeechResult{
			Entries:   []wire.SpeechEntry{{Text: "Edit  blank", Index: 1, LogPosition: 12}},
			FromIndex: 0,
			ToIndex:   1,
		}, nil
	})
	speech := h.Call(t, "get_speech", map[string]any{"since_index": 0})
	if speech.IsError {
		t.Fatalf("get_speech failed: %s", speech.Text)
	}
	var window struct {
		Entries []struct {
			Text        string `json:"text"`
			Index       int    `json:"index"`
			LogPosition int    `json:"logPosition"`
		} `json:"entries"`
		ToIndex int `json:"toIndex"`
	}
	speech.Decode(t, &window)
	if len(window.Entries) != 1 || window.Entries[0].Text != "Edit  blank" || window.ToIndex != 1 {
		t.Errorf("get_speech = %+v, want the bridge's own answer", window)
	}
	if window.Entries[0].LogPosition != 12 {
		t.Errorf("logPosition = %d, want the 12 the bridge sent", window.Entries[0].LogPosition)
	}

	if got := h.Call(t, "disconnect_reader", nil); got.IsError {
		t.Fatalf("disconnect_reader failed: %s", got.Text)
	}

	if got := advertised(t, h); !slices.Equal(got, beforeConnecting) {
		t.Errorf("tools/list = %v after disconnecting, want it unchanged at %v",
			got, beforeConnecting)
	}
	h.AssertNoToolsChanged(t)

	refused := h.Call(t, "get_speech", map[string]any{"since_index": 0})
	if !refused.IsError {
		t.Error("get_speech succeeded after the session ended")
	}
	if !strings.Contains(refused.Text, "connect_reader") {
		t.Errorf("error = %q, want it to name the tool that fixes this", refused.Text)
	}
}

func TestAReaderWithoutBrailleIsRefusedTheBrailleToolWithAReason(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(
		wire.CapabilitySpeech, wire.CapabilityGestures, wire.CapabilityFocus,
	))
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	if !h.Advertises(t, "get_braille") {
		t.Errorf("tools/list = %v, want get_braille advertised even though this "+
			"reader announced no braille", h.ToolNames(t))
	}

	result := h.Call(t, "get_braille", map[string]any{"since_index": 0})
	if !result.IsError {
		t.Fatal("get_braille succeeded on a reader with no braille")
	}
	if !strings.Contains(result.Text, "braille") {
		t.Errorf("error = %q, want the missing capability named", result.Text)
	}
	if !strings.Contains(result.Text, "nvda") {
		t.Errorf("error = %q, want the connected reader named", result.Text)
	}
	if strings.Contains(result.Text, "unknown tool") {
		t.Errorf("error = %q, want a capability error rather than the SDK's "+
			"unknown-tool answer", result.Text)
	}

	h.Bridge.Handle(wire.CommandGetFocusInfo, func(json.RawMessage) (any, error) {
		return wire.FocusInfoResult{Name: "Edit", Role: "editableText"}, nil
	})
	if got := h.Call(t, "get_focus_info", map[string]any{}); got.IsError {
		t.Errorf("get_focus_info = %q, want it to run for a reader that announced focus",
			got.Text)
	}
}

func TestAReaderAnnouncingNothingCanBeDrivenThroughNothing(t *testing.T) {
	h := testsupport.StartMCP(t, nvda())
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	for _, name := range []string{"get_speech", "press_gesture", "get_braille"} {
		if !h.Advertises(t, name) {
			t.Errorf("%s left the list; the advertised surface is a constant", name)
		}
		if got := h.Call(t, name, map[string]any{"since_index": 0}); !got.IsError {
			t.Errorf("%s ran for a reader that announced no capabilities at all", name)
		}
	}
}

func TestAnUnknownAnnouncedCapabilityIsIgnoredButStillReported(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilitySpeech, wire.Capability("telepathy")))

	result := h.Connect(t)
	if result.IsError {
		t.Fatalf("an unknown capability broke the handshake: %s", result.Text)
	}

	var connected struct {
		Capabilities []string `json:"capabilities"`
	}
	result.Decode(t, &connected)
	if !slices.Contains(connected.Capabilities, "telepathy") {
		t.Errorf("capabilities = %v, want the unknown one retained and reported",
			connected.Capabilities)
	}
	if !h.Advertises(t, "get_speech") {
		t.Error("the known capability was not honoured alongside the unknown one")
	}
}

func TestCallingAGatedToolWithNoSessionSaysToConnectFirst(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilitySpeech))

	result := h.Call(t, "get_speech", map[string]any{"since_index": 0})

	if !result.IsError {
		t.Fatal("get_speech succeeded with nothing connected")
	}
	if !strings.Contains(result.Text, "connect_reader") {
		t.Errorf("error = %q, want it to name the tool that fixes this", result.Text)
	}
}

func TestAGenuinelyUnknownToolIsStillAProtocolError(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilitySpeech))

	h.CallExpectingProtocolError(t, "make_coffee")
}

func TestAConnectionThatDiesMidSessionIsNoticedAndCanBeReopened(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(testsupport.EveryWireCapability()...))
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}
	if !h.Advertises(t, "get_speech") {
		t.Fatal("the gated tools are not advertised at all")
	}

	h.Bridge.Handle(wire.CommandGetSpeech, func(json.RawMessage) (any, error) {
		h.Bridge.DropConnection()
		return wire.SpeechResult{}, nil
	})

	result := h.Call(t, "get_speech", map[string]any{"since_index": 0})
	if !result.IsError {
		t.Fatal("a call over a dead connection reported success")
	}

	if !h.Advertises(t, "get_speech") {
		t.Errorf("tools/list = %v, want it unchanged by a lost connection",
			h.ToolNames(t))
	}
	var status struct {
		State  string `json:"state"`
		Reason string `json:"reason"`
	}
	h.Call(t, "status", nil).Decode(t, &status)
	if status.State != "disconnected" {
		t.Errorf("state = %q, want disconnected", status.State)
	}
	if status.Reason == "" {
		t.Error("reason is empty; status must say why the session ended")
	}

	if got := h.Connect(t); got.IsError {
		t.Fatalf("reconnecting after a loss: %s", got.Text)
	}
	if !h.Advertises(t, "get_speech") {
		t.Errorf("tools/list = %v, want the gated tools published again", h.ToolNames(t))
	}
}

func TestReaderVocabularyPassesThroughUntouched(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(testsupport.EveryWireCapability()...))
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	var pressed []string
	h.Bridge.Handle(wire.CommandPressGesture, func(params json.RawMessage) (any, error) {
		var request wire.PressGestureParams
		if err := json.Unmarshal(params, &request); err != nil {
			return nil, err
		}
		pressed = request.Gestures
		ok := true
		return wire.AckResult{OK: &ok}, nil
	})
	h.Bridge.Handle(wire.CommandGetFocusInfo, func(json.RawMessage) (any, error) {
		return wire.FocusInfoResult{
			Name:   "Text editor",
			Role:   "editableText",
			States: []string{"focusable", "focused"},
		}, nil
	})

	if got := h.Call(t, "press_gesture", map[string]any{
		"gestures": []string{"kb:NVDA+control+f7"},
	}); got.IsError {
		t.Fatalf("press_gesture failed: %s", got.Text)
	}
	if !slices.Equal(pressed, []string{"kb:NVDA+control+f7"}) {
		t.Errorf("the bridge received %v, want the id unchanged", pressed)
	}

	var focus struct {
		Role   string   `json:"role"`
		States []string `json:"states"`
	}
	h.Call(t, "get_focus_info", nil).Decode(t, &focus)
	if focus.Role != "editableText" || len(focus.States) != 2 {
		t.Errorf("focus = %+v, want the reader's own vocabulary unchanged", focus)
	}
}

func TestARefusedCommandDoesNotEndTheSession(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilityGestures))
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	h.Bridge.Handle(wire.CommandPressGesture, func(json.RawMessage) (any, error) {
		return nil, errUnknownGesture
	})

	result := h.Call(t, "press_gesture", map[string]any{"gestures": []string{"kb:nonsense"}})
	if !result.IsError {
		t.Fatal("a refused gesture reported success")
	}

	if !h.Advertises(t, "press_gesture") {
		t.Error("a refusal retracted the gated tools; only a lost connection should")
	}
	var status struct {
		State string `json:"state"`
	}
	h.Call(t, "status", nil).Decode(t, &status)
	if status.State != "connected" {
		t.Errorf("state = %q, want the session still connected after a refusal", status.State)
	}
}

var errUnknownGesture = errors.New("unknown gesture id")
