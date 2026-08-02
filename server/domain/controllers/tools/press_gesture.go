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
	return "Press one or more screen reader gestures, in order. Gesture ids are the " +
		"reader's own user-facing command notation -- the key combo as its " +
		"documentation writes it -- and pass through untouched: for NVDA, the User " +
		"Guide form like \"NVDA+f7\", \"downArrow\" or \"control+home\", not an internal " +
		"identifier. Read screenreader://info to learn which reader you are driving, " +
		"then use that reader's vocabulary. Gestures land wherever the system focus " +
		"currently is. IMPORTANT -- a successful result reports DELIVERY, NOT " +
		"CONSEQUENCE: it means the reader accepted the input and will act on it " +
		"afterwards, on its own thread. When this returns, the dialog has not opened " +
		"and focus has not moved yet. To confirm what actually happened, call " +
		"wait_for_speech_to_finish and then get_speech -- a window that opens " +
		"announces its title. Do not re-press because it \"seemed\" not to work, and " +
		"do not assume focus moved: most reader commands never move it. Read " +
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
		}
	},
	"required": ["gestures"],
	"additionalProperties": false
}`)
}

type pressGestureParams struct {
	Gestures []string `json:"gestures"`
}

type pressGestureResult struct {
	Pressed []string `json:"pressed"`
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

	if err := gestures.PressGestures(request.Gestures); err != nil {
		return nil, err
	}
	// Echo what was pressed: the ids are opaque to this server, so the only
	// useful confirmation is that these exact strings reached the reader.
	return pressGestureResult{Pressed: request.Gestures}, nil
}
