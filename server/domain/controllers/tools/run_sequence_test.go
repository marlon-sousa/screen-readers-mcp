// screenreader-mcp domain -- the run_sequence tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Black-box (package tools_test), against fakes for every port a plan can reach.
//
// WHAT IS WORTH PROTECTING HERE, and it is not throughput. Four properties, each
// of which is a way this tool could quietly become dishonest:
//
//  1. THE WINDOW IS GAPLESS. The per-step spans must partition the merged one,
//     so no utterance is credited to nobody. That is what the trailing read
//     exists for, and it is invisible until something arrives in a gap.
//  2. `trigger_not_found` IS NOT `failed`. Collapsing them is the exact failure
//     spec 0025 named when it rejected an `until:` parameter.
//  3. A SILENT STEP IS PRESENT with an empty span, rather than omitted.
//  4. A REFUSED PLAN DELIVERS NOTHING -- no keystroke, and no announcement,
//     because a capability refusal is a message to the agent and `announce` is
//     the channel to the human.
//
// Time is injected, never patched: the fake clock's Sleep is an instant advance,
// and its OnSleep hook is how speech is made to arrive DURING a gap -- which is
// the only way property 1 can be exercised at all.
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

// sequenceCall wires run_sequence against a reader announcing exactly these
// capabilities -- stated per test, because which ones are announced is the
// variable the whole up-front gate turns on.
func sequenceCall(t *testing.T, announced ...entities.Capability) (*testsupport.ToolCall, *testsupport.Connection) {
	t.Helper()
	built := testsupport.NewConnection("nvda", announced...)
	return testsupport.NewToolCall(&tools.RunSequence{}).WithConnection(built.Connection), built
}

// sequenceResult is the shape an agent decodes. Written out here rather than
// reaching for the tool's own struct, which is unexported and must stay so: a
// test sharing it could not catch a field being renamed on the way out.
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

// speakInGaps makes the reader say one thing during each pause, in order --
// which is where the speech a keystroke causes actually lands, and the only way
// to exercise a window that has to be gapless.
//
// An empty string is a gap in which nothing was said, so a test can place a
// SILENT step between two talkative ones.
func speakInGaps(call *testsupport.ToolCall, speech *testsupport.Connection, said ...string) {
	gap := 0
	call.Clock.OnSleep(func(time.Duration) {
		if gap < len(said) && said[gap] != "" {
			speech.Speech.Speak(said[gap])
		}
		gap++
	})
}

// PROPERTY 1, and the whole reason the trailing read exists: speech that arrives
// in the pause after a step belongs to THAT step, and the per-step spans
// partition the merged window with nothing left over.
//
// Without the final read the last step's right edge would be a mark taken before
// its own speech had arrived, and that utterance would be returned by nothing --
// present in no step's span and outside the merged window's end.
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

	// The partition itself: step 1 starts where the window does, each step
	// begins exactly where the last ended, and the last ends where the window
	// does. No utterance can belong to neither.
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
	// And the speech really is attributed one apiece rather than blended.
	if got.Steps[0].SpeechTo-got.Steps[0].SpeechFrom != 1 {
		t.Errorf("step 1 = [%d,%d), want exactly its own utterance",
			got.Steps[0].SpeechFrom, got.Steps[0].SpeechTo)
	}
}

// PROPERTY 3: a step that said nothing is REPORTED, with an empty span, rather
// than omitted -- spec 0025's "batching stops hiding things", applied to mixed
// step kinds. Most reader commands never move focus and never speak.
func TestASilentStepIsPresentWithAnEmptySpan(t *testing.T) {
	call, built := sequenceCall(t,
		entities.CapabilityGestures, entities.CapabilityTyping, entities.CapabilitySpeech)
	// The gesture spoke; the typing did not, which is the ordinary case with
	// speak-typed-characters off.
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
	// The count is reported and the text never is: typing is exactly how a
	// secret would be entered, and a plan is not a way round that.
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshalling the result: %v", err)
	}
	if strings.Contains(string(encoded), "report") {
		t.Fatalf("the result carries the literal text: %s", encoded)
	}
}

// PROPERTY 2, the one this entry exists to keep honest: a trigger that never
// fired stops the plan and is NOT a failure. "The trigger never fired" and "a
// step broke" call for different next moves by the agent, so they are different
// answers -- and the step that waited is named either way.
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
	// The remaining steps did NOT run, and the per-step results say how far it
	// got rather than leaving the agent to guess.
	if len(got.Steps) != 2 {
		t.Fatalf("steps = %v, want the plan stopped at the trigger", got.Steps)
	}
	if got.Steps[1].Matched == nil || got.Steps[1].Matched.Found {
		t.Errorf("the waiting step = %+v, want found:false recorded on it", got.Steps[1])
	}
}

// The other half of the same property: a trigger that DID fire carries straight
// on, which is what makes act-on-trigger a plan rather than a new concept.
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

// The trigger matches anything said since the PLAN started, not since the
// waiting step was dispatched. The utterance can legitimately land in the
// fraction of a millisecond between the previous step going out and this one,
// and a wait that could miss it that way would abort a plan that was working.
func TestATriggerMatchesSpeechFromEarlierInTheSamePlan(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilitySpeech)
	// Said in the pause after step 1, which is BEFORE the waiting step is
	// dispatched.
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
	// And it did not match speech from BEFORE the plan: the wait was asked
	// with the plan's own start index.
	waits := built.Speech.Waits()
	if len(waits) != 1 || waits[0].AfterIndex == nil || *waits[0].AfterIndex != 0 {
		t.Errorf("wait = %+v, want it bounded by the plan's start index", waits)
	}
}

