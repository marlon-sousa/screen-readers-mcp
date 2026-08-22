// screenreader-mcp domain -- the run_sequence tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED BY ITS STEPS -- the third gating value,
// because a plan spans several capabilities and honestly has no single one
// (entities.GatedByItsSteps).
// USES: entities.SequencePlan, and the ports behind ToolContext.Gestures(),
// .Text(), .Speech(), .Focus(), .Braille(), .Interact(), .State() and .Clock().
// LISTED BY: registry.go.
//
// WHAT IT IS FOR, and the claim it must be judged on. Spec 0036, board entry
// 11.16, out of the first external run. NOT a latency optimisation: entry 11.4
// measured the server-to-bridge hop at 0.2-0.5 ms, so the 5-10 s a step cost
// that run was the client model's own turn time and none of it is ours. What
// this removes is MODEL ROUND TRIPS.
//
// And not primarily for throughput either. One scenario in that run was
// UNTESTABLE: a command with a 1.5 s finish delay always completed before the
// agent could interrupt it, because typing it and submitting it cost two agent
// turns before a stop could be sent. As a plan -- type, submit, wait half a
// second, stop -- every hop is a fraction of a millisecond and the stop lands
// comfortably inside 1.5 s. A class of behaviour that could not be tested at all
// becomes testable; that is the claim.
//
// COMPOSITION IS OVER THE BRIDGE'S EXISTING COMMANDS, NOT OVER SIBLING TOOLS,
// and the distinction is load-bearing (spec 0036, part 3.2). Each mutating tool
// spends its OWN grace window and returns its OWN speech list; the result here
// is ONE window. So the steps are dispatched through the same ports the tools
// drive, with graceMs 0 on each, and one final speech read is taken after the
// trailing gap.
//
// THAT FINAL READ IS WHAT MAKES THE WINDOW GAPLESS. Per-step windows alone would
// leave speech that arrived BETWEEN one step's window closing and the next
// step's dispatch belonging to neither -- returned by nothing, and invisible.
// Here every step's span is the half-open range between the mark taken at its
// own dispatch and the mark taken at the next one, and the last step runs to
// where the final read ended, so the spans partition the merged window exactly.
//
// `outcome` IS THREE-VALUED, and collapsing the middle row into either
// neighbour is the failure spec 0025 named when it rejected an `until:`
// parameter: "the trigger never fired" and "a step broke" call for different
// next moves by the agent, so they are different answers.
//
// NO NEW PORT AND NO NEW ADAPTER, which is the whole reason a sequence is
// affordable server-side: no wire command, no bridge change, no add-on rebuild
// and no protocol amendment. What each underlying command does to the reader --
// including whether it is withheld from an observe-only session -- is still the
// bridge's own per-command business, unchanged by being driven from here.
package tools

