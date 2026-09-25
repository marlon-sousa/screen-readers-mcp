//go:build integration

// screenreader-mcp tests -- one call, several intentions, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario: a plan crosses the whole stack over a real transport; only the reader is faked.
package integration_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// Declared here for the reason pressResult is; see mcp_press_gesture_test.go.
type planResult struct {
	Outcome    string `json:"outcome"`
	FailedStep int    `json:"failedStep"`
	Message    string `json:"message"`
	Steps      []struct {
		Step       int    `json:"step"`
		Kind       string `json:"kind"`
		SpeechFrom int    `json:"speechFrom"`
		SpeechTo   int    `json:"speechTo"`
		Gesture    string `json:"gesture"`
		Typed      *int   `json:"typed"`
	} `json:"steps"`
	Speech []struct {
		Text        string `json:"text"`
		Index       int    `json:"index"`
		LogPosition int    `json:"logPosition"`
	} `json:"speech"`
	SpeechFrom int    `json:"speechFrom"`
	SpeechTo   int    `json:"speechTo"`
	Announced  string `json:"announced"`
	State      *struct {
		BrowseMode string `json:"browseMode"`
	} `json:"state"`
}

func TestAPlanCarriesSeveralIntentionsAndComesBackAsOneWindow(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	index := 0
	h.Bridge.Handle(wire.CommandGetNextSpeechIndex, func(json.RawMessage) (any, error) {
		return wire.NextIndexResult{Index: index}, nil
	})
	var typed wire.TypeParams
	h.Bridge.Handle(wire.CommandTypeText, func(params json.RawMessage) (any, error) {
		if err := json.Unmarshal(params, &typed); err != nil {
			return nil, err
		}
		return wire.TypeResult{Typed: 3}, nil
	})
	var pressed []string
	h.Bridge.Handle(wire.CommandPressGesture, func(params json.RawMessage) (any, error) {
		var asked wire.PressGestureParams
		if err := json.Unmarshal(params, &asked); err != nil {
			return nil, err
		}
		pressed = append(pressed, asked.Gestures...)
		if len(pressed) == 2 {
			index = 1
		}
		return wire.GestureResult{}, nil
	})
	h.Bridge.Handle(wire.CommandGetSpeech, func(json.RawMessage) (any, error) {
		return wire.SpeechResult{
			Entries:   []wire.SpeechEntry{{Text: "running", Index: 0, LogPosition: 8814}},
			FromIndex: 0,
			ToIndex:   1,
		}, nil
	})
	h.Bridge.Handle(wire.CommandGetState, func(json.RawMessage) (any, error) {
		return wire.StateResult{BrowseMode: wire.BrowseMode("focus"), SpeechMode: "talk"}, nil
	})
	var narrated string
	h.Bridge.Handle(wire.CommandAnnounce, func(params json.RawMessage) (any, error) {
		var asked wire.AnnounceParams
		if err := json.Unmarshal(params, &asked); err != nil {
			return nil, err
		}
		narrated = asked.Text
		return map[string]any{}, nil
	})

	result := h.Call(t, "run_sequence", map[string]any{
		"steps": []map[string]any{
			{"type_text": "big"},
			{"press_gesture": "enter"},
			{"delay": 500},
			{"press_gesture": "escape"},
		},
		"gap_ms":   0,
		"announce": "running a long command and then stopping it",
	})
	if result.IsError {
		t.Fatalf("run_sequence: %s", result.Text)
	}
	var got planResult
	result.Decode(t, &got)

	if got.Outcome != "completed" {
		t.Fatalf("outcome = %q (%s), want completed", got.Outcome, got.Message)
	}
	if typed.Text != "big" {
		t.Errorf("typed %q, want the command", typed.Text)
	}
	if len(pressed) != 2 || pressed[0] != "enter" || pressed[1] != "escape" {
		t.Errorf("pressed %v, want the submit and then the stop", pressed)
	}
	if typed.GraceMs == nil || *typed.GraceMs != 0 {
		t.Errorf("typeText graceMs = %v, want 0 -- the pause belongs to the plan", typed.GraceMs)
	}

	if len(got.Steps) != 4 {
		t.Fatalf("steps = %+v, want one entry per step", got.Steps)
	}
	if got.Steps[0].Typed == nil || *got.Steps[0].Typed != 3 {
		t.Errorf("typed = %v, want the reader's own count", got.Steps[0].Typed)
	}
	if got.Steps[1].Gesture != "enter" {
		t.Errorf("step 2 = %+v, want the gesture echoed unchanged", got.Steps[1])
	}
	if got.Steps[0].SpeechFrom != got.Steps[0].SpeechTo {
		t.Errorf("the typing step = %+v, want an EMPTY span: it said nothing", got.Steps[0])
	}
	if got.SpeechFrom != 0 || got.SpeechTo != 1 {
		t.Errorf("merged window = [%d,%d), want [0,1)", got.SpeechFrom, got.SpeechTo)
	}
	if len(got.Speech) != 1 || got.Speech[0].Text != "running" {
		t.Fatalf("speech = %+v, want the utterance the plan caused", got.Speech)
	}
	if got.Speech[0].LogPosition != 8814 {
		t.Errorf("logPosition = %d, want 8814", got.Speech[0].LogPosition)
	}
	if narrated != "running a long command and then stopping it" {
		t.Errorf("the reader was told %q, want the narration spoken before step 1", narrated)
	}
	if got.Announced != "running a long command and then stopping it" {
		t.Errorf("announced = %q, want the narration echoed back", got.Announced)
	}
	if got.State == nil || got.State.BrowseMode != "focus" {
		t.Errorf("state = %+v, want the modes the agent cannot hear", got.State)
	}
}

