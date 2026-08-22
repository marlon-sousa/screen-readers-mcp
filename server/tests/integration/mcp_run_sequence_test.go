//go:build integration

// screenreader-mcp tests -- one call, several intentions, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario, named after the USE CASE (spec 0036, board entry
// 11.16). Everything below the MCP client is real except the reader: a mixed
// plan crosses the whole stack over a real transport, and a refused one delivers
// nothing at all.
//
// It is at THIS boundary because the entry's value is a property of what the
// AGENT receives. A plan is only worth having if the merged window, the per-step
// bookmarks and the three-valued outcome survive the crossing -- and the refusal
// is only worth having if it happens before a single command reaches the reader,
// which is a fact about the wire and not about a domain object.
package integration_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// planResult is the shape an agent decodes, written out here rather than
// imported: the tools package's own struct is unexported, and a test that shared
// it could not catch a field being renamed on the way out.
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

// The entry in one test: four intentions that would have cost four agent turns
// arrive as one call, and what comes back is ONE window with a bookmark per
// step.
//
// The plan is the scenario that was UNTESTABLE in the first external run: type a
// command, submit it, wait while it runs, and interrupt it. Across separate
// calls the command had always finished before a stop could be sent.
func TestAPlanCarriesSeveralIntentionsAndComesBackAsOneWindow(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	if got := h.Connect(t); got.IsError {
		t.Fatalf("connect_reader: %s", got.Text)
	}

	// A reader whose speech ring advances as the plan runs: the server marks
	// it before each step, so what the bridge answers getNextSpeechIndex with
	// is what the bookmarks are made of.
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
		// Submitting the command is what makes the reader speak.
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
		// The reader acknowledges the call and says nothing more; the server
		// asks for no result body here.
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
	// Every intention reached the reader, in order, as ordinary commands --
	// composition is over the bridge's existing commands, so nothing new
	// crossed the wire.
	if typed.Text != "big" {
		t.Errorf("typed %q, want the command", typed.Text)
	}
	if len(pressed) != 2 || pressed[0] != "enter" || pressed[1] != "escape" {
		t.Errorf("pressed %v, want the submit and then the stop", pressed)
	}
	// Each step went out with NO grace of its own: the result carries one
	// window, not one per step.
	if typed.GraceMs == nil || *typed.GraceMs != 0 {
		t.Errorf("typeText graceMs = %v, want 0 -- the pause belongs to the plan", typed.GraceMs)
	}

	// What the agent came for: one window over the whole plan, and a bookmark
	// per step so it can see which one spoke.
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
	// The coordinates survive the crossing, so the utterance still joins to
	// the log and the next read resumes without a gap.
	if got.Speech[0].LogPosition != 8814 {
		t.Errorf("logPosition = %d, want 8814", got.Speech[0].LogPosition)
	}
	// The human heard the plan described BEFORE it ran, once, whatever the
	// first step happened to be.
	if narrated != "running a long command and then stopping it" {
		t.Errorf("the reader was told %q, want the narration spoken before step 1", narrated)
	}
	// And the two things that ride on every mutating result.
	if got.Announced != "running a long command and then stopping it" {
		t.Errorf("announced = %q, want the narration echoed back", got.Announced)
	}
	if got.State == nil || got.State.BrowseMode != "focus" {
		t.Errorf("state = %+v, want the modes the agent cannot hear", got.State)
	}
}

// The refusal, end to end and at the wire: a plan naming a capability this
// reader never announced delivers NO keystroke -- not one, not the ones before
// the bad step -- and the error names the step that asked.
//
// This is the property that makes a plan safe to send at all. Four separate
// calls fail one at a time in front of the agent; a plan fails in the middle and
// leaves the reader wherever it got to, which is why the check happens before
// anything moves.
func TestARefusedPlanDeliversNoKeystroke(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
		// Gestures but no typing: the second step is the impossible one.
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
	// Including the announcement. A capability refusal is a message about the
	// agent's own mistake, and announce is the channel to the person at the
	// machine -- speaking a refusal down it would interrupt somebody to report
	// a thing that never happened.
	if !strings.Contains(result.Text, "step 2") {
		t.Errorf("the refusal %q does not name the step that asked", result.Text)
	}
	if !strings.Contains(result.Text, "typing") {
		t.Errorf("the refusal %q does not name the missing capability", result.Text)
	}
}

// A trigger that never fires stops the plan and is NOT reported as an error at
// the MCP boundary either: an agent must be able to read `trigger_not_found` off
// an ordinary successful result, exactly as it reads `found: false` from the
// tool this step is made of.
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