import (
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// DefaultGapMs is the pause after each step, including the last, when the agent
// did not name one.
//
// The same 100 ms as DefaultGraceMs and for the same measurement (speech
// produced ~124 ms after a keystroke), but it is a different thing in a
// different place: the grace is spent INSIDE the bridge for one command, this is
// spent HERE, between commands. It is the sequence's single timing knob --
// anything longer or deliberate is a `delay` step, so there are never two
// parameters meaning "wait here".
const DefaultGapMs = DefaultGraceMs

// MaxGapMs bounds the knob, so 32 steps cannot spend an unbounded time in gaps
// alone. Anything longer is a delay step, which the budget also counts.
const MaxGapMs = 5000

// The three answers a plan can end with. Strings rather than a bool, because
// there are genuinely three situations and two of them are not failures.
const (
	// outcomeCompleted: every step ran.
	outcomeCompleted = "completed"
	// outcomeTriggerNotFound: a wait_for_speech step timed out. The
	// remaining steps did NOT run, and this is NOT an error -- the tool
	// answers found:false for exactly this reason, and a plan must not turn
	// that into a failure on its way through.
	outcomeTriggerNotFound = "trigger_not_found"
	// outcomeFailed: a step failed, or the plan ran out of budget.
	outcomeFailed = "failed"
)

// RunSequence carries several intentions in one call.
type RunSequence struct{}

var _ Tool = (*RunSequence)(nil)

func (t *RunSequence) Name() string { return "run_sequence" }

// Capability is the third gating value: this tool needs a session, but which
// capabilities it needs is a property of the plan it is handed, checked per call
// by Validate rather than declared here (spec 0036, part 2).
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

// -- what the agent sends ----------------------------------------------------

type runSequenceParams struct {
	Steps    []sequenceStepParams `json:"steps"`
	GapMs    *int                 `json:"gap_ms"`
	Announce string               `json:"announce"`
}

// sequenceStepParams is one step as JSON: exactly one field is non-nil, and the
// FIELD NAME is the discriminator.
//
// Every field is a pointer so that "present" is distinguishable from "zero" --
// `{"delay": 0}` is a mistake worth naming, and an erased int could not tell it
// from a step that named no delay at all.
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

// -- what the agent receives -------------------------------------------------

// sequenceStepResult is one step that RAN.
//
// The kind-specific fields are all omitempty and all absent on the steps they do
// not belong to, which is why the schema declares only the four every step has.
// The three sub-results are the OTHER TOOLS' OWN RESULT STRUCTS -- reused rather
// than restated, so a read step's focus reads exactly like get_focus_info's
// answer, by construction rather than by agreement.
type sequenceStepResult struct {
	Step int    `json:"step"`
	Kind string `json:"kind"`
	// The half-open span the ring stood at either side of THIS step's
	// dispatch. An empty span is a real answer: this step said nothing.
	SpeechFrom int `json:"speechFrom"`
	SpeechTo   int `json:"speechTo"`

	Gesture string               `json:"gesture,omitempty"`
	Typed   *int                 `json:"typed,omitempty"`
	Settled *bool                `json:"settled,omitempty"`
	Matched *waitForSpeechResult `json:"matched,omitempty"`
	Focus   *focusResult         `json:"focus,omitempty"`
	Braille *speechRangeResult   `json:"braille,omitempty"`
}

// runSequenceResult is the plan's answer: how it ended, what each step did, and
// the ONE window that spans all of it.
//
// The embedded observation is the same shape press_gesture and type_text
// publish, one level up (spec 0036, part 2): the merged speech list, the resume
// coordinate, the modes that cannot be heard, and the echoed announcement.
type runSequenceResult struct {
	Outcome string `json:"outcome"`
	// FailedStep counts from 1 and is ABSENT when the plan completed.
	FailedStep int `json:"failedStep,omitempty"`
	// Message is why, and only ever accompanies outcomeFailed: a trigger that
	// never fired needs no explanation beyond which step waited for it.
	Message string               `json:"message,omitempty"`
	Steps   []sequenceStepResult `json:"steps"`
	observation
}

// -- the use case ------------------------------------------------------------

func (t *RunSequence) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	// Asked first so that "nothing is connected" answers the plain error,
	// before any talk of steps and capabilities.
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
	// THE WHOLE PLAN, BEFORE THE FIRST KEYSTROKE. A plan is refused entire
	// rather than discovered broken halfway through with the reader left
	// mid-edit -- and refused BEFORE the announcement, because a capability
	// refusal is a message about the agent's own mistake and `announce` is the
	// channel to the person at the machine. Speaking it down there would
	// interrupt somebody to report a thing that never happened.
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
		// The connection going away mid-plan is not "a step failed": the
		// session is over, and the answer has to be an ERROR so the
		// dispatcher notices the loss and records it. Everything else stays
		// a result, which is what makes partial execution legible.
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

// refusal turns the entity's structured miss into the agent-facing error, which
// already names the tool, the capability and the connected reader -- and now the
// step, because "this reader has no braille" leaves an agent still hunting for
// which of its own steps asked for it.
func refusal(ctx ToolContext, err error) error {
	var missing *entities.MissingCapability
	if !errors.As(err, &missing) {
		return err
	}
	failure := ctx.missing(missing.Capability)
	failure.Step = missing.Step
	return failure
}

// gapFor reads the plan's single timing knob. Absent means the default, which is
// NOT the same as 0 -- so the parameter is a pointer and the default lives in
// one place.
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

// parsePlan turns the JSON steps into the entity.
//
// It enforces the ONE THING JSON's shape can express and the entity cannot: that
// a step names exactly one kind. Everything else -- an empty gesture id, a
// negative delay, an unknown read target, the bounds -- is the plan's own
// validation, so that the gate is testable without going through a decoder.
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

// step is one raw step as the entity's value, or the reason it is not one.
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

// readTargets maps the asked-for targets, defaulting an empty list to focus --
// which is what "orient me" means when nobody said more.
//
// Unknown strings pass through UNTRANSLATED so that the plan's validation is
// what rejects them, naming the step: dropping them here would leave a plan that
// asked for something impossible reading as a plan that asked for nothing.
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

// seconds converts a wire timeout. Zero stays zero, which every port reads as
// "the reader's own default".
func seconds(value float64) time.Duration {
	if value <= 0 {
		return 0
	}
	return time.Duration(value * float64(time.Second))
}

// sequenceRun is one plan in flight: the collaborators, the marks taken so far,
// and the per-step results.
//
// A PRIVATE HELPER of this controller, sharing its file per AGENTS.md -- not a
// role of its own. It holds no state between calls and outlives nothing: the
// controller builds one, walks it, and returns.
type sequenceRun struct {
	ctx  ToolContext
	plan entities.SequencePlan
	gap  time.Duration

	// speech is the reader's speech port, or nil when it serves none. It is
	// resolved ONCE because it is the source of every mark: without it there
	// is no speech ring for a coordinate to be in, and every span is empty.
	speech ports.SpeechReader

	// deadline is when the whole-plan budget runs out.
	deadline time.Time

	// start is the mark taken before step 1, and the left edge of the merged
	// window.
	start int
	// at is the most recent mark, which is where the next step's span begins.
	at int
	// braille is where the braille ring stood at the last read, so a second
	// read step reports what arrived since the first rather than repeating it.
	braille int

	steps []sequenceStepResult
}

// newSequenceRun takes the opening marks: the speech index the plan starts from,
// and -- only when the plan actually reads braille -- where that ring stands.
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

// mark is where the speech ring stands now.
//
// A read of its own rather than the coordinate a mutating command reports,
// because it has to be the same coordinate for all six kinds: a delay and a
// settle report nothing, and a plan whose spans came from two different clocks
// would not partition its own window. Failure is not fatal -- the mark simply
// does not move, which reads as a silent step, and the merged read is where a
// real speech problem surfaces.
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

// markBraille notes where the braille ring stands, but only for a plan that
// actually reads it.
//
// There is no next-index probe for braille as there is for speech -- get_braille
// is the only braille fetch -- so the end is learned by reading and keeping the
// coordinate. The entries are discarded: they are what was on the display BEFORE
// this plan, which the plan did not cause and nobody asked for.
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

// walk runs the plan and reports how it ended.
//
// ABORT ON THE FIRST FAILURE. Nothing is rolled back, because keystrokes cannot
// be un-pressed: what the per-step results buy is that the agent can see exactly
// how far it got, which is what makes the wreckage legible.
//
// The error return is reserved for the connection going away -- see Execute.
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
		// The gap runs after EVERY step, including a failed one and the
		// last: it is what gives that step's speech time to reach the
		// merged read, which is the whole reason the window is gapless.
		r.ctx.Clock.Sleep(r.gap)
		r.at = r.mark()
		r.close(number)

		switch {
		case failure != nil && errors.Is(failure, ports.ErrConnectionLost):
			return "", 0, "", failure
		case failure != nil:
			return outcomeFailed, number, failure.Error(), nil
		case !continued:
			// A trigger that never fired. NOT an error, and not to be
			// collapsed into one: the plan stopped, and the agent's next
			// move is a different one from a step having broken.
			return outcomeTriggerNotFound, number, "", nil
		}
	}
	return outcomeCompleted, 0, "", nil
}

