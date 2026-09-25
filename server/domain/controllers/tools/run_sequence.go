// screenreader-mcp domain -- the run_sequence tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, gated by its steps, since a plan spans several capabilities.
// USES: entities.SequencePlan and the ports behind ToolContext.
// LISTED BY: registry.go.
package tools

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// DefaultGapMs is the pause after every step, including the last, when the agent names none.
const DefaultGapMs = DefaultGraceMs

const MaxGapMs = 5000

const (
	outcomeCompleted = "completed"
	// outcomeTriggerNotFound: a wait_for_speech step timed out and the remaining steps did not run; it is not an error.
	outcomeTriggerNotFound = "trigger_not_found"
	outcomeFailed          = "failed"
)

type RunSequence struct{}

var _ Tool = (*RunSequence)(nil)

func (t *RunSequence) Name() string { return "run_sequence" }

func (t *RunSequence) Capability() entities.Capability { return entities.GatedByItsSteps }

func (t *RunSequence) Description() string {
	return "Run several intentions in ONE call: a short straight-line plan of steps, " +
		"dispatched back to back with a small pause between them. USE IT WHEN THE " +
		"STEPS ARE KNOWN IN ADVANCE -- typing a value and submitting it, opening " +
		"something and reading where you landed, doing a thing and interrupting it " +
		"while it is still running. Each step reaches the reader in a fraction of a " +
		"millisecond, so timing that is impossible across separate calls -- stopping " +
		"a command that finishes in a second and a half -- is expressible here. " +
		"SIX KINDS OF STEP: `press_gesture` presses one gesture id; `type_text` " +
		"inserts literal text at the focused control; `delay` waits a fixed number " +
		"of milliseconds and is for the APPLICATION's known timing (\"this dialog " +
		"takes half a second\"); `settle` waits for the READER to stop talking and is " +
		"for its unknown latency -- a long deliberate announcement, or reading a " +
		"whole document aloud -- and it can never claim the reader is finished, only " +
		"that it stopped answering; `wait_for_speech` blocks until an utterance " +
		"contains your text and then carries straight on, which is how you act on a " +
		"trigger; `read` orients you afterwards, reporting the focused object and " +
		"optionally the braille display. WHAT COMES BACK: ONE merged speech window " +
		"for the whole plan, plus a `speechFrom`/`speechTo` bookmark per step, so " +
		"you can see which step spoke and which was silent -- a step whose span is " +
		"empty said nothing, and it is reported rather than omitted. `outcome` has " +
		"THREE values and they mean different things: `completed`, `trigger_not_found` " +
		"(a wait_for_speech step timed out, which is an ANSWER and not an error -- " +
		"the remaining steps did not run, and `failedStep` says which one waited), " +
		"and `failed` (a step broke, or the plan ran out of its 30-second budget; " +
		"`failedStep` and `message` say which and why). A plan ABORTS ON THE FIRST " +
		"FAILURE and nothing is undone: keystrokes cannot be un-pressed, so the " +
		"per-step results are there to show you how far it got. THE WHOLE PLAN IS " +
		"CHECKED BEFORE THE FIRST KEYSTROKE against what this reader announced, so a " +
		"plan naming something it cannot do is refused entire, naming the step. " +
		"LIMITS: at most 32 steps and about 30 seconds. A plan is a bet placed " +
		"before the first keystroke -- its steps cannot react to what the reader " +
		"says, except by stopping -- so if what you do second depends on what you " +
		"heard first, that is two calls and should be. Use `announce` to tell the " +
		"human at the keyboard what the plan is about to do; it is spoken before " +
		"step 1 and comes back as `announced`, which confirms it was SAID and never " +
		"that it was heard. Read screenreader://guidance for the loop this fits into."
}