func TestARefusedPlanDeliversNoKeystroke(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader:       wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
		Capabilities: []wire.Capability{wire.CapabilityGestures, wire.CapabilityInteract},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	delivered := 0
	for _, command := range []wire.Command{
		wire.CommandPressGesture, wire.CommandTypeText, wire.CommandAnnounce,
	} {
		h.Bridge.Handle(command, func(json.RawMessage) (any, error) {
			delivered++
			return map[string]any{}, nil
		})
	}

	result := h.Call(t, "run_sequence", map[string]any{
		"steps": []map[string]any{
			{"press_gesture": "enter"},
			{"type_text": "big"},
		},
		"announce": "filling the field in",
	})

	if !result.IsError {
		t.Fatalf("run_sequence succeeded: %s", result.Text)
	}
	if delivered != 0 {
		t.Errorf("%d commands reached the reader, want NONE: the plan was refused whole "+
			"before anything was delivered", delivered)
	}
	// No announcement either: a refusal is the agent's own mistake and must not interrupt the person at the machine.
	if !strings.Contains(result.Text, "step 2") {
		t.Errorf("the refusal %q does not name the step that asked", result.Text)
	}
	if !strings.Contains(result.Text, "typing") {
		t.Errorf("the refusal %q does not name the missing capability", result.Text)
	}
}

func TestATriggerThatNeverFiredIsASuccessfulResultAtTheBoundary(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	pressed := 0
	h.Bridge.Handle(wire.CommandPressGesture, func(json.RawMessage) (any, error) {
		pressed++
		return wire.GestureResult{}, nil
	})
	h.Bridge.Handle(wire.CommandWaitForSpeech, func(json.RawMessage) (any, error) {
		return wire.WaitForSpeechResult{Found: false, Index: 0}, nil
	})

	result := h.Call(t, "run_sequence", map[string]any{
		"steps": []map[string]any{
			{"press_gesture": "enter"},
			{"wait_for_speech": map[string]any{"text": "finished", "timeout": 1}},
			{"press_gesture": "escape"},
		},
		"gap_ms": 0,
	})
	if result.IsError {
		t.Fatalf("run_sequence reported an error for a trigger that did not fire: %s", result.Text)
	}
	var got planResult
	result.Decode(t, &got)

	if got.Outcome != "trigger_not_found" {
		t.Fatalf("outcome = %q, want trigger_not_found -- distinct from failed", got.Outcome)
	}
	if got.FailedStep != 2 {
		t.Errorf("failedStep = %d, want the step that waited", got.FailedStep)
	}
	if pressed != 1 {
		t.Errorf("%d keys pressed, want only the one before the trigger: the remaining "+
			"steps must not run", pressed)
	}
}
