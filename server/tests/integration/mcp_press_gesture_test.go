//go:build integration

// screenreader-mcp tests -- one round trip per intention, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario: everything below the MCP client is real except the reader.
package integration_test

import (
	"encoding/json"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// Declared here, not shared with the tools package, so a field renamed on the way out fails this test.
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

func TestAGesturesSpeechComesBackInTheCallThatPressedIt(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	var asked wire.PressGestureParams
	h.Bridge.Handle(wire.CommandPressGesture, func(params json.RawMessage) (any, error) {
		if err := json.Unmarshal(params, &asked); err != nil {
			return nil, err
		}
		// A reader where the first `h` found a heading and the second found nothing.
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

	if asked.GraceMs == nil || *asked.GraceMs == 0 {
		t.Errorf("graceMs = %v, want the server's default carried through", asked.GraceMs)
	}
	if asked.Announce == nil || *asked.Announce != "looking for the first heading" {
		t.Errorf("announce = %v, want the hint carried to the human", asked.Announce)
	}

	if len(got.Speech) != 1 || got.Speech[0].Text != "Notícias heading level 1" {
		t.Fatalf("speech = %v, want the utterance the key caused", got.Speech)
	}
	if got.Speech[0].Index != 7 || got.Speech[0].LogPosition != 3329 {
		t.Errorf("entry = index %d at logPosition %d, want 7 at 3329",
			got.Speech[0].Index, got.Speech[0].LogPosition)
	}
	if got.SpeechFrom != 7 || got.SpeechTo != 8 {
		t.Errorf("window = [%d,%d), want [7,8)", got.SpeechFrom, got.SpeechTo)
	}
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

func TestAQuietWindowIsAnEmptyListAndAnAbsentStateIsAbsent(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	h.Bridge.Handle(wire.CommandPressGesture, func(json.RawMessage) (any, error) {
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
	if raw["speechTo"] != float64(4) {
		t.Errorf("speechTo = %v, want 4 -- where to read from next", raw["speechTo"])
	}
	for _, forbidden := range []string{"complete", "finished", "done"} {
		if _, present := raw[forbidden]; present {
			t.Errorf("result carries %q; a window reports an instant, it never claims completeness", forbidden)
		}
	}
}