func (t *RunSequence) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"steps": {
			"type": "array",
			"minItems": 1,
			"maxItems": 32,
			"description": "The plan, in order. Each element is an object with EXACTLY ONE of the six keys below; the key is the kind of step and its value is what that step needs. Steps run back to back with gap_ms between them, and the plan stops at the first failure or unmet trigger.",
			"items": {
				"type": "object",
				"minProperties": 1,
				"maxProperties": 1,
				"additionalProperties": false,
				"description": "One step: exactly one key.",
				"properties": {
					"press_gesture": {
						"type": "string",
						"description": "Press one gesture id, in the reader's own user-facing command notation, passed through unchanged. Take the spelling from screenreader://reader-guidance, which connect_reader returns in full. One id per step: to press three keys, write three steps, and each gets its own bookmark."
					},
					"type_text": {
						"type": "string",
						"description": "Insert this literal text at whatever holds focus. Layout-independent content, not commands: it does not interpret newlines and submits nothing, so follow it with a press_gesture step to commit."
					},
					"delay": {
						"type": "integer",
						"minimum": 1,
						"maximum": 30000,
						"description": "Wait this many milliseconds. For the APPLICATION's own known timing -- \"this dialog takes half a second to appear\", \"this command runs for a second before I interrupt it\". It observes nothing, so never treat having waited as evidence: pair it with a read or with the speech that comes back."
					},
					"settle": {
						"type": "number",
						"minimum": 0,
						"maximum": 30,
						"description": "Wait for the READER to stop talking, at most this many seconds; 0 for its own default. For its unknown latency -- a long deliberate announcement, or reading a whole document aloud. It asks \"has speech stopped?\", which can never be a claim that the reader is finished, only that it stopped answering; it is NOT the step to put after every action."
					},
					"wait_for_speech": {
						"type": "object",
						"description": "Block until the reader says something containing this text, then carry straight on -- the next step fires as soon as it lands. This is how you act on a trigger. If it never arrives the plan stops with outcome trigger_not_found, which is an answer rather than an error.",
						"properties": {
							"text": {
								"type": "string",
								"description": "Matched as a substring of one utterance. It matches anything said since the plan STARTED, so a trigger that arrives a moment before this step is reached is not missed."
							},
							"timeout": {
								"type": "number",
								"exclusiveMinimum": 0,
								"maximum": 30,
								"description": "How long to wait, in seconds. Omit for the reader's own default."
							}
						},
						"required": ["text"],
						"additionalProperties": false
					},
					"read": {
						"type": "array",
						"items": {"type": "string", "enum": ["focus", "braille"]},
						"description": "Orient: where did this land? \"focus\" describes the focused object; \"braille\" reports what reached the braille display since the previous read in this plan. An empty list means [\"focus\"]. There is no \"speech\" here and none is needed: the merged window already covers the whole plan. There is no \"state\" either: it is on the result already."
					}
				}
			}
		},
		"gap_ms": {
			"type": "integer",
			"minimum": 0,
			"maximum": 5000,
			"description": "How long to pause after EACH step, including the last, in milliseconds. Omit for the default (100), which is where the speech a keystroke causes usually already is. This is the plan's single timing knob -- anything longer or deliberate belongs in a delay step. 0 opts out."
		},
		"announce": {
			"type": "string",
			"description": "Spoken aloud to the human at the reader before step 1 -- audible even in a silent session, which is what it is FOR. A plan can occupy the reader for several seconds, so in a SILENT session with somebody there, say what it is about to do: those seconds are silence they cannot account for. In a LIVE session they hear every step as it happens, so announcing the plan talks over the run they are listening to -- say something only if the plan will do something surprising or leave the reader quiet. Never narrate to an unattended machine; see silenceCap on connect_reader for whether anyone is there. A refused plan says nothing: if you asked for something this reader cannot do, that is a message for you and not for them."
		}
	},
	"required": ["steps"],
	"additionalProperties": false
}`)
}

func (t *RunSequence) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"outcome": {
			"type": "string",
			"enum": ["completed", "trigger_not_found", "failed"],
			"description": "THREE values, and the middle one is not an error: \"completed\" -- every step ran; \"trigger_not_found\" -- a wait_for_speech step timed out and the remaining steps did not run; \"failed\" -- a step broke or the plan ran out of budget. The trigger never firing and a step breaking call for different next moves, which is why they are different answers."
		},
		"failedStep": {
			"type": "integer",
			"description": "Which step stopped the plan, counting from 1. ABSENT when the plan completed. For trigger_not_found it names the step that waited; for failed, the step that broke."
		},
		"message": {
			"type": "string",
			"description": "Why the plan failed, in the reader's or the server's own words. ABSENT unless the outcome is \"failed\": a trigger that never fired needs no explanation beyond which step waited."
		},
		"steps": {
			"type": "array",
			"description": "One entry per step that RAN, in order -- shorter than the plan when it stopped early, which is how you see how far it got. Each carries its own window, so a silent step is visible rather than inferred.",
			"items": {
				"type": "object",
				"properties": {
					"step": {"type": "integer", "description": "Its place in the plan, counting from 1."},
					"kind": {"type": "string", "description": "Which of the six kinds this step was."},
					"speechFrom": {"type": "integer", "description": "The speech index the ring stood at when this step was dispatched."},
					"speechTo": {"type": "integer", "description": "And when the next one was. An EMPTY span is a real answer: this step said nothing, and most reader commands never move focus."},
					"gesture": {"type": "string", "description": "The gesture id, echoed unchanged. Present only on a press_gesture step."},
					"typed": {"type": "integer", "description": "The LENGTH of what was sent, counted by the reader that injected it; the text itself is never echoed back. Present only on a type_text step."},
					"settled": {"type": "boolean", "description": "Whether the reader stopped talking before this settle step's timeout. Present only on a settle step. It says the reader stopped answering, never that it had finished."},
					"matched": {
						"type": "object",
						"description": "What a wait_for_speech step found. Present only on such a step.",
						"properties": {
							"found": {"type": "boolean", "description": "Whether matching speech appeared before the timeout. False stopped the plan, with outcome trigger_not_found."},
							"index": {"type": "integer", "description": "The matching utterance's index. On a miss, the ring's current index."},
							"text": {"type": "string", "description": "The matching utterance in full, not just the substring you waited for. Empty on a miss."},
							"logPosition": {"type": "integer", "description": "Where the match sits on the reader's log journal; hand it to get_log as since_position."},
							"emittedAt": {"type": "string", "description": "When the match was emitted. Absent on a miss."}
						},
						"required": ["found", "index", "text", "logPosition"]
					},
					"focus": {
						"type": "object",
						"description": "The focused object, from a read step that asked for it.",
						"properties": {
							"name": {"type": "string", "description": "Its accessible name. AN EMPTY NAME IS A FINDING, not a blank."},
							"role": {"type": "string", "description": "Its role, in the READER's own vocabulary."},
							"states": {"type": "array", "items": {"type": "string"}, "description": "Its states, in the reader's vocabulary. Empty list, never null."},
							"value": {"type": ["string", "null"], "description": "Its value, or null. Null and the empty string are DIFFERENT answers."},
							"appModule": {"type": ["string", "null"], "description": "The reader's own module handling the owning application, or null."}
						},
						"required": ["name", "role", "states", "value", "appModule"]
					},
					"braille": {
						"type": "object",
						"description": "What reached the braille display, from a read step that asked for it: everything since the previous read in this plan, or since the plan began.",
						"properties": {
							"entries": {
								"type": "array",
								"description": "One entry per display update, oldest first. Empty when nothing was brailled -- never null.",
								"items": {
									"type": "object",
									"properties": {
										"text": {"type": "string", "description": "What was sent to the display. Often abbreviated differently from what was spoken."},
										"index": {"type": "integer", "description": "This update's place in the BRAILLE ring, which is not interchangeable with a speech index."},
										"logPosition": {"type": "integer", "description": "Where this update sits on the reader's log journal."},
										"emittedAt": {"type": "string", "description": "Always absent here: braille updates carry no emission time."}
									},
									"required": ["text", "index", "logPosition"]
								}
							},
							"fromIndex": {"type": "integer", "description": "The first braille index this read covered."},
							"toIndex": {"type": "integer", "description": "One past the last: the range is [fromIndex, toIndex)."}
						},
						"required": ["entries", "fromIndex", "toIndex"]
					}
				},
				"required": ["step", "kind", "speechFrom", "speechTo"]
			}
		},
		"speech": {
			"type": "array",
			"description": "Everything the reader said across the WHOLE plan, oldest first: one window from the first step's dispatch to the pause after the last. Empty means nothing had arrived by that instant -- NOT that nothing happened. Never null.",
			"items": {
				"type": "object",
				"properties": {
					"text": {"type": "string", "description": "What the reader spoke."},
					"index": {"type": "integer", "description": "This utterance's place in the speech ring."},
					"logPosition": {"type": "integer", "description": "Where it sits on the reader's log journal; hand it to get_log as since_position."},
					"emittedAt": {"type": "string", "description": "When the reader emitted it. Absent if the reader supplied none."}
				},
				"required": ["text", "index", "logPosition"]
			}
		},
		"speechFrom": {"type": "integer", "description": "The first speech index this plan covered."},
		"speechTo": {"type": "integer", "description": "One past the last: the window is [speechFrom, speechTo), so speechTo is exactly what to read from next. Slow effects legitimately arrive after it -- read again from here rather than running the plan twice."},
		"announced": {"type": "string", "description": "The announcement that was spoken to the human before step 1, echoed back. ABSENT when you asked for none. It confirms the announcement was MADE, never that it was HEARD: speech is emitted around five seconds ahead of audio."},
		"state": {
			"type": "object",
			"description": "The modes you cannot hear, sampled once the plan had finished. ABSENT when the reader serves no state capability: absent and \"all four fields zero\" are different answers. Deliberately not focus information.",
			"properties": {
				"browseMode": {"type": "string", "enum": ["browse", "focus", "none"], "description": "\"none\" when there is no browsable document -- the absence IS one of the three answers."},
				"speechMode": {"type": "string", "description": "The reader's speech mode, in its own vocabulary."},
				"sleepMode": {"type": "boolean", "description": "Whether the reader is asleep for the focused application."},
				"inputHelp": {"type": "boolean", "description": "Whether input help is on -- if it is, keys are described rather than acted on."}
			},
			"required": ["browseMode", "speechMode", "sleepMode", "inputHelp"]
		}
	},
	"required": ["outcome", "steps", "speech", "speechFrom", "speechTo"]
}`)
}

