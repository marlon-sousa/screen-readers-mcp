// screenreader-mcp domain -- the press_gesture tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `gestures`.
// USES: ports.GestureSender, through ToolContext.Gestures().
// LISTED BY: registry.go.
//
// GESTURE IDS ARE OPAQUE (spec 0005, principle 3). `NVDA+f7` means something
// to NVDA and to the agent, and nothing to this server, which routes the string
// without interpreting it. That is what keeps the chassis reader-agnostic: a
// JAWS gesture vocabulary needs no code change here, and this file contains no
// reader's syntax except as an example in the text an agent reads. The example
// is deliberately the reader's user-facing command notation (what its manual
// prints), not an internal identifier -- the vocabulary any agent already knows.
package tools

import (
	"encoding/json"
	"errors"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// PressGesture presses reader gestures in order.
type PressGesture struct{}

var _ Tool = (*PressGesture)(nil)

func (t *PressGesture) Name() string { return "press_gesture" }

func (t *PressGesture) Capability() entities.Capability { return entities.CapabilityGestures }

func (t *PressGesture) Description() string {
	return "Press one or more screen reader gestures, in order, and receive what the " +
		"reader SAID in response. Gesture ids are the reader's own user-facing " +
		"command notation -- the key combo as its documentation writes it -- and pass " +
		"through untouched: for NVDA, the User Guide form like \"NVDA+f7\", " +
		"\"downArrow\" or \"control+home\", not an internal identifier. Read " +
		"screenreader://info to learn which reader you are driving, then use that " +
		"reader's vocabulary. Gestures land wherever the system focus currently is. " +
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
		"before anything is pressed and costs no extra call. Read " +
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
			"description": "The gesture ids to press, in order. The reader's user-facing command notation, passed through unchanged (NVDA example: [\"NVDA+control+f7\"])."
		},
		"grace_ms": {
			"type": "integer",
			"minimum": 0,
			"description": "How long to wait after EACH key for the speech it caused, in milliseconds. Omit for the default (100), which is where the common case already is. Raise it on a slow machine or a heavy page; 0 returns immediately and reports only what was already there."
		},
		"announce": {
			"type": "string",
			"description": "Spoken aloud to the human at the reader before anything is pressed -- audible even in a silent session. Say what you are about to do, in their language. Costs no extra call."
		}
	},
	"required": ["gestures"],
	"additionalProperties": false
}`)
}

type pressGestureParams struct {
	Gestures []string `json:"gestures"`
	GraceMs  *int     `json:"grace_ms"`
	Announce string   `json:"announce"`
}

type gesturePress struct {
	Gesture string `json:"gesture"`
	// The half-open span the ring stood at either side of THIS key's dispatch.
	// An empty span is a real answer: this key said nothing.
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
	// Absent means "use the reader's default", which is NOT the same as 0. An
	// erased int cannot tell the two apart, so the parameter is a pointer and
	// the default lives in one place -- the contract -- rather than being
	// restated here where it could drift.
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
	// The ids are opaque to this server, so it echoes them rather than
	// interpreting them -- but each now carries the window it was dispatched in,
	// which is what makes a silent key visible instead of inferred.
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
		observation: observed(outcome.Observation),
	}, nil
}
