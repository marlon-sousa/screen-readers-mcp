// screenreader-mcp domain -- SequencePlan: several intentions, in one call.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. The parsed plan a run_sequence call carries -- an ordered list
// of steps, each knowing which capabilities it needs -- plus Validate, which is
// the whole up-front gate.
// BUILT BY: domain/controllers/tools/run_sequence.go, from the call's params.
// READ BY: the same controller, which walks the steps through the ports.
//
// PURE. No IO, no ports, no clock: a plan is a value, and running one is the
// controller's job. Its own DTOs -- SequenceStep, ReadTarget, MissingCapability
// -- live in this file, per AGENTS.md's rule that a type belongs with the thing
// that owns it.
//
// THE STEP VOCABULARY IS CLOSED, and deliberately not a {tool, params}
// passthrough over the registry (spec 0036, part 2). A passthrough would let
// connect_reader, disconnect_reader or ask_user be nested inside a plan, where
// none of them has a meaning; it could not be described, and the description is
// where this server's usability lives; and the gate below has to know what a
// step MEANS in order to refuse a plan before the first keystroke is delivered.
//
// WHY THE GATE IS HERE AND NOT IN THE CONTROLLER. "Which capability does this
// step need" is a fact about the step, so it lives on the step -- which is what
// makes the controller's refusal one line and makes the mapping testable without
// a session, a port or a fake. The controller still owns turning a refusal into
// the agent-facing CapabilityError, because that type is the tools package's.
package entities

import (
	"errors"
	"fmt"
	"slices"
	"time"
)

// MaxSequenceSteps bounds a plan so a malformed one cannot occupy the session.
//
// Spec 0036, part 3.3. Thirty-two is not a measurement: it is comfortably more
// than any plan anybody has wanted and comfortably less than a loop.
const MaxSequenceSteps = 32

// SequenceBudget is the wall clock a whole plan may spend before it stops and
// reports how far it got.
//
// It is a BACKSTOP for the sum of the waiting steps, not a substitute for their
// own timeouts: settle and wait_for_speech each carry one, and MaxStepWait keeps
// any single one of them from being the runaway.
const SequenceBudget = 30 * time.Second

// MaxStepWait bounds a single step's own wait -- a delay's length, a settle's or
// a trigger's timeout -- so that one step cannot outlive the budget the plan is
// held to.
const MaxStepWait = 30 * time.Second

// SequenceStepKind names one of the six things a step can be.
//
// The four that ACT or WAIT are the vocabulary an agent thinks in; the
// distinction that matters most is delay against settle, and the descriptions
// have to say which is which: `delay` is for the APPLICATION's known timing
// ("this dialog takes half a second"), `settle` for the READER's unknown
// latency (a long deliberate announcement, a say-all). A plan that can only
// sleep is a machine for mass-producing the failure spec 0023 exists to prevent.
type SequenceStepKind string

const (
	// StepPressGesture presses one gesture id, opaque as everywhere else.
	StepPressGesture SequenceStepKind = "press_gesture"
	// StepTypeText inserts literal text at the focused control.
	StepTypeText SequenceStepKind = "type_text"
	// StepDelay waits a fixed time: the application's own known timing.
	StepDelay SequenceStepKind = "delay"
	// StepSettle waits for the reader to stop talking: its unknown latency.
	StepSettle SequenceStepKind = "settle"
	// StepWaitForSpeech blocks until an utterance matches. This is
	// act-on-trigger, and it costs no new concept: the next step fires as
	// soon as the match lands, where the hop is a fraction of a millisecond
	// rather than a model turn.
	StepWaitForSpeech SequenceStepKind = "wait_for_speech"
	// StepRead orients: where did this land?
	StepRead SequenceStepKind = "read"
)

// ReadTarget names one thing a read step orients with.
//
// A LIST ON ONE STEP rather than one step kind per getter (spec 0036, part 2):
// it keeps the vocabulary at six, states the intent as "orient me" rather than
// "call this getter", and makes braille one enum value instead of a seventh
// kind. Each element gates independently, which Validate handles with no special
// case.
//
// Speech is deliberately absent, and so is state. The merged window already
// spans the whole plan, so a trailing speech read returns an identical set, and
// state rides on the result of every mutating call already (spec 0025, part 3).
type ReadTarget string