type runSequenceParams struct {
	Steps    []sequenceStepParams `json:"steps"`
	GapMs    *int                 `json:"gap_ms"`
	Announce string               `json:"announce"`
}

// sequenceStepParams has exactly one non-nil field, whose name is the discriminator; pointers keep present distinct from zero.
type sequenceStepParams struct {
	PressGesture  *string         `json:"press_gesture"`
	TypeText      *string         `json:"type_text"`
	Delay         *int            `json:"delay"`
	Settle        *float64        `json:"settle"`
	WaitForSpeech *waitStepParams `json:"wait_for_speech"`
	Read          *[]string       `json:"read"`
}

type waitStepParams struct {
	Text    string  `json:"text"`
	Timeout float64 `json:"timeout"`
}

type sequenceStepResult struct {
	Step int    `json:"step"`
	Kind string `json:"kind"`
	// [SpeechFrom, SpeechTo) is half-open; an empty span means this step said nothing.
	SpeechFrom int `json:"speechFrom"`
	SpeechTo   int `json:"speechTo"`

	Gesture string               `json:"gesture,omitempty"`
	Typed   *int                 `json:"typed,omitempty"`
	Settled *bool                `json:"settled,omitempty"`
	Matched *waitForSpeechResult `json:"matched,omitempty"`
	Focus   *focusResult         `json:"focus,omitempty"`
	Braille *speechRangeResult   `json:"braille,omitempty"`
}

