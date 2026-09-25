// screenreader-mcp domain -- the press_gesture tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, gated on gestures.
// USES: ports.GestureSender, through ToolContext.Gestures().
// LISTED BY: registry.go.
package tools

import (
	"encoding/json"
	"errors"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

type PressGesture struct{}

var _ Tool = (*PressGesture)(nil)

func (t *PressGesture) Name() string { return "press_gesture" }

func (t *PressGesture) Capability() entities.Capability { return entities.CapabilityGestures }

func (t *PressGesture) Description() string {
	return "Press one or more screen reader gestures, in order, and receive what the " +
		"reader SAID in response. Gesture ids are the reader's own user-facing " +
		"command notation -- a key combination on one reader, a named command on " +
		"another, as that reader's own guidance spells it, not an internal " +
		"identifier -- and pass through untouched. WHERE TO GET THEM: " +
		"screenreader://reader-guidance is the connected reader's own list, read out " +
		"of the running reader rather than transcribed, so it is right even where the " +
		"user has rebound something; connect_reader returns it in full. Do not copy a " +
		"combination from anywhere else, including from memory of a different reader. " +
		"Gestures land wherever the system focus currently is. " +
		"THIS IS ONE CALL, NOT THREE: after each key the reader waits `grace_ms` (100 " +
		"by default) and returns the speech that arrived, so you do NOT need to " +
		"follow this with wait_for_speech_to_finish and get_speech. WHAT AN EMPTY " +
		"`speech` MEANS: nothing had arrived by that instant -- NOT that nothing " +
		"happened. Slow effects (a window opening, a page loading) legitimately take " +
		"longer than the grace: read again from `speech_to`, or wait_for_speech for a " +
		"phrase you expect. Never re-press a key because the first result looked " +
		"quiet; that presses it twice. Each entry in `pressed` carries its own " +
		"`speech_from`/`speech_to`, so in a batch you can see WHICH key spoke and " +
		"which said nothing -- an empty span is a real answer, and most reader " +
		"commands never move focus. `state` reports the modes you cannot hear " +
		"(browse/focus, speech mode, sleep, input help), sampled when the last " +
		"window closed; it is deliberately not focus information. Use `announce` to " +
		"tell the human at the keyboard what you are about to do -- it is spoken " +
		"before anything is pressed and costs no extra call, and comes back to you " +
		"as `announced`, which confirms it was SAID and never that it was heard. Read " +
		"screenreader://guidance for the full loop."
}

func (t *PressGesture) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"gestures": {
			"type": "array",
			"items": {"type": "string"},
			"minItems": 1,
			"description": "The gesture ids to press, in order. The reader's user-facing command notation, passed through unchanged. Take the spelling from screenreader://reader-guidance, which connect_reader returns in full -- it is generated from the running reader, so it matches what is actually bound."
		},
		"grace_ms": {
			"type": "integer",
			"minimum": 0,
			"description": "How long to wait after EACH key for the speech it caused, in milliseconds. Omit for the default (100), which is where the common case already is. Raise it on a slow machine or a heavy page; 0 returns immediately and reports only what was already there."
		},
		"announce": {
			"type": "string",
			"description": "Spoken aloud to the human at the reader before anything is pressed -- audible even in a silent session, which is what it is FOR. Use it when they would otherwise not know: a SILENT session with somebody there, where this is the only thing they hear. In a LIVE session they can already hear the reader answer every key, so narrating each one talks over the speech they are following -- save it for what the reader will not tell them, such as that you are about to go quiet. Never narrate to an unattended machine. See silenceCap on connect_reader for whether anyone is there."
		}
	},
	"required": ["gestures"],
	"additionalProperties": false
}`)
}

func (t *PressGesture) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"pressed": {
			"type": "array",
			"description": "One entry per gesture, in the order they were pressed. Each carries its OWN window, so in a batch you can see which key spoke and which said nothing.",
			"items": {
				"type": "object",
				"properties": {
					"gesture": {"type": "string", "description": "The gesture id, echoed unchanged -- this server never interprets it."},
					"speechFrom": {"type": "integer", "description": "The speech index the ring stood at before this key was dispatched."},
					"speechTo": {"type": "integer", "description": "And after its grace window closed. An empty span is a real answer: this key said nothing, and most reader commands never move focus."}
				},
				"required": ["gesture", "speechFrom", "speechTo"]
			}
		},
		"speech": {
			"type": "array",
			"description": "What the reader said inside this call's grace window, oldest first. Empty means nothing had arrived by that instant -- NOT that nothing happened. Never null.",
			"items": {
				"type": "object",
				"properties": {
					"text": {"type": "string", "description": "What the reader spoke."},
					"index": {"type": "integer", "description": "This utterance's place in the speech ring."},
					"logPosition": {"type": "integer", "description": "Where it sits on the reader's log journal; hand it to get_log as sincePosition."},
					"emittedAt": {"type": "string", "description": "When the reader emitted it. Absent if the reader supplied none."}
				},
				"required": ["text", "index", "logPosition"]
			}
		},
		"speechFrom": {"type": "integer", "description": "The first speech index this call covered."},
		"speechTo": {"type": "integer", "description": "One past the last: the window is [speechFrom, speechTo), so speechTo is exactly what to read from next. Slow effects legitimately arrive after it -- read again from here rather than pressing anything twice."},
		"announced": {"type": "string", "description": "The announcement that was spoken to the human before the first key went out, echoed back. ABSENT when you asked for none. It confirms the announcement was MADE, never that it was HEARD: speech is emitted around five seconds ahead of audio, so if you narrate and act at once you are acting ahead of your own narration."},
		"state": {
			"type": "object",
			"description": "The modes you cannot hear, sampled when the last grace window closed. ABSENT when the reader serves no state capability: absent and \"all four fields zero\" are different answers. Deliberately not focus information.",
			"properties": {
				"browseMode": {"type": "string", "enum": ["browse", "focus", "none"], "description": "\"none\" when there is no browsable document -- the absence IS one of the three answers."},
				"speechMode": {"type": "string", "description": "The reader's speech mode, in its own vocabulary."},
				"sleepMode": {"type": "boolean", "description": "Whether the reader is asleep for the focused application."},
				"inputHelp": {"type": "boolean", "description": "Whether input help is on -- if it is, keys are described rather than acted on."}
			},
			"required": ["browseMode", "speechMode", "sleepMode", "inputHelp"]
		}
	},
	"required": ["pressed", "speech", "speechFrom", "speechTo"]
}`)
}

