// screenreader-mcp domain -- the run_sequence tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// The fake clock's OnSleep hook is how speech is made to arrive during a gap.
package tools_test

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func sequenceCall(t *testing.T, announced ...entities.Capability) (*testsupport.ToolCall, *testsupport.Connection) {
	t.Helper()
	built := testsupport.NewConnection("nvda", announced...)
	return testsupport.NewToolCall(&tools.RunSequence{}).WithConnection(built.Connection), built
}

// sequenceResult is written out, not borrowed from the tool, so a field renamed on the way out is caught.
type sequenceResult struct {
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
		Settled    *bool  `json:"settled"`
		Matched    *struct {
			Found bool   `json:"found"`
			Index int    `json:"index"`
			Text  string `json:"text"`
		} `json:"matched"`
		Focus *struct {
			Name   string   `json:"name"`
			Role   string   `json:"role"`
			States []string `json:"states"`
		} `json:"focus"`
		Braille *capturedWindow `json:"braille"`
	} `json:"steps"`
	Speech []struct {
		Text  string `json:"text"`
		Index int    `json:"index"`
	} `json:"speech"`
	SpeechFrom int    `json:"speechFrom"`
	SpeechTo   int    `json:"speechTo"`
	Announced  string `json:"announced"`
	State      *struct {
		BrowseMode string `json:"browseMode"`
	} `json:"state"`
}

// speakInGaps says one thing during each pause, in order; an empty string is a gap in which nothing was said.
func speakInGaps(call *testsupport.ToolCall, speech *testsupport.Connection, said ...string) {
	gap := 0
	call.Clock.OnSleep(func(time.Duration) {
		if gap < len(said) && said[gap] != "" {
			speech.Speech.Speak(said[gap])
		}
		gap++
	})
}

func TestThePerStepSpansPartitionTheMergedWindow(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilitySpeech)
	speakInGaps(call, built, "Documents list", "Report, one of four")

	result, err := call.Run(`{"steps":[{"press_gesture":"a"},{"press_gesture":"b"}]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if got.Outcome != "completed" {
		t.Fatalf("outcome = %q (%s), want completed", got.Outcome, got.Message)
	}
	if got.SpeechFrom != 0 || got.SpeechTo != 2 {
		t.Fatalf("merged window = [%d,%d), want [0,2)", got.SpeechFrom, got.SpeechTo)
	}
	if len(got.Speech) != 2 {
		t.Fatalf("speech = %v, want both utterances in ONE window", got.Speech)
	}
	if len(got.Steps) != 2 {
		t.Fatalf("steps = %v, want one entry per step", got.Steps)
	}

	at := got.SpeechFrom
	for _, step := range got.Steps {
		if step.SpeechFrom != at {
			t.Errorf("step %d starts at %d, want %d -- there is a hole in the window",
				step.Step, step.SpeechFrom, at)
		}
		at = step.SpeechTo
	}
	if at != got.SpeechTo {
		t.Errorf("the last step ends at %d, want %d -- the trailing read is not being "+
			"credited to it", at, got.SpeechTo)
	}
	if got.Steps[0].SpeechTo-got.Steps[0].SpeechFrom != 1 {
		t.Errorf("step 1 = [%d,%d), want exactly its own utterance",
			got.Steps[0].SpeechFrom, got.Steps[0].SpeechTo)
	}
}

func TestASilentStepIsPresentWithAnEmptySpan(t *testing.T) {
	call, built := sequenceCall(t,
		entities.CapabilityGestures, entities.CapabilityTyping, entities.CapabilitySpeech)
	speakInGaps(call, built, "Search edit", "")

	result, err := call.Run(`{"steps":[{"press_gesture":"a"},{"type_text":"report"}]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if len(got.Steps) != 2 {
		t.Fatalf("steps = %v, want the silent step present rather than omitted", got.Steps)
	}
	silent := got.Steps[1]
	if silent.Kind != "type_text" || silent.SpeechFrom != silent.SpeechTo {
		t.Errorf("the typing step = %+v, want an EMPTY span -- it said nothing", silent)
	}
	if silent.Typed == nil || *silent.Typed != len("report") {
		t.Errorf("typed = %v, want the reader's own count", silent.Typed)
	}
	// The count is reported and the text never is.
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshalling the result: %v", err)
	}
	if strings.Contains(string(encoded), "report") {
		t.Fatalf("the result carries the literal text: %s", encoded)
	}
}