type runSequenceResult struct {
	Outcome string `json:"outcome"`
	// FailedStep counts from 1 and is absent when the plan completed.
	FailedStep int `json:"failedStep,omitempty"`
	// Message accompanies only outcomeFailed.
	Message string               `json:"message,omitempty"`
	Steps   []sequenceStepResult `json:"steps"`
	observation
}

func (t *RunSequence) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	session, err := ctx.Session()
	if err != nil {
		return nil, err
	}
	var request runSequenceParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	plan, err := parsePlan(request.Steps)
	if err != nil {
		return nil, err
	}
	announced, err := announcement(request.Announce)
	if err != nil {
		return nil, err
	}
	gap, err := gapFor(request.GapMs)
	if err != nil {
		return nil, err
	}
	// The whole plan is validated before the first keystroke and before the announcement, so a refusal presses and speaks nothing.
	if err := plan.Validate(session.Capabilities); err != nil {
		return nil, refusal(ctx, err)
	}
	if announced != "" {
		interact, err := ctx.Interact()
		if err != nil {
			return nil, err
		}
		if err := interact.Announce(announced); err != nil {
			return nil, err
		}
	}

	run := newSequenceRun(ctx, plan, gap)
	outcome, failedStep, message, err := run.walk()
	if err != nil {
		// A lost connection must be an error so the dispatcher records it; every other failure stays a result.
		return nil, err
	}
	window, err := run.observe(announced)
	if err != nil && outcome == outcomeCompleted {
		return nil, fmt.Errorf("the plan ran, but reading back what it said failed: %w", err)
	}
	return runSequenceResult{
		Outcome:     outcome,
		FailedStep:  failedStep,
		Message:     message,
		Steps:       run.steps,
		observation: window,
	}, nil
}

