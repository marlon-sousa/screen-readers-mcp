// screenreader-mcp domain -- the braille, gesture, focus, state and config
// tools' tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package tools_test

import (
	"errors"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// asCapabilityError is shared with speech_tools_test.go.
func asCapabilityError(err error, into **tools.CapabilityError) bool {
	return errors.As(err, into)
}

func TestGetBrailleReturnsAHalfOpenWindow(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityBraille)
	call := testsupport.NewToolCall(&tools.GetBraille{}).WithConnection(built.Connection)
	built.Braille.Braille("edt blnk", "docs lst")

	var window capturedWindow
	result, err := call.Run(`{"since_index":1}`)
	if err != nil {
		t.Fatalf("get_braille: %v", err)
	}
	decode(t, result, &window)

	if len(window.Entries) != 1 || window.Entries[0].Text != "docs lst" {
		t.Errorf("entries = %q, want only what was brailled since index 1", window.texts())
	}
	if window.FromIndex != 1 || window.ToIndex != 2 {
		t.Errorf("range = [%d,%d), want [1,2)", window.FromIndex, window.ToIndex)
	}
	if window.Entries[0].Index != 1 || window.Entries[0].LogPosition == 0 {
		t.Errorf("entry = index %d at logPosition %d, want its own ring index and a real coordinate",
			window.Entries[0].Index, window.Entries[0].LogPosition)
	}
}

func TestPressGesturePassesOpaqueIdsThroughInOrder(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	call := testsupport.NewToolCall(&tools.PressGesture{}).WithConnection(built.Connection)

	var pressed struct {
		Pressed []struct {
			Gesture    string `json:"gesture"`
			SpeechFrom int    `json:"speechFrom"`
			SpeechTo   int    `json:"speechTo"`
		} `json:"pressed"`
	}
	result, err := call.Run(`{"gestures":["kb:NVDA+control+f7","kb:downArrow"]}`)
	if err != nil {
		t.Fatalf("press_gesture: %v", err)
	}
	decode(t, result, &pressed)

	sent := built.Gestures.Pressed()
	if len(sent) != 1 || len(sent[0]) != 2 {
		t.Fatalf("pressed %v, want one call with both ids", sent)
	}
	if sent[0][0] != "kb:NVDA+control+f7" || sent[0][1] != "kb:downArrow" {
		t.Errorf("pressed %v, want the ids unchanged and in order", sent[0])
	}
	if len(pressed.Pressed) != 2 {
		t.Fatalf("result = %v, want both pressed ids echoed", pressed.Pressed)
	}
	if pressed.Pressed[0].Gesture != "kb:NVDA+control+f7" || pressed.Pressed[1].Gesture != "kb:downArrow" {
		t.Errorf("echoed %v, want the ids unchanged and in order", pressed.Pressed)
	}
}

func TestPressGestureCarriesTheGraceAndTheAnnouncementToTheReader(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	call := testsupport.NewToolCall(&tools.PressGesture{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"gestures":["h"],"grace_ms":250,"announce":"pressing h"}`); err != nil {
		t.Fatalf("press_gesture: %v", err)
	}
	if _, err := call.Run(`{"gestures":["h"]}`); err != nil {
		t.Fatalf("press_gesture: %v", err)
	}

	if graces := built.Gestures.Graces(); len(graces) != 2 || graces[0] != 250 || graces[1] != tools.DefaultGraceMs {
		t.Errorf("graces = %v, want [250 %d] -- asked for, then the default", graces, tools.DefaultGraceMs)
	}
	if said := built.Gestures.Announcements(); len(said) != 2 || said[0] != "pressing h" || said[1] != "" {
		t.Errorf("announcements = %q, want the hint then nothing", said)
	}
}

func TestPressGestureTreatsAnExplicitZeroGraceAsAnOptOut(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	call := testsupport.NewToolCall(&tools.PressGesture{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"gestures":["h"],"grace_ms":0}`); err != nil {
		t.Fatalf("press_gesture: %v", err)
	}

	if graces := built.Gestures.Graces(); len(graces) != 1 || graces[0] != 0 {
		t.Errorf("graces = %v, want [0]", graces)
	}
}