type pressGestureParams struct {
	Gestures []string `json:"gestures"`
	GraceMs  *int     `json:"grace_ms"`
	Announce string   `json:"announce"`
}

type gesturePress struct {
	Gesture string `json:"gesture"`
	// [SpeechFrom, SpeechTo) is half-open; an empty span means this key said nothing.
	SpeechFrom int `json:"speechFrom"`
	SpeechTo   int `json:"speechTo"`
}

type pressGestureResult struct {
	Pressed []gesturePress `json:"pressed"`
	observation
}

func (t *PressGesture) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	gestures, err := ctx.Gestures()
	if err != nil {
		return nil, err
	}
	var request pressGestureParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	if len(request.Gestures) == 0 {
		return nil, errors.New("gestures is required, and must name at least one gesture")
	}
	// Validated before the keys are dispatched, so an unspeakable narration is not discovered after the machine moved.
	announced, err := announcement(request.Announce)
	if err != nil {
		return nil, err
	}
	// Absent means the reader's default, which is not the same as 0.
	grace := DefaultGraceMs
	if request.GraceMs != nil {
		grace = *request.GraceMs
		if grace < 0 {
			return nil, errors.New("grace_ms cannot be negative")
		}
	}

	outcome, err := gestures.PressGestures(request.Gestures, grace, request.Announce)
	if err != nil {
		return nil, err
	}
	pressed := make([]gesturePress, 0, len(outcome.Pressed))
	for _, p := range outcome.Pressed {
		pressed = append(pressed, gesturePress{
			Gesture:    p.Gesture,
			SpeechFrom: p.SpeechFrom,
			SpeechTo:   p.SpeechTo,
		})
	}
	return pressGestureResult{
		Pressed:     pressed,
		observation: observed(outcome.Observation, announced),
	}, nil
}