func refusal(ctx ToolContext, err error) error {
	var missing *entities.MissingCapability
	if !errors.As(err, &missing) {
		return err
	}
	failure := ctx.missing(missing.Capability)
	failure.Step = missing.Step
	return failure
}

// gapFor: absent means the default, which is not the same as 0.
func gapFor(asked *int) (time.Duration, error) {
	gap := DefaultGapMs
	if asked != nil {
		gap = *asked
	}
	if gap < 0 {
		return 0, errors.New("gap_ms cannot be negative")
	}
	if gap > MaxGapMs {
		return 0, fmt.Errorf("gap_ms may be at most %d; anything longer is a delay step, "+
			"which says what it is waiting for", MaxGapMs)
	}
	return time.Duration(gap) * time.Millisecond, nil
}

func parsePlan(steps []sequenceStepParams) (entities.SequencePlan, error) {
	parsed := make([]entities.SequenceStep, 0, len(steps))
	for i, raw := range steps {
		step, err := raw.step()
		if err != nil {
			return entities.SequencePlan{}, fmt.Errorf("step %d: %w", i+1, err)
		}
		parsed = append(parsed, step)
	}
	return entities.SequencePlan{Steps: parsed}, nil
}

func (p sequenceStepParams) step() (entities.SequenceStep, error) {
	named := 0
	step := entities.SequenceStep{}
	if p.PressGesture != nil {
		named++
		step = entities.SequenceStep{Kind: entities.StepPressGesture, Gesture: *p.PressGesture}
	}
	if p.TypeText != nil {
		named++
		step = entities.SequenceStep{Kind: entities.StepTypeText, Text: *p.TypeText}
	}
	if p.Delay != nil {
		named++
		step = entities.SequenceStep{
			Kind:  entities.StepDelay,
			Delay: time.Duration(*p.Delay) * time.Millisecond,
		}
	}
	if p.Settle != nil {
		named++
		step = entities.SequenceStep{Kind: entities.StepSettle, Timeout: seconds(*p.Settle)}
	}
	if p.WaitForSpeech != nil {
		named++
		step = entities.SequenceStep{
			Kind:    entities.StepWaitForSpeech,
			Match:   p.WaitForSpeech.Text,
			Timeout: seconds(p.WaitForSpeech.Timeout),
		}
	}
	if p.Read != nil {
		named++
		step = entities.SequenceStep{Kind: entities.StepRead, Read: readTargets(*p.Read)}
	}

	switch named {
	case 1:
		return step, nil
	case 0:
		return step, errors.New("names no kind of step; give it exactly one of " +
			"press_gesture, type_text, delay, settle, wait_for_speech or read")
	default:
		return step, errors.New("names more than one kind of step; a step is one " +
			"intention, so write them as separate steps")
	}
}