func TestPressGestureReportsWhatWasSaidAndWhichKeySaidIt(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	built.Gestures.AnswerWith(ports.GestureOutcome{
		Pressed: []ports.GesturePress{
			{Gesture: "h", SpeechFrom: 7, SpeechTo: 8},
			{Gesture: "h", SpeechFrom: 8, SpeechTo: 8},
		},
		Observation: ports.Observation{
			Speech:    []ports.SpeechEntry{{Text: "Notícias heading level 1", Index: 7, LogPosition: 3329}},
			FromIndex: 7,
			ToIndex:   8,
			State:     &ports.ReaderState{BrowseMode: "browse", SpeechMode: "talk"},
		},
	})
	call := testsupport.NewToolCall(&tools.PressGesture{}).WithConnection(built.Connection)

	result, err := call.Run(`{"gestures":["h","h"]}`)
	if err != nil {
		t.Fatalf("press_gesture: %v", err)
	}
	var got struct {
		Pressed []struct {
			SpeechFrom int `json:"speechFrom"`
			SpeechTo   int `json:"speechTo"`
		} `json:"pressed"`
		Speech []struct {
			Text  string `json:"text"`
			Index int    `json:"index"`
		} `json:"speech"`
		SpeechFrom int `json:"speechFrom"`
		SpeechTo   int `json:"speechTo"`
		State      *struct {
			BrowseMode string `json:"browseMode"`
		} `json:"state"`
	}
	decode(t, result, &got)

	if len(got.Speech) != 1 || got.Speech[0].Text != "Notícias heading level 1" {
		t.Errorf("speech = %v, want the utterance the key caused", got.Speech)
	}
	if got.SpeechFrom != 7 || got.SpeechTo != 8 {
		t.Errorf("window = [%d,%d), want [7,8)", got.SpeechFrom, got.SpeechTo)
	}
	if len(got.Pressed) != 2 || got.Pressed[1].SpeechFrom != got.Pressed[1].SpeechTo {
		t.Errorf("pressed = %v, want the second key to carry an EMPTY span", got.Pressed)
	}
	if got.State == nil || got.State.BrowseMode != "browse" {
		t.Errorf("state = %v, want the modes the agent cannot hear", got.State)
	}
}

func TestAQuietPressReportsAnEmptyListAndNoClaimOfCompleteness(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	call := testsupport.NewToolCall(&tools.PressGesture{}).WithConnection(built.Connection)

	result, err := call.Run(`{"gestures":["h"]}`)
	if err != nil {
		t.Fatalf("press_gesture: %v", err)
	}
	var got map[string]any
	decode(t, result, &got)

	speech, ok := got["speech"].([]any)
	if !ok || len(speech) != 0 {
		t.Errorf("speech = %v, want an empty LIST -- never null, never absent", got["speech"])
	}
	for _, forbidden := range []string{"complete", "finished", "done"} {
		if _, present := got[forbidden]; present {
			t.Errorf("result carries %q; an empty window is a fact about an instant, not a claim", forbidden)
		}
	}
}

