// screenreader-mcp domain -- SequencePlan's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package entities_test

import (
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func everything() entities.Set {
	return entities.NewSet([]string{"speech", "braille", "gestures", "typing", "focus", "state"})
}

func press(gesture string) entities.SequenceStep {
	return entities.SequenceStep{Kind: entities.StepPressGesture, Gesture: gesture}
}

func TestEveryStepKindNamesTheCapabilityItNeeds(t *testing.T) {
	for _, one := range []struct {
		what string
		step entities.SequenceStep
		want []entities.Capability
	}{
		{"press_gesture", press("a"), []entities.Capability{entities.CapabilityGestures}},
		{
			"type_text",
			entities.SequenceStep{Kind: entities.StepTypeText, Text: "hello"},
			[]entities.Capability{entities.CapabilityTyping},
		},
		{"delay", entities.SequenceStep{Kind: entities.StepDelay, Delay: time.Second}, nil},
		{
			"settle",
			entities.SequenceStep{Kind: entities.StepSettle},
			[]entities.Capability{entities.CapabilitySpeech},
		},
		{
			"wait_for_speech",
			entities.SequenceStep{Kind: entities.StepWaitForSpeech, Match: "ready"},
			[]entities.Capability{entities.CapabilitySpeech},
		},
		{
			"read focus",
			entities.SequenceStep{Kind: entities.StepRead, Read: []entities.ReadTarget{entities.ReadFocus}},
			[]entities.Capability{entities.CapabilityFocus},
		},
		{
			"read both",
			entities.SequenceStep{
				Kind: entities.StepRead,
				Read: []entities.ReadTarget{entities.ReadFocus, entities.ReadBraille},
			},
			[]entities.Capability{entities.CapabilityFocus, entities.CapabilityBraille},
		},
	} {
		t.Run(one.what, func(t *testing.T) {
			got := one.step.Capabilities()
			if len(got) != len(one.want) {
				t.Fatalf("capabilities = %v, want %v", got, one.want)
			}
			for i, capability := range one.want {
				if got[i] != capability {
					t.Errorf("capability %d = %q, want %q", i, got[i], capability)
				}
			}
		})
	}
}

func TestAReadStepGatesOnEachTargetIndependently(t *testing.T) {
	plan := entities.SequencePlan{Steps: []entities.SequenceStep{
		press("a"),
		{Kind: entities.StepRead, Read: []entities.ReadTarget{entities.ReadFocus, entities.ReadBraille}},
	}}
	announced := entities.NewSet([]string{"gestures", "focus"})

	var missing *entities.MissingCapability
	if err := plan.Validate(announced); !errors.As(err, &missing) {
		t.Fatalf("Validate = %v, want the braille half refused", err)
	}
	if missing.Capability != entities.CapabilityBraille || missing.Step != 2 {
		t.Errorf("refused %q at step %d, want braille at step 2", missing.Capability, missing.Step)
	}

	onlyFocus := entities.SequencePlan{Steps: []entities.SequenceStep{
		{Kind: entities.StepRead, Read: []entities.ReadTarget{entities.ReadFocus}},
	}}
	if err := onlyFocus.Validate(announced); err != nil {
		t.Errorf("Validate = %v, want a focus-only read accepted", err)
	}
}

func TestAPlanNamingAnUnannouncedCapabilityIsRefusedAndNamesTheStep(t *testing.T) {
	plan := entities.SequencePlan{Steps: []entities.SequenceStep{
		press("a"),
		{Kind: entities.StepDelay, Delay: 500 * time.Millisecond},
		{Kind: entities.StepTypeText, Text: "hello"},
	}}

	var missing *entities.MissingCapability
	err := plan.Validate(entities.NewSet([]string{"gestures"}))
	if !errors.As(err, &missing) {
		t.Fatalf("Validate = %v, want a MissingCapability", err)
	}
	if missing.Step != 3 {
		t.Errorf("step = %d, want 3 -- the typing step, not the plan as a whole", missing.Step)
	}
	if missing.Capability != entities.CapabilityTyping {
		t.Errorf("capability = %q, want typing", missing.Capability)
	}
}

func TestAMalformedStepIsReportedBeforeAnyCapabilityQuestion(t *testing.T) {
	plan := entities.SequencePlan{Steps: []entities.SequenceStep{
		{Kind: entities.StepWaitForSpeech, Match: "ready"},
		{Kind: entities.StepPressGesture}, // no gesture id
	}}

	// A reader with no speech, so the first step is ungated too.
	err := plan.Validate(entities.NewSet(nil))
	var missing *entities.MissingCapability
	if errors.As(err, &missing) {
		t.Fatalf("Validate = %v, want the malformed step reported first", err)
	}
	if err == nil || !strings.Contains(err.Error(), "step 2") {
		t.Fatalf("Validate = %v, want it to name step 2", err)
	}
}

func TestEachStepKindRefusesItsOwnEmptyForm(t *testing.T) {
	for _, one := range []struct {
		what string
		step entities.SequenceStep
	}{
		{"a gesture id", entities.SequenceStep{Kind: entities.StepPressGesture}},
		{"text to type", entities.SequenceStep{Kind: entities.StepTypeText}},
		{"a delay of zero", entities.SequenceStep{Kind: entities.StepDelay}},
		{"a negative delay", entities.SequenceStep{Kind: entities.StepDelay, Delay: -time.Second}},
		{"nothing to wait for", entities.SequenceStep{Kind: entities.StepWaitForSpeech}},
		{"nothing to read", entities.SequenceStep{Kind: entities.StepRead}},
		{
			"a target that is not one",
			entities.SequenceStep{Kind: entities.StepRead, Read: []entities.ReadTarget{"speech"}},
		},
		{"a kind that is not one", entities.SequenceStep{Kind: "restart_the_reader"}},
	} {
		t.Run(one.what, func(t *testing.T) {
			plan := entities.SequencePlan{Steps: []entities.SequenceStep{one.step}}
			if err := plan.Validate(everything()); err == nil {
				t.Fatal("Validate accepted it")
			}
		})
	}
}

func TestThePlanIsBounded(t *testing.T) {
	if err := (entities.SequencePlan{}).Validate(everything()); err == nil {
		t.Error("an empty plan was accepted")
	}

	steps := make([]entities.SequenceStep, entities.MaxSequenceSteps)
	for i := range steps {
		steps[i] = press("a")
	}
	if err := (entities.SequencePlan{Steps: steps}).Validate(everything()); err != nil {
		t.Errorf("a plan of exactly %d steps was refused: %v", entities.MaxSequenceSteps, err)
	}
	tooMany := entities.SequencePlan{Steps: append(steps, press("a"))}
	if err := tooMany.Validate(everything()); err == nil {
		t.Errorf("a plan of %d steps was accepted", entities.MaxSequenceSteps+1)
	}

	for _, one := range []struct {
		what string
		step entities.SequenceStep
	}{
		{"delay", entities.SequenceStep{Kind: entities.StepDelay, Delay: entities.MaxStepWait + time.Second}},
		{"settle", entities.SequenceStep{Kind: entities.StepSettle, Timeout: entities.MaxStepWait + time.Second}},
		{
			"wait_for_speech",
			entities.SequenceStep{
				Kind:    entities.StepWaitForSpeech,
				Match:   "ready",
				Timeout: entities.MaxStepWait + time.Second,
			},
		},
	} {
		t.Run("a "+one.what+" longer than the budget", func(t *testing.T) {
			plan := entities.SequencePlan{Steps: []entities.SequenceStep{one.step}}
			if err := plan.Validate(everything()); err == nil {
				t.Error("Validate accepted a step that outlives the plan's own budget")
			}
		})
	}
}

func TestAZeroTimeoutIsTheReadersDefaultAndIsAccepted(t *testing.T) {
	plan := entities.SequencePlan{Steps: []entities.SequenceStep{
		{Kind: entities.StepSettle},
		{Kind: entities.StepWaitForSpeech, Match: "ready"},
	}}
	if err := plan.Validate(everything()); err != nil {
		t.Errorf("Validate = %v, want a zero timeout accepted", err)
	}
}

func TestReadsBrailleAnswersForTheWholePlan(t *testing.T) {
	neither := entities.SequencePlan{Steps: []entities.SequenceStep{
		press("a"),
		{Kind: entities.StepRead, Read: []entities.ReadTarget{entities.ReadFocus}},
	}}
	if neither.ReadsBraille() {
		t.Error("a plan that reads only focus claims to read braille")
	}

	later := entities.SequencePlan{Steps: append(neither.Steps,
		entities.SequenceStep{Kind: entities.StepRead, Read: []entities.ReadTarget{entities.ReadBraille}},
	)}
	if !later.ReadsBraille() {
		t.Error("a braille read in the LAST step was missed")
	}
}