const (
	// ReadFocus is the focused object, in the reader's own vocabulary.
	ReadFocus ReadTarget = "focus"
	// ReadBraille is what reached the braille display during the plan.
	ReadBraille ReadTarget = "braille"
)

// SequenceStep is one intention. Only the fields its Kind uses are read; the
// rest are zero, and Validate is what says so before anything is dispatched.
type SequenceStep struct {
	// Kind decides which of the fields below mean anything.
	Kind SequenceStepKind

	// Gesture is the opaque gesture id, for StepPressGesture.
	Gesture string

	// Text is the literal content, for StepTypeText.
	Text string

	// Delay is how long StepDelay waits.
	Delay time.Duration

	// Timeout is how long StepSettle or StepWaitForSpeech waits. Zero means
	// the reader's own default, exactly as it does on the tools.
	Timeout time.Duration

	// Match is the text StepWaitForSpeech waits for.
	Match string

	// Read is what StepRead orients with, in the order asked for.
	Read []ReadTarget
}

// Capabilities is what the reader must have announced for this step to run.
//
// A LIST, because a read step can ask for two things at once and each gates on
// its own. Empty for a delay, which asks the reader for nothing at all -- the
// one step kind that runs on a session with no capabilities whatsoever.
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

// SequencePlan is the whole ordered plan.
//
// A straight line, and it stays one (spec 0036, "what is deliberately not
// built"): no branching, no conditionals, no loops. StepWaitForSpeech is the
// only thing resembling a condition and it can only STOP the plan, never choose
// between two continuations. Anything more is a scripting language, and the
// agent already is one.
type SequencePlan struct {
	Steps []SequenceStep
}

// ReadsBraille says whether any step will ask for the braille display.
//
// A question about the PLAN rather than a step, and it is asked before anything
// runs: braille has no next-index probe, so the only way to learn where its ring
// stands is to read it -- and a plan that never reads braille must not pay for
// that read, nor require a capability it does not use.
func (p SequencePlan) ReadsBraille() bool {
	for _, step := range p.Steps {
		if slices.Contains(step.Capabilities(), CapabilityBraille) {
			return true
		}
	}
	return false
}

// MissingCapability is a step naming something the connected reader never
// announced.
//
// Its own type so the controller can rebuild it as the agent-facing
// CapabilityError -- which already carries the tool, the capability and the
// reader's name -- with the step number added. The entity cannot build that
// error itself: CapabilityError belongs to the tools package, and an entity that
// imported a controller would be the dependency running backwards.
type MissingCapability struct {
	// Step is which step, counting from 1 as the result does.
	Step int
	// Capability is what that step needed.
	Capability Capability
}

func (e *MissingCapability) Error() string {
	return fmt.Sprintf("step %d needs the %q capability", e.Step, e.Capability)
}

// Validate is the whole up-front gate: the plan is refused ENTIRE, before the
// first keystroke is delivered, rather than discovered broken halfway through
// with the reader left mid-edit.
//
// TWO PASSES, and the order is deliberate. A malformed step is the agent's own
// typo and is fixable without knowing anything about the reader; a missing
// capability is a fact about the session. Reporting every shape problem first
// means an agent is never sent to look at the reader for a mistake it made in
// its own JSON.
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

// validate is one step's own shape: the kind is one we know, and the field that
// kind reads carries something usable.
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
			// Refused here for wait_for_speech's own reason: waiting for
			// the empty string matches the first thing said, which is
			// never what anyone meant and looks like a working assertion.
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

// validateTimeout holds a waiting step to the per-step bound, so no single step
// can outlive the plan's budget on its own.
func (s SequenceStep) validateTimeout(kind string) error {
	if s.Timeout < 0 {
		return fmt.Errorf("a %s step cannot wait for a negative time", kind)
	}
	if s.Timeout > MaxStepWait {
		return fmt.Errorf("a %s step may wait at most %s", kind, MaxStepWait)
	}
	return nil
}