func TestATriggerThatNeverFiredIsItsOwnOutcome(t *testing.T) {
	call, _ := sequenceCall(t, entities.CapabilityGestures, entities.CapabilitySpeech)

	result, err := call.Run(`{"steps":[
		{"press_gesture":"a"},
		{"wait_for_speech":{"text":"finished","timeout":2}},
		{"press_gesture":"b"}
	]}`)
	if err != nil {
		t.Fatalf("run_sequence: a trigger that did not fire must not be an ERROR: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if got.Outcome != "trigger_not_found" {
		t.Fatalf("outcome = %q, want trigger_not_found -- distinct from both neighbours",
			got.Outcome)
	}
	if got.FailedStep != 2 {
		t.Errorf("failedStep = %d, want 2 -- the step that waited", got.FailedStep)
	}
	if got.Message != "" {
		t.Errorf("message = %q, want none: nothing broke, so there is nothing to explain",
			got.Message)
	}
	if len(got.Steps) != 2 {
		t.Fatalf("steps = %v, want the plan stopped at the trigger", got.Steps)
	}
	if got.Steps[1].Matched == nil || got.Steps[1].Matched.Found {
		t.Errorf("the waiting step = %+v, want found:false recorded on it", got.Steps[1])
	}
}

func TestAFiredTriggerCarriesStraightOn(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilitySpeech)
	speakInGaps(call, built, "processing")

	result, err := call.Run(`{"steps":[
		{"press_gesture":"a"},
		{"wait_for_speech":{"text":"process"}},
		{"press_gesture":"b"}
	]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if got.Outcome != "completed" {
		t.Fatalf("outcome = %q (%s), want completed", got.Outcome, got.Message)
	}
	if len(got.Steps) != 3 {
		t.Fatalf("steps = %v, want the step after the trigger to have run", got.Steps)
	}
	if got.Steps[1].Matched == nil || !got.Steps[1].Matched.Found {
		t.Errorf("the waiting step = %+v, want the match recorded", got.Steps[1])
	}
	if pressed := built.Gestures.Pressed(); len(pressed) != 2 {
		t.Errorf("pressed %v, want both keys -- the second is the point of the trigger", pressed)
	}
}

func TestATriggerMatchesSpeechFromEarlierInTheSamePlan(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilitySpeech)
	// Said in the pause after step 1, before the waiting step is dispatched.
	speakInGaps(call, built, "processing")

	result, err := call.Run(`{"steps":[
		{"press_gesture":"a"},
		{"wait_for_speech":{"text":"processing"}}
	]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if got.Outcome != "completed" {
		t.Fatalf("outcome = %q, want the earlier utterance to satisfy the trigger", got.Outcome)
	}
	waits := built.Speech.Waits()
	if len(waits) != 1 || waits[0].AfterIndex == nil || *waits[0].AfterIndex != 0 {
		t.Errorf("wait = %+v, want it bounded by the plan's start index", waits)
	}
}

func TestAFailingStepStopsThePlanAndSaysHowFarItGot(t *testing.T) {
	call, built := sequenceCall(t,
		entities.CapabilityGestures, entities.CapabilityTyping, entities.CapabilitySpeech)
	built.Text.FailWith(errors.New("the focused control refused the text"))

	result, err := call.Run(`{"steps":[
		{"press_gesture":"a"},
		{"type_text":"report"},
		{"press_gesture":"b"}
	]}`)
	if err != nil {
		t.Fatalf("run_sequence: a step failing is a RESULT, not an error: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if got.Outcome != "failed" {
		t.Fatalf("outcome = %q, want failed", got.Outcome)
	}
	if got.FailedStep != 2 {
		t.Errorf("failedStep = %d, want 2", got.FailedStep)
	}
	if !strings.Contains(got.Message, "refused the text") {
		t.Errorf("message = %q, want the reader's own reason", got.Message)
	}
	if len(got.Steps) != 2 {
		t.Errorf("steps = %v, want the two that ran and no more", got.Steps)
	}
	if pressed := built.Gestures.Pressed(); len(pressed) != 1 {
		t.Errorf("pressed %v, want only the key before the failure", pressed)
	}
}

func TestAPlanNamingAnUnannouncedCapabilityDeliversNothing(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilityInteract)

	_, err := call.Run(`{"steps":[
		{"press_gesture":"a"},
		{"type_text":"report"}
	],"announce":"filling the form in"}`)

	var refused *tools.CapabilityError
	if !errors.As(err, &refused) {
		t.Fatalf("run_sequence = %v, want a CapabilityError", err)
	}
	if refused.Step != 2 || refused.Capability != entities.CapabilityTyping {
		t.Errorf("refused %q at step %d, want typing at step 2", refused.Capability, refused.Step)
	}
	if !strings.Contains(refused.Error(), "step 2") {
		t.Errorf("the message %q does not name the step", refused.Error())
	}
	if pressed := built.Gestures.Pressed(); len(pressed) != 0 {
		t.Errorf("pressed %v, want NOTHING delivered by a refused plan", pressed)
	}
	// And nothing was said to the human.
	if said := built.Interact.Announced(); len(said) != 0 {
		t.Errorf("announced %q, want silence: the plan never ran", said)
	}
}

// Proved by making the announcement fail: if nothing is pressed, it came first.
func TestTheAnnouncementPrecedesStepOneAndIsEchoedBack(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilityInteract)

	result, err := call.Run(`{"steps":[{"press_gesture":"a"}],"announce":"opening the report"}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)
	if got.Announced != "opening the report" {
		t.Errorf("announced = %q, want the text echoed -- confirmation that THIS text "+
			"reached the reader, not merely that the mechanism ran", got.Announced)
	}
	if said := built.Interact.Announced(); len(said) != 1 || said[0] != "opening the report" {
		t.Errorf("the reader was told %q, want the announcement once", said)
	}

	// Now the ordering, which an echo alone cannot show.
	failing, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilityInteract)
	built.Interact.FailWith(errors.New("the reader could not speak"))
	if _, err := failing.Run(`{"steps":[{"press_gesture":"a"}],"announce":"opening"}`); err == nil {
		t.Fatal("run_sequence succeeded although the announcement failed")
	}
	if pressed := built.Gestures.Pressed(); len(pressed) != 0 {
		t.Errorf("pressed %v, want nothing: the announcement had not been spoken yet", pressed)
	}
}

func TestAWhitespaceAnnouncementIsRefusedBeforeAnythingRuns(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilityInteract)

	if _, err := call.Run(`{"steps":[{"press_gesture":"a"}],"announce":"   "}`); err == nil {
		t.Fatal("a whitespace-only announcement was accepted")
	}
	if pressed := built.Gestures.Pressed(); len(pressed) != 0 {
		t.Errorf("pressed %v, want nothing delivered", pressed)
	}
}

func TestEveryStepIsDispatchedWithNoGraceOfItsOwn(t *testing.T) {
	call, built := sequenceCall(t,
		entities.CapabilityGestures, entities.CapabilityTyping, entities.CapabilityInteract)

	if _, err := call.Run(`{"steps":[
		{"press_gesture":"a"},
		{"type_text":"report"}
	],"announce":"filling it in"}`); err != nil {
		t.Fatalf("run_sequence: %v", err)
	}

	if graces := built.Gestures.Graces(); len(graces) != 1 || graces[0] != 0 {
		t.Errorf("gesture graces = %v, want [0] -- the pause belongs to the plan", graces)
	}
	if graces := built.Text.Graces(); len(graces) != 1 || graces[0] != 0 {
		t.Errorf("typing graces = %v, want [0]", graces)
	}
	if said := built.Gestures.Announcements(); len(said) != 1 || said[0] != "" {
		t.Errorf("the gesture carried the announcement %q, want none", said)
	}
	if said := built.Text.Announcements(); len(said) != 1 || said[0] != "" {
		t.Errorf("the typing carried the announcement %q, want none", said)
	}
	if said := built.Interact.Announced(); len(said) != 1 {
		t.Errorf("announced %q, want it spoken exactly once, before step 1", said)
	}
}

func TestTheGapRunsAfterEveryStepIncludingTheLast(t *testing.T) {
	call, _ := sequenceCall(t, entities.CapabilityGestures)

	if _, err := call.Run(`{"steps":[{"press_gesture":"a"},{"press_gesture":"b"}]}`); err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	want := time.Duration(tools.DefaultGapMs) * time.Millisecond
	slept := call.Clock.Slept()
	if len(slept) != 2 || slept[0] != want || slept[1] != want {
		t.Errorf("slept %v, want the default gap after each of the two steps", slept)
	}

	// And an explicit gap replaces it, including zero, which opts out.
	quick, _ := sequenceCall(t, entities.CapabilityGestures)
	if _, err := quick.Run(`{"steps":[{"press_gesture":"a"}],"gap_ms":0}`); err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	if slept := quick.Clock.Slept(); len(slept) != 1 || slept[0] != 0 {
		t.Errorf("slept %v, want a single zero-length pause", slept)
	}
}

func TestADelayStepWaitsForTheTimeItWasGiven(t *testing.T) {
	call, _ := sequenceCall(t, entities.CapabilityGestures)

	if _, err := call.Run(`{"steps":[
		{"press_gesture":"a"},
		{"delay":500},
		{"press_gesture":"b"}
	],"gap_ms":0}`); err != nil {
		t.Fatalf("run_sequence: %v", err)
	}

	var waited time.Duration
	for _, slept := range call.Clock.Slept() {
		waited += slept
	}
	if waited != 500*time.Millisecond {
		t.Errorf("the plan waited %s, want exactly the delay it was given", waited)
	}
}

func TestASettleStepReportsWhetherTheReaderStopped(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilitySpeech)
	built.Speech.SetFinished(false)

	result, err := call.Run(`{"steps":[{"settle":2}]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if got.Outcome != "completed" {
		t.Fatalf("outcome = %q, want completed: a settle that timed out is not a failure",
			got.Outcome)
	}
	if len(got.Steps) != 1 || got.Steps[0].Settled == nil || *got.Steps[0].Settled {
		t.Errorf("the settle step = %+v, want settled:false recorded", got.Steps)
	}
}

func TestAReadStepOrientsWithFocusAndBraille(t *testing.T) {
	call, built := sequenceCall(t,
		entities.CapabilityGestures, entities.CapabilityFocus, entities.CapabilityBraille)
	built.Focus.SetFocus(ports.FocusInfo{Name: "Report", Role: "listItem"})
	call.Clock.OnSleep(func(time.Duration) { built.Braille.Braille("Report lv 1") })

	result, err := call.Run(`{"steps":[
		{"press_gesture":"a"},
		{"read":["focus","braille"]}
	]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	read := got.Steps[1]
	if read.Focus == nil || read.Focus.Name != "Report" || read.Focus.Role != "listItem" {
		t.Errorf("focus = %+v, want the focused object in the reader's own vocabulary", read.Focus)
	}
	if read.Braille == nil || len(read.Braille.Entries) != 1 {
		t.Fatalf("braille = %+v, want what reached the display during the plan", read.Braille)
	}
	if read.Braille.Entries[0].Text != "Report lv 1" {
		t.Errorf("braille = %q, want the update the plan caused", read.Braille.Entries[0].Text)
	}
}

func TestAnEmptyReadListMeansFocus(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityFocus)
	built.Focus.SetFocus(ports.FocusInfo{Name: "Search", Role: "editableText"})

	result, err := call.Run(`{"steps":[{"read":[]}]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)
	if got.Steps[0].Focus == nil || got.Steps[0].Focus.Name != "Search" {
		t.Errorf("read = %+v, want focus by default", got.Steps[0])
	}
}

func TestASecondBrailleReadResumesWhereTheFirstEnded(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityBraille)
	// On the display before the plan: not caused by it, and not reported.
	built.Braille.Braille("Desktop")

	first := 0
	call.Clock.OnSleep(func(time.Duration) {
		first++
		if first == 1 {
			built.Braille.Braille("Report lv 1")
		}
	})

	result, err := call.Run(`{"steps":[{"read":["braille"]},{"read":["braille"]}]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if len(got.Steps[0].Braille.Entries) != 0 {
		t.Errorf("the first read = %+v, want nothing: the display's earlier contents "+
			"are not what this plan did", got.Steps[0].Braille.Entries)
	}
	second := got.Steps[1].Braille
	if second == nil || len(second.Entries) != 1 || second.Entries[0].Text != "Report lv 1" {
		t.Errorf("the second read = %+v, want only what arrived since the first", second)
	}
}

func TestTheModesRideOnTheResult(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilityState)
	built.State.SetState(ports.ReaderState{BrowseMode: "focus", SpeechMode: "talk"})

	result, err := call.Run(`{"steps":[{"press_gesture":"a"}]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)
	if got.State == nil || got.State.BrowseMode != "focus" {
		t.Errorf("state = %+v, want the modes that cannot be heard", got.State)
	}

	// Decoded into a fresh value, because a pointer left over from the decode above would read as present.
	without, _ := sequenceCall(t, entities.CapabilityGestures)
	result, err = without.Run(`{"steps":[{"press_gesture":"a"}]}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var stateless sequenceResult
	decode(t, result, &stateless)
	if stateless.State != nil {
		t.Errorf("state = %+v, want it absent for a reader that serves none", stateless.State)
	}
}

func TestAStepMustNameExactlyOneKind(t *testing.T) {
	for _, one := range []struct {
		what  string
		steps string
	}{
		{"no kind at all", `[{}]`},
		{"two kinds at once", `[{"press_gesture":"a","delay":100}]`},
	} {
		t.Run(one.what, func(t *testing.T) {
			call, built := sequenceCall(t, entities.CapabilityGestures)
			if _, err := call.Run(`{"steps":` + one.steps + `}`); err == nil {
				t.Fatal("the step was accepted")
			}
			if pressed := built.Gestures.Pressed(); len(pressed) != 0 {
				t.Errorf("pressed %v, want nothing delivered", pressed)
			}
		})
	}
}

func TestThePlanIsRefusedWhenItIsUnbounded(t *testing.T) {
	call, _ := sequenceCall(t, entities.CapabilityGestures)
	if _, err := call.Run(`{"steps":[]}`); err == nil {
		t.Error("an empty plan was accepted")
	}
	if _, err := call.Run(`{"steps":[{"press_gesture":"a"}],"gap_ms":-1}`); err == nil {
		t.Error("a negative gap was accepted")
	}
	if _, err := call.Run(`{"steps":[{"press_gesture":"a"}],"gap_ms":60000}`); err == nil {
		t.Error("a gap longer than the bound was accepted; it should be a delay step")
	}
}

func TestThePlanStopsWhenItsBudgetRunsOut(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilitySpeech)
	// The fake clock advances on Sleep, so the delay steps are what spend the budget.
	result, err := call.Run(`{"steps":[
		{"delay":20000},
		{"delay":20000},
		{"press_gesture":"a"}
	],"gap_ms":0}`)
	if err != nil {
		t.Fatalf("run_sequence: %v", err)
	}
	var got sequenceResult
	decode(t, result, &got)

	if got.Outcome != "failed" {
		t.Fatalf("outcome = %q, want failed once the budget ran out", got.Outcome)
	}
	if got.FailedStep != 3 {
		t.Errorf("failedStep = %d, want 3 -- the step it reached", got.FailedStep)
	}
	if !strings.Contains(got.Message, "budget") {
		t.Errorf("message = %q, want it to say the budget ran out", got.Message)
	}
	if pressed := built.Gestures.Pressed(); len(pressed) != 0 {
		t.Errorf("pressed %v, want the step past the budget never dispatched", pressed)
	}
}

func TestALostConnectionSurfacesAsAnErrorRatherThanAFailedStep(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures)
	built.Gestures.FailWith(ports.ErrConnectionLost)

	_, err := call.Run(`{"steps":[{"press_gesture":"a"}]}`)
	if !errors.Is(err, ports.ErrConnectionLost) {
		t.Fatalf("run_sequence = %v, want the loss to reach the dispatcher", err)
	}
}

func TestWithNoReaderConnectedItSaysConnectFirst(t *testing.T) {
	call := testsupport.NewToolCall(&tools.RunSequence{})

	_, err := call.Run(`{"steps":[{"press_gesture":"a"}]}`)
	var refused *tools.CapabilityError
	if !errors.As(err, &refused) {
		t.Fatalf("run_sequence = %v, want a CapabilityError", err)
	}
	if refused.Reader != "" || refused.Step != 0 {
		t.Errorf("refused = %+v, want the no-session form with no step", refused)
	}
}
