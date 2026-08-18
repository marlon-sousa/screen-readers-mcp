//go:build integration

// screenreader-mcp tests -- one round trip per intention, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario, named after the USE CASE (spec 0025, board entry
// 11.12). Everything below the MCP client is real except the reader: the agent
// presses a key and the words it caused come back in that same result.
//
// It is at THIS boundary because the value of the entry is a property of what
// the agent receives -- the collapse is only real if the collapsed shape
// survives the whole stack, and an empty window is only honest if the agent can
// tell it apart from a field nobody sent.
package integration_test

import (
	"encoding/json"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// pressResult is the shape an agent decodes, written out here rather than
// imported: the tools package's own struct is unexported, and a test that shared
// it could not catch a field being renamed on the way out.
type pressResult struct {
	Pressed []struct {
		Gesture    string `json:"gesture"`
		SpeechFrom int    `json:"speechFrom"`
		SpeechTo   int    `json:"speechTo"`
	} `json:"pressed"`
	Speech []struct {
		Text        string `json:"text"`
		Index       int    `json:"index"`
		LogPosition int    `json:"logPosition"`
	} `json:"speech"`
	SpeechFrom int `json:"speechFrom"`
	SpeechTo   int `json:"speechTo"`
	State      *struct {
		BrowseMode string `json:"browseMode"`
		SpeechMode string `json:"speechMode"`
	} `json:"state"`
}

// The entry in one test: three round trips become one, and the batch stays
// observable while it happens.
func TestAGesturesSpeechComesBackInTheCallThatPressedIt(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}
	h.AwaitToolsChanged(t)

	var asked wire.PressGestureParams
	h.Bridge.Handle(wire.CommandPressGesture, func(params json.RawMessage) (any, error) {
		if err := json.Unmarshal(params, &asked); err != nil {
			return nil, err
		}
		// A reader where the first `h` found a heading and the second found
		// nothing -- the 2026-08-03 shape, now expressible.
		return wire.GestureResult{
			Pressed: []wire.GesturePress{
				{Gesture: "h", SpeechFrom: 7, SpeechTo: 8},
				{Gesture: "h", SpeechFrom: 8, SpeechTo: 8},
			},
			Speech: []wire.SpeechEntry{
				{Text: "Notícias heading level 1", Index: 7, LogPosition: 3329},
			},
			SpeechFrom: 7,
			SpeechTo:   8,
			State: &wire.StateResult{
				BrowseMode: wire.BrowseMode("browse"),
				SpeechMode: "talk",
			},
		}, nil
	})

	result := h.Call(t, "press_gesture", map[string]any{
		"gestures": []string{"h", "h"},
		"announce": "looking for the first heading",
	})
	if result.IsError {
		t.Fatalf("press_gesture: %s", result.Text)
	}
	var got pressResult
	result.Decode(t, &got)

	// The grace and the announcement reached the reader, with the default
	// applied by the server because the agent did not name one.
	if asked.GraceMs == nil || *asked.GraceMs == 0 {
		t.Errorf("graceMs = %v, want the server's default carried through", asked.GraceMs)
	}
	if asked.Announce == nil || *asked.Announce != "looking for the first heading" {
		t.Errorf("announce = %v, want the hint carried to the human", asked.Announce)
	}

	// What the agent came for: the words, in this result.
	if len(got.Speech) != 1 || got.Speech[0].Text != "Notícias heading level 1" {
		t.Fatalf("speech = %v, want the utterance the key caused", got.Speech)
	}
	// Coordinates survive the crossing, so the utterance still joins to the log
	// (spec 0021) and the next read resumes without a gap.
	if got.Speech[0].Index != 7 || got.Speech[0].LogPosition != 3329 {
		t.Errorf("entry = index %d at logPosition %d, want 7 at 3329",
			got.Speech[0].Index, got.Speech[0].LogPosition)
	}
	if got.SpeechFrom != 7 || got.SpeechTo != 8 {
		t.Errorf("window = [%d,%d), want [7,8)", got.SpeechFrom, got.SpeechTo)
	}
	// The batch stays observable: which key spoke, and which said nothing.
	if len(got.Pressed) != 2 {
		t.Fatalf("pressed = %v, want one entry per key", got.Pressed)
	}
	if got.Pressed[0].SpeechFrom == got.Pressed[0].SpeechTo {
		t.Errorf("first key = %+v, want a non-empty span", got.Pressed[0])
	}
	if got.Pressed[1].SpeechFrom != got.Pressed[1].SpeechTo {
		t.Errorf("second key = %+v, want an EMPTY span -- it said nothing", got.Pressed[1])
	}
	if got.State == nil || got.State.BrowseMode != "browse" {
		t.Errorf("state = %+v, want the modes the agent cannot hear", got.State)
	}
}

// The honest empty case, end to end. An agent must be able to tell "the reader
// said nothing by then" from "this reader does not report that at all" -- and
// must never find a field claiming the window was complete.
func TestAQuietWindowIsAnEmptyListAndAnAbsentStateIsAbsent(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}
	h.AwaitToolsChanged(t)

	h.Bridge.Handle(wire.CommandPressGesture, func(json.RawMessage) (any, error) {
		// A reader that took the key, said nothing, and serves no state.
		return wire.GestureResult{
			Pressed:    []wire.GesturePress{{Gesture: "h", SpeechFrom: 4, SpeechTo: 4}},
			Speech:     []wire.SpeechEntry{},
			SpeechFrom: 4,
			SpeechTo:   4,
		}, nil
	})

	result := h.Call(t, "press_gesture", map[string]any{"gestures": []string{"h"}})
	if result.IsError {
		t.Fatalf("press_gesture: %s", result.Text)
	}

	var raw map[string]any
	result.Decode(t, &raw)

	speech, ok := raw["speech"].([]any)
	if !ok || len(speech) != 0 {
		t.Errorf("speech = %v, want an empty LIST -- an agent should read \"nothing yet\", not null", raw["speech"])
	}
	if _, present := raw["state"]; present {
		t.Errorf("state = %v, want the field ABSENT when the reader reported none", raw["state"])
	}
	// The resume coordinate is still there, which is what makes the empty
	// answer actionable rather than a dead end.
	if raw["speechTo"] != float64(4) {
		t.Errorf("speechTo = %v, want 4 -- where to read from next", raw["speechTo"])
	}
	for _, forbidden := range []string{"complete", "finished", "done"} {
		if _, present := raw[forbidden]; present {
			t.Errorf("result carries %q; a window reports an instant, it never claims completeness", forbidden)
		}
	}
}