// readTargets defaults an empty list to focus, and passes unknown strings through so the plan's validation rejects them by step.
func readTargets(asked []string) []entities.ReadTarget {
	if len(asked) == 0 {
		return []entities.ReadTarget{entities.ReadFocus}
	}
	targets := make([]entities.ReadTarget, 0, len(asked))
	for _, one := range asked {
		targets = append(targets, entities.ReadTarget(one))
	}
	return targets
}

// seconds keeps zero as zero, which every port reads as the reader's own default.
func seconds(value float64) time.Duration {
	if value <= 0 {
		return 0
	}
	return time.Duration(value * float64(time.Second))
}

type sequenceRun struct {
	ctx  ToolContext
	plan entities.SequencePlan
	gap  time.Duration

	// speech is nil when the reader serves none, and then every span is empty.
	speech ports.SpeechReader

	deadline time.Time

	start int
	at    int
	// braille is where the braille ring stood at the last read, so a second read reports only what arrived since.
	braille int

	steps []sequenceStepResult
}

func newSequenceRun(ctx ToolContext, plan entities.SequencePlan, gap time.Duration) *sequenceRun {
	run := &sequenceRun{
		ctx:      ctx,
		plan:     plan,
		gap:      gap,
		deadline: ctx.Clock.Now().Add(entities.SequenceBudget),
		steps:    make([]sequenceStepResult, 0, len(plan.Steps)),
	}
	if speech, err := ctx.Speech(); err == nil {
		run.speech = speech
	}
	run.start = run.mark()
	run.at = run.start
	run.markBraille()
	return run
}

// A failed mark leaves the mark unmoved, which reads as a silent step.
func (r *sequenceRun) mark() int {
	if r.speech == nil {
		return r.at
	}
	next, err := r.speech.NextSpeechIndex()
	if err != nil {
		return r.at
	}
	return next
}

func (r *sequenceRun) markBraille() {
	if !r.plan.ReadsBraille() {
		return
	}
	braille, err := r.ctx.Braille()
	if err != nil {
		return
	}
	if captured, err := braille.BrailleSince(0); err == nil {
		r.braille = captured.ToIndex
	}
}

// walk aborts on the first failure and rolls nothing back; its error return is reserved for a lost connection.
func (r *sequenceRun) walk() (outcome string, failedStep int, message string, err error) {
	for i, step := range r.plan.Steps {
		number := i + 1
		if !r.ctx.Clock.Now().Before(r.deadline) {
			return outcomeFailed, number, fmt.Sprintf(
				"the plan's %s budget ran out before step %d could run",
				entities.SequenceBudget, number), nil
		}
		result := sequenceStepResult{Step: number, Kind: string(step.Kind), SpeechFrom: r.at}
		continued, failure := r.dispatch(step, &result)
		r.steps = append(r.steps, result)
		// The gap runs after every step, including a failed one and the last, so that step's speech reaches the merged read.
		r.ctx.Clock.Sleep(r.gap)
		r.at = r.mark()
		r.close(number)

		switch {
		case failure != nil && errors.Is(failure, ports.ErrConnectionLost):
			return "", 0, "", failure
		case failure != nil:
			return outcomeFailed, number, failure.Error(), nil
		case !continued:
			return outcomeTriggerNotFound, number, "", nil
		}
	}
	return outcomeCompleted, 0, "", nil
}

// close ends the step at the mark taken after its gap, so consecutive spans meet exactly.
func (r *sequenceRun) close(number int) {
	r.steps[number-1].SpeechTo = r.at
}