func TestPressGestureRefusesAnEmptyList(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	call := testsupport.NewToolCall(&tools.PressGesture{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"gestures":[]}`); err == nil {
		t.Error("pressing an empty gesture list was accepted")
	}
	if len(built.Gestures.Pressed()) != 0 {
		t.Error("an empty list reached the reader")
	}
}

func TestPressGestureReportsARejectedId(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityGestures)
	call := testsupport.NewToolCall(&tools.PressGesture{}).WithConnection(built.Connection)
	built.Gestures.FailWith(errors.New("bridge refused pressGesture: unknown gesture id"))

	if _, err := call.Run(`{"gestures":["kb:NVDA+nonsense"]}`); err == nil {
		t.Error("a rejected gesture was reported as success")
	}
}

func TestGetFocusInfoPassesReaderVocabularyThrough(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityFocus)
	call := testsupport.NewToolCall(&tools.GetFocusInfo{}).WithConnection(built.Connection)

	value := ""
	appModule := "notepad"
	built.Focus.SetFocus(ports.FocusInfo{
		Name:      "Text editor",
		Role:      "editableText",
		States:    []string{"focusable", "focused", "multiLine"},
		Value:     &value,
		AppModule: &appModule,
	})

	var focus struct {
		Name      string   `json:"name"`
		Role      string   `json:"role"`
		States    []string `json:"states"`
		Value     *string  `json:"value"`
		AppModule *string  `json:"appModule"`
	}
	result, err := call.Run("")
	if err != nil {
		t.Fatalf("get_focus_info: %v", err)
	}
	decode(t, result, &focus)

	if focus.Role != "editableText" || len(focus.States) != 3 {
		t.Errorf("focus = %+v, want the reader's own role and states unchanged", focus)
	}
	// The empty string is a value and must survive as one, distinct from null.
	if focus.Value == nil || *focus.Value != "" {
		t.Errorf("value = %v, want the empty string preserved rather than nulled", focus.Value)
	}
	if focus.AppModule == nil || *focus.AppModule != "notepad" {
		t.Errorf("appModule = %v, want notepad", focus.AppModule)
	}
}

func TestGetFocusInfoReportsNoStatesAsAnEmptyList(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityFocus)
	call := testsupport.NewToolCall(&tools.GetFocusInfo{}).WithConnection(built.Connection)
	built.Focus.SetFocus(ports.FocusInfo{Name: "Pane", Role: "pane"})

	var focus struct {
		States *[]string `json:"states"`
	}
	result, err := call.Run("")
	if err != nil {
		t.Fatalf("get_focus_info: %v", err)
	}
	decode(t, result, &focus)

	if focus.States == nil {
		t.Fatal("states = null, want an empty list")
	}
	if len(*focus.States) != 0 {
		t.Errorf("states = %v, want empty", *focus.States)
	}
}

func TestGetStateSnapshotsCanBeDiffedAcrossAnAction(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityState)
	call := testsupport.NewToolCall(&tools.GetState{}).WithConnection(built.Connection)

	built.State.SetState(ports.ReaderState{BrowseMode: "browse", SpeechMode: "talk"})

	var before struct {
		BrowseMode string `json:"browseMode"`
	}
	result, err := call.Run("")
	if err != nil {
		t.Fatalf("get_state: %v", err)
	}
	decode(t, result, &before)

	built.State.SetState(ports.ReaderState{BrowseMode: "focus", SpeechMode: "talk"})

	var after struct {
		BrowseMode string `json:"browseMode"`
	}
	result, err = call.Run("")
	if err != nil {
		t.Fatalf("get_state: %v", err)
	}
	decode(t, result, &after)

	if before.BrowseMode == "" || after.BrowseMode == "" {
		t.Fatalf("browseMode = %q then %q, want both reported", before.BrowseMode, after.BrowseMode)
	}
	if before.BrowseMode == after.BrowseMode {
		t.Error("the two snapshots are identical; the toggle would be invisible")
	}
}

func TestGetStateReportsAnAbsentBrowseModeAsNone(t *testing.T) {
	built := testsupport.NewConnection("jaws", entities.CapabilityState)
	call := testsupport.NewToolCall(&tools.GetState{}).WithConnection(built.Connection)
	built.State.SetState(ports.ReaderState{BrowseMode: "none", SpeechMode: "talk"})

	var state struct {
		BrowseMode string `json:"browseMode"`
	}
	result, err := call.Run("")
	if err != nil {
		t.Fatalf("get_state: %v", err)
	}
	decode(t, result, &state)

	if state.BrowseMode != "none" {
		t.Errorf("browseMode = %q, want \"none\" for a reader with no such mode", state.BrowseMode)
	}
}

func TestConfigValuesRoundTripAsOpaqueJSON(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityConfig)
	built.Config.Put([]string{"speech", "symbolLevel"}, "100")

	read := testsupport.NewToolCall(&tools.GetConfig{}).WithConnection(built.Connection)
	var got struct {
		Value any `json:"value"`
	}
	result, err := read.Run(`{"key_path":["speech","symbolLevel"]}`)
	if err != nil {
		t.Fatalf("get_config: %v", err)
	}
	decode(t, result, &got)
	if got.Value != float64(100) {
		t.Errorf("value = %v, want the reader's own 100", got.Value)
	}

	// A write returns what the reader now holds, so the assertion reads it back.
	write := testsupport.NewToolCall(&tools.SetConfig{}).WithConnection(built.Connection)
	if _, err := write.Run(`{"key_path":["speech","symbolLevel"],"value":{"nested":[1,2]}}`); err != nil {
		t.Fatalf("set_config: %v", err)
	}
	result, err = read.Run(`{"key_path":["speech","symbolLevel"]}`)
	if err != nil {
		t.Fatalf("get_config: %v", err)
	}
	var complex struct {
		Value map[string]any `json:"value"`
	}
	decode(t, result, &complex)
	if len(complex.Value["nested"].([]any)) != 2 {
		t.Errorf("value = %v, want the structure preserved exactly", complex.Value)
	}
}

func TestConfigToolsRequireAKeyPath(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityConfig)

	read := testsupport.NewToolCall(&tools.GetConfig{}).WithConnection(built.Connection)
	if _, err := read.Run(`{"key_path":[]}`); err == nil {
		t.Error("get_config accepted an empty key path")
	}

	write := testsupport.NewToolCall(&tools.SetConfig{}).WithConnection(built.Connection)
	if _, err := write.Run(`{"value":1}`); err == nil {
		t.Error("set_config accepted a call with no key path")
	}
}

func TestSetConfigDistinguishesAnAbsentValueFromAnExplicitNull(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilityConfig)
	call := testsupport.NewToolCall(&tools.SetConfig{}).WithConnection(built.Connection)

	if _, err := call.Run(`{"key_path":["speech","rate"]}`); err == nil {
		t.Error("set_config accepted a call with no value")
	}
	if _, err := call.Run(`{"key_path":["speech","rate"],"value":null}`); err != nil {
		t.Errorf("set_config refused an explicit null: %v", err)
	}
}

func TestEveryGatedToolNamesTheCapabilityItNeeds(t *testing.T) {
	// A reader that announced nothing at all.
	built := testsupport.NewConnection("nvda")

	gated := []struct {
		tool       tools.Tool
		capability entities.Capability
	}{
		{&tools.GetBraille{}, entities.CapabilityBraille},
		{&tools.PressGesture{}, entities.CapabilityGestures},
		{&tools.TypeText{}, entities.CapabilityTyping},
		{&tools.GetFocusInfo{}, entities.CapabilityFocus},
		{&tools.GetState{}, entities.CapabilityState},
		{&tools.GetConfig{}, entities.CapabilityConfig},
		{&tools.SetConfig{}, entities.CapabilityConfig},
	}
	for _, gate := range gated {
		t.Run(gate.tool.Name(), func(t *testing.T) {
			call := testsupport.NewToolCall(gate.tool).WithConnection(built.Connection)

			_, err := call.Run(`{"since_index":0,"gestures":["x"],"key_path":["a"],"value":1}`)
			if err == nil {
				t.Fatal("the tool ran for a reader that announced nothing")
			}
			var capability *tools.CapabilityError
			if !asCapabilityError(err, &capability) {
				t.Fatalf("error = %v, want a *CapabilityError", err)
			}
			if capability.Capability != gate.capability {
				t.Errorf("capability = %q, want %q", capability.Capability, gate.capability)
			}
			if capability.Reader != "nvda" {
				t.Errorf("reader = %q, want the connected reader named", capability.Reader)
			}
		})
	}
}

func TestTheCapabilityCheckPrecedesArgumentValidation(t *testing.T) {
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	call := testsupport.NewToolCall(&tools.PressGesture{}).WithConnection(built.Connection)

	_, err := call.Run(`{"gestures":[]}`)

	var capability *tools.CapabilityError
	if !asCapabilityError(err, &capability) {
		t.Fatalf("error = %v, want the capability error rather than the argument one", err)
	}
}