// close writes the just-finished step's right edge, which is the mark taken
// after its gap -- so the spans of consecutive steps meet exactly and no
// utterance belongs to neither.
func (r *sequenceRun) close(number int) {
	r.steps[number-1].SpeechTo = r.at
}

// dispatch runs one step. It reports whether the plan CONTINUES -- only a
// wait_for_speech step can answer no -- and the failure that stopped it.
//
// Every mutating call goes out with graceMs 0 and no announcement: the pause
// belongs to the plan (one knob, not two), and the announcement was spoken once
// before step 1 rather than repeated per step.
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
		// The reader counts what it received; this server does not recount
		// it, and the text itself is never echoed back.
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
		// Matched from the PLAN's start, not from this step's own mark: the
		// trigger can legitimately land in the fraction of a millisecond
		// between the previous step's dispatch and this one's, and a wait
		// that could miss it that way would abort a plan that was working.
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
	// Unreachable: the plan's own validation refused any other kind before
	// anything was dispatched.
	return true, fmt.Errorf("%q is not a step kind", step.Kind)
}

// read orients. Each target gates independently, which is why they are asked for
// one at a time rather than as a bundle.
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
			// So a second read step reports what arrived since this one
			// rather than repeating it.
			r.braille = captured.ToIndex
		}
	}
	return nil
}

// observe takes the one read that makes the window gapless, and the mode
// snapshot that rides on every mutating result.
//
// The last step's right edge is corrected to the read's own end: speech that
// arrived while the read was in flight belongs to the last step, not to nobody.
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
	// Sampled once, at the end, so it reports the modes the plan LEFT the
	// reader in rather than whichever step happened to be the last mutating
	// one. Never fatal: absent state is a reader that serves none, which is
	// the same answer this shape gives everywhere else.
	if inspector, err := r.ctx.State(); err == nil {
		if state, err := inspector.State(); err == nil {
			seen.State = &state
		}
	}
	return observed(seen, announced), failure
}
