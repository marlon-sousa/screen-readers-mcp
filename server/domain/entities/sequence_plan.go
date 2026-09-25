// screenreader-mcp domain -- SequencePlan: several intentions, in one call.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, the parsed plan a run_sequence call carries, and Validate, the whole up-front gate.
// BUILT BY: domain/controllers/tools/run_sequence.go, from the call's params.
// READ BY: the same controller, which walks the steps through the ports.
package entities

import (
	"errors"
	"fmt"
	"slices"
	"time"
)

const MaxSequenceSteps = 32

// SequenceBudget is a backstop for the sum of the waiting steps, not a
// substitute for their own timeouts.
const SequenceBudget = 30 * time.Second

const MaxStepWait = 30 * time.Second

type SequenceStepKind string

const (
	StepPressGesture  SequenceStepKind = "press_gesture"
	StepTypeText      SequenceStepKind = "type_text"
	StepDelay         SequenceStepKind = "delay"
	StepSettle        SequenceStepKind = "settle"
	StepWaitForSpeech SequenceStepKind = "wait_for_speech"
	StepRead          SequenceStepKind = "read"
)

type ReadTarget string

const (
	ReadFocus   ReadTarget = "focus"
	ReadBraille ReadTarget = "braille"
)

type SequenceStep struct {
	Kind SequenceStepKind

	Gesture string

	Text string

	Delay time.Duration

	// Timeout zero means the reader's own default.
	Timeout time.Duration

	Match string

	Read []ReadTarget
}

// Capabilities is empty for a delay, the one step kind that runs on a session with no capabilities.
func (s SequenceStep) Capabilities() []Capability {
	switch s.Kind {
	case StepPressGesture:
		return []Capability{CapabilityGestures}
	case StepTypeText:
		return []Capability{CapabilityTyping}
	case StepSettle, StepWaitForSpeech:
		return []Capability{CapabilitySpeech}
	case StepRead:
		needed := make([]Capability, 0, len(s.Read))
		for _, target := range s.Read {
			switch target {
			case ReadFocus:
				needed = append(needed, CapabilityFocus)
			case ReadBraille:
				needed = append(needed, CapabilityBraille)
			}
		}
		return needed
	case StepDelay:
		return nil
	}
	return nil
}

type SequencePlan struct {
	Steps []SequenceStep
}

// ReadsBraille is asked before anything runs, because braille has no next-index
// probe and a plan that never reads braille must not pay for the read that
// stands in for one.
func (p SequencePlan) ReadsBraille() bool {
	for _, step := range p.Steps {
		if slices.Contains(step.Capabilities(), CapabilityBraille) {
			return true
		}
	}
	return false
}

type MissingCapability struct {
	Step       int
	Capability Capability
}

func (e *MissingCapability) Error() string {
	return fmt.Sprintf("step %d needs the %q capability", e.Step, e.Capability)
}

// Validate refuses the whole plan before the first keystroke, reporting every
// malformed step before any missing capability.
func (p SequencePlan) Validate(announced Set) error {
	if len(p.Steps) == 0 {
		return errors.New("a plan needs at least one step")
	}
	if len(p.Steps) > MaxSequenceSteps {
		return fmt.Errorf("a plan may hold at most %d steps, and this one holds %d: "+
			"split it, or drive the rest in a second call", MaxSequenceSteps, len(p.Steps))
	}
	for i, step := range p.Steps {
		if err := step.validate(); err != nil {
			return fmt.Errorf("step %d: %w", i+1, err)
		}
	}
	for i, step := range p.Steps {
		for _, capability := range step.Capabilities() {
			if !announced.Has(capability) {
				return &MissingCapability{Step: i + 1, Capability: capability}
			}
		}
	}
	return nil
}

func (s SequenceStep) validate() error {
	switch s.Kind {
	case StepPressGesture:
		if s.Gesture == "" {
			return errors.New("a press_gesture step needs a gesture id")
		}
	case StepTypeText:
		if s.Text == "" {
			return errors.New("a type_text step needs text to type")
		}
	case StepDelay:
		if s.Delay <= 0 {
			return errors.New("a delay step needs a positive number of milliseconds")
		}
		if s.Delay > MaxStepWait {
			return fmt.Errorf("a delay step may wait at most %s", MaxStepWait)
		}
	case StepSettle:
		if err := s.validateTimeout("settle"); err != nil {
			return err
		}
	case StepWaitForSpeech:
		if s.Match == "" {
			// An empty match would pass on the first utterance.
			return errors.New("a wait_for_speech step needs the text to wait for")
		}
		if err := s.validateTimeout("wait_for_speech"); err != nil {
			return err
		}
	case StepRead:
		if len(s.Read) == 0 {
			return errors.New("a read step needs something to read")
		}
		for _, target := range s.Read {
			if target != ReadFocus && target != ReadBraille {
				return fmt.Errorf("a read step cannot read %q", target)
			}
		}
	default:
		return fmt.Errorf("%q is not a step kind", s.Kind)
	}
	return nil
}

func (s SequenceStep) validateTimeout(kind string) error {
	if s.Timeout < 0 {
		return fmt.Errorf("a %s step cannot wait for a negative time", kind)
	}
	if s.Timeout > MaxStepWait {
		return fmt.Errorf("a %s step may wait at most %s", kind, MaxStepWait)
	}
	return nil
}