// Abort on the first failure, with the per-step results that make partial
// execution legible. Nothing is rolled back -- keystrokes cannot be un-pressed --
// so how far it got is the only thing that can be reported, and it must be.
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

// PROPERTY 4: the whole plan is checked BEFORE the first keystroke, so a plan
// naming something this reader cannot do is refused entire rather than
// discovered halfway through with the reader left mid-edit. The error names the
// step, because "this reader has no typing" leaves an agent hunting for which of
// its own lines asked.
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
	// And nothing was said to the human. A capability refusal is a message
	// about the agent's own mistake; announce is the channel to the person at
	// the machine, and speaking a refusal down it would interrupt somebody to
	// report a thing that never happened.
	if said := built.Interact.Announced(); len(said) != 0 {
		t.Errorf("announced %q, want silence: the plan never ran", said)
	}
}

// The announcement is spoken BEFORE step 1 and comes back echoed. Proved by
// making it fail: if nothing is pressed when the announcement could not be
// spoken, the announcement must have come first.
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

// A whitespace-only announcement is refused, exactly as the announce tool and
// the two mutating tools refuse it -- and refused before anything is dispatched,
// so a narration that cannot be spoken is never discovered after the machine has
// already moved.
func TestAWhitespaceAnnouncementIsRefusedBeforeAnythingRuns(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilityInteract)

	if _, err := call.Run(`{"steps":[{"press_gesture":"a"}],"announce":"   "}`); err == nil {
		t.Fatal("a whitespace-only announcement was accepted")
	}
	if pressed := built.Gestures.Pressed(); len(pressed) != 0 {
		t.Errorf("pressed %v, want nothing delivered", pressed)
	}
}

// COMPOSITION IS OVER THE BRIDGE'S COMMANDS, not over sibling tools, and this is
// what that means in practice: every step goes out with graceMs 0 and no
// announcement of its own. A per-step grace would give each step its own window,
// and the result carries ONE.
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
	// The announcement went out ONCE, through the interact port, rather than
	// riding on each step and being spoken twice.
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

// The plan's single timing knob: the pause after each step INCLUDING the last,
// which is what gives the final read something to find. Anything longer is a
// delay step, so there are never two parameters meaning "wait here".
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

// A delay is the application's own known timing, and it is spent where the
// latency is a fraction of a millisecond rather than a model turn -- which is
// the whole reason the untestable scenario becomes testable.
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

// A settle reports whether the reader stopped answering -- and the field says
// only that. It can never claim the reader had finished, which is why it is a
// plain bool on the step rather than anything shaped like completeness.
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

// The read step orients, which is the half of the original trailing-read idea
// that survived spec 0025: focus is not speech and is on no other result.
func TestAReadStepOrientsWithFocusAndBraille(t *testing.T) {
	call, built := sequenceCall(t,
		entities.CapabilityGestures, entities.CapabilityFocus, entities.CapabilityBraille)
	built.Focus.SetFocus(ports.FocusInfo{Name: "Report", Role: "listItem"})
	// Brailled in the pause after the key, which is when a display update
	// caused by that key actually arrives.
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

// A read step with no targets means "orient me", which is focus -- the default
// stated in one place rather than assumed by each caller.
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

// Braille from a SECOND read step reports what arrived since the first, rather
// than repeating it -- the same no-overlap-no-gap rule the speech window follows.
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

// The modes an agent cannot hear ride on the result, sampled once the plan had
// finished -- so they report the state the plan LEFT the reader in rather than
// whichever step happened to be the last mutating one.
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

	// And ABSENT on a reader that serves no state: absent and "all four
	// fields zero" are different answers. Decoded into a FRESH value, because
	// a pointer field left over from the decode above would read as present.
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

// A step naming no kind, or two, is the agent's own mistake and is named as
// such -- before anything is delivered.
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

// The plan's own bounds reach the agent as a refusal rather than as a session
// spent waiting.
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

// The whole-plan budget is the backstop for the waiting steps' sum. It stops the
// plan and says which step it reached, rather than letting a plan of long waits
// hold the session.
func TestThePlanStopsWhenItsBudgetRunsOut(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures, entities.CapabilitySpeech)
	// Two settles that each eat most of the budget. The fake clock advances
	// on Sleep; the settle itself does not wait, so the delay steps here are
	// what spend the time.
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

// The connection going away mid-plan is NOT "a step failed": the session is
// over, and it has to surface as an error so the dispatcher notices the loss and
// records it. A result carrying outcome:"failed" would leave the server still
// believing it had a reader.
func TestALostConnectionSurfacesAsAnErrorRatherThanAFailedStep(t *testing.T) {
	call, built := sequenceCall(t, entities.CapabilityGestures)
	built.Gestures.FailWith(ports.ErrConnectionLost)

	_, err := call.Run(`{"steps":[{"press_gesture":"a"}]}`)
	if !errors.Is(err, ports.ErrConnectionLost) {
		t.Fatalf("run_sequence = %v, want the loss to reach the dispatcher", err)
	}
}

// With no session at all the answer is the plain "connect first", before any
// talk of steps and capabilities.
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