// dispatch reports whether the plan continues; only a wait_for_speech step can answer no.
func (r *sequenceRun) dispatch(step entities.SequenceStep, into *sequenceStepResult) (bool, error) {
	switch step.Kind {
	case entities.StepPressGesture:
		gestures, err := r.ctx.Gestures()
		if err != nil {
			return true, err
		}
		if _, err := gestures.PressGestures([]string{step.Gesture}, 0, ""); err != nil {
			return true, err
		}
		into.Gesture = step.Gesture
		return true, nil

	case entities.StepTypeText:
		typer, err := r.ctx.Text()
		if err != nil {
			return true, err
		}
		outcome, err := typer.TypeText(step.Text, 0, "")
		if err != nil {
			return true, err
		}
		typed := outcome.Typed
		into.Typed = &typed
		return true, nil

	case entities.StepDelay:
		r.ctx.Clock.Sleep(step.Delay)
		return true, nil

	case entities.StepSettle:
		speech, err := r.ctx.Speech()
		if err != nil {
			return true, err
		}
		settled, err := speech.WaitForSpeechToFinish(step.Timeout)
		if err != nil {
			return true, err
		}
		into.Settled = &settled
		return true, nil

	case entities.StepWaitForSpeech:
		speech, err := r.ctx.Speech()
		if err != nil {
			return true, err
		}
		// Matched from the plan's start: the trigger can land between the previous step's dispatch and this one's.
		after := r.start
		match, err := speech.WaitForSpeech(ports.SpeechWait{
			Text:       step.Match,
			AfterIndex: &after,
			Timeout:    step.Timeout,
		})
		if err != nil {
			return true, err
		}
		into.Matched = &waitForSpeechResult{
			Found:       match.Found,
			Index:       match.Index,
			Text:        match.Text,
			LogPosition: match.LogPosition,
			EmittedAt:   match.EmittedAt,
		}
		return match.Found, nil

	case entities.StepRead:
		return true, r.read(step.Read, into)
	}
	// Unreachable: the plan's own validation refused any other kind.
	return true, fmt.Errorf("%q is not a step kind", step.Kind)
}

func (r *sequenceRun) read(targets []entities.ReadTarget, into *sequenceStepResult) error {
	for _, target := range targets {
		switch target {
		case entities.ReadFocus:
			focus, err := r.ctx.Focus()
			if err != nil {
				return err
			}
			info, err := focus.FocusInfo()
			if err != nil {
				return err
			}
			states := info.States
			if states == nil {
				states = []string{}
			}
			into.Focus = &focusResult{
				Name:      info.Name,
				Role:      info.Role,
				States:    states,
				Value:     info.Value,
				AppModule: info.AppModule,
			}

		case entities.ReadBraille:
			braille, err := r.ctx.Braille()
			if err != nil {
				return err
			}
			captured, err := braille.BrailleSince(r.braille)
			if err != nil {
				return err
			}
			entries := make([]capturedEntry, 0, len(captured.Entries))
			for _, entry := range captured.Entries {
				entries = append(entries, capturedEntry{
					Text:        entry.Text,
					Index:       entry.Index,
					LogPosition: entry.LogPosition,
				})
			}
			into.Braille = &speechRangeResult{
				Entries:   entries,
				FromIndex: captured.FromIndex,
				ToIndex:   captured.ToIndex,
			}
			r.braille = captured.ToIndex
		}
	}
	return nil
}

// observe moves the last step's right edge to the read's own end, so speech that arrived mid-read belongs to that step.
func (r *sequenceRun) observe(announced string) (observation, error) {
	seen := ports.Observation{FromIndex: r.start, ToIndex: r.at}
	var failure error
	if r.speech != nil {
		captured, err := r.speech.SpeechSince(r.start)
		if err != nil {
			failure = err
		} else {
			seen.Speech = captured.Entries
			seen.FromIndex = captured.FromIndex
			seen.ToIndex = captured.ToIndex
			if len(r.steps) > 0 {
				r.steps[len(r.steps)-1].SpeechTo = captured.ToIndex
			}
		}
	}
	// Sampled once, at the end, so it reports the modes the plan left the reader in.
	if inspector, err := r.ctx.State(); err == nil {
		if state, err := inspector.State(); err == nil {
			seen.State = &state
		}
	}
	return observed(seen, announced), failure
}
