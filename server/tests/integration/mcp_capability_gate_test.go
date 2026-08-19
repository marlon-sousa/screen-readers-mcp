//go:build integration

// screenreader-mcp tests -- capability enforcement, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario, named after the USE CASE. Spec 0013's headless
// scenarios 1, 2 and 4 -- proved where they actually matter, at the MCP
// boundary, with everything below the client real except the bridge.
//
// WHAT THIS FILE STOPPED ASSERTING. Under spec 0013 the gate was on the LIST,
// and these tests read tools/list to prove it. Spec 0022 (option (c), agreed
// 2026-08-19) moved the gate off the list entirely: every tool is advertised
// from startup, and a reader that cannot serve one refuses the CALL. So the
// assertions moved from an absence to an error -- which is the stronger claim
// anyway, because an absence proved only that this server did not offer the
// tool, while the error proves it will not run it.
//
// The list assertions that remain say the opposite of what they used to: that
// tools/list is IDENTICAL before connecting, while connected, and after both a
// disconnect and a lost connection. That constant is what closes entry 11.6.
//
// Enforcement is keyed on CAPABILITY STRINGS and never on reader names, so every
// bridge below is called "nvda" and differs only in what `hello` announced. If
// any of these passed because of a reader name, that would be the bug.
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

// everyGatedTool is what a reader announcing every capability should see.
var everyGatedTool = []string{
	"announce", "ask_user", "get_braille", "get_config", "get_focus_info",
	"get_last_speech", "get_log", "get_log_position", "get_next_speech_index",
	"get_speech", "get_state", "press_gesture", "set_config", "set_log_level",
	"type_text", "wait_for_log", "wait_for_speech", "wait_for_speech_to_finish",
	"wait_for_user_reply",
}

// nvda is a bridge announcing exactly these capabilities and nothing else.
//
// The empty slice is made non-nil deliberately: BridgeOptions distinguishes "the
// test did not say" (nil, meaning every capability) from "this reader announces
// none", and it is the second that the gate's hardest case needs.
func nvda(capabilities ...wire.Capability) testsupport.BridgeOptions {
	if capabilities == nil {
		capabilities = []wire.Capability{}
	}
	return testsupport.BridgeOptions{
		Reader:       wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
		Capabilities: capabilities,
	}
}

// Scenario 1 in full: the whole surface is there from the start, a session opens,
// a gated call works, the session ends -- and the tool list never moves.
//
// THE PROPERTY ENTRY 11.6 TURNS ON, asserted at the MCP boundary where a client
// actually sees it: a client that listed once, before connecting, and cached the
// answer forever is holding a correct answer at every point below.
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

	// A real gated call, over the whole stack, answered by the bridge.
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
	// End to end over the real MCP surface: the journal coordinate reaches the
	// AGENT, not just the domain -- it is what makes get_log's since_position
	// usable from a speech entry (spec 0021).
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
	// And nothing was ever announced, because nothing changed. A client with no
	// notification handling at all is not disadvantaged here -- which is the
	// whole point, and the half of 11.6 that no client-side remedy could reach.
	h.AssertNoToolsChanged(t)

	// What the session's end DOES change is what a call can do.
	refused := h.Call(t, "get_speech", map[string]any{"since_index": 0})
	if !refused.IsError {
		t.Error("get_speech succeeded after the session ended")
	}
	if !strings.Contains(refused.Text, "connect_reader") {
		t.Errorf("error = %q, want it to name the tool that fixes this", refused.Text)
	}
}

// Scenario 2: a reader without braille. The tool is LISTED and the call is
// REFUSED, which is the shape spec 0022 chose deliberately -- an absence told an
// agent nothing about why, and could not be told apart from a stale list.
//
// The reader is still called nvda: only what it ANNOUNCED differs.
func TestAReaderWithoutBrailleIsRefusedTheBrailleToolWithAReason(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(
		wire.CapabilitySpeech, wire.CapabilityGestures, wire.CapabilityFocus,
	))
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	// Advertised, like everything else: the list does not narrow to the reader.
	if !h.Advertises(t, "get_braille") {
		t.Errorf("tools/list = %v, want get_braille advertised even though this "+
			"reader announced no braille", h.ToolNames(t))
	}

	// And calling it gives the structured capability error rather than the SDK's
	// `unknown tool` -- naming the capability AND the reader, which is what tells
	// "this reader cannot" apart from "nothing is connected".
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

	// And this is a per-capability refusal, not a blanket one: what the reader
	// DID announce runs.
	h.Bridge.Handle(wire.CommandGetFocusInfo, func(json.RawMessage) (any, error) {
		return wire.FocusInfoResult{Name: "Edit", Role: "editableText"}, nil
	})
	if got := h.Call(t, "get_focus_info", map[string]any{}); got.IsError {
		t.Errorf("get_focus_info = %q, want it to run for a reader that announced focus",
			got.Text)
	}
}

// A reader announcing nothing at all can be driven through nothing -- and the
// empty announcement is not mistaken for "announced everything".
//
// The list is untouched by any of that, which is why the proof is a call.
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

// protocol.md §4: an unknown capability string must be ignored rather than
// rejected -- the set can grow without breaking an older peer -- and it is still
// reported honestly, because a reader deserves describing even where this server
// has no tool for what it offers.
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

// Calling a gated tool with NO session gives the other message -- "connect
// first" -- because the two situations need different actions from the agent.
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

// A name that was never a tool still gets the SDK's own protocol error: the
// backstop answers only for tools this server actually has.
func TestAGenuinelyUnknownToolIsStillAProtocolError(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilitySpeech))

	h.CallExpectingProtocolError(t, "make_coffee")
}

// Scenario 4: the connection dies mid-session. The in-flight call fails cleanly,
// the tools retract without anybody restarting anything, and a later
// connect_reader opens a fresh session.
func TestAConnectionThatDiesMidSessionIsNoticedAndCanBeReopened(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(testsupport.EveryWireCapability()...))
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}
	if !h.Advertises(t, "get_speech") {
		t.Fatal("the gated tools are not advertised at all")
	}

	// The bridge drops the connection while serving a command, which is what
	// a crashed reader looks like from here.
	h.Bridge.Handle(wire.CommandGetSpeech, func(json.RawMessage) (any, error) {
		h.Bridge.DropConnection()
		return wire.SpeechResult{}, nil
	})

	result := h.Call(t, "get_speech", map[string]any{"since_index": 0})
	if !result.IsError {
		t.Fatal("a call over a dead connection reported success")
	}

	// The list is untouched by a lost connection, exactly as by a clean
	// disconnect. What says the session ended is `status`, and the next call.
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

	// And the agent can open a fresh one when it chooses -- the server never
	// did so on its own.
	if got := h.Connect(t); got.IsError {
		t.Fatalf("reconnecting after a loss: %s", got.Text)
	}
	if !h.Advertises(t, "get_speech") {
		t.Errorf("tools/list = %v, want the gated tools published again", h.ToolNames(t))
	}
}

// Reader vocabulary rides through as opaque data (spec 0005, principle 3): the
// gesture ids the agent sends reach the bridge unchanged, and the roles and
// states it gets back are the reader's own.
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

// A bridge REFUSING a command is not a lost connection: protocol.md §3 says an
// established session survives a failing command, so the tools must stay.
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

// errUnknownGesture is a bridge refusing a command -- an ordinary failure the
// session survives, distinct from the connection going away.
var errUnknownGesture = errors.New("unknown gesture id")
