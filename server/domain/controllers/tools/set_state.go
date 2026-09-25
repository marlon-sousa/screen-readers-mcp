// screenreader-mcp domain -- the set_state tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, gated on state, the same capability as get_state.
// USES: ports.StateWriter, through ToolContext.StateWriter().
// LISTED BY: registry.go.
// The compare-and-set happens inside the reader, so there is no window between the read and the write.
package tools

import (
	"encoding/json"
	"errors"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type SetState struct{}

var _ Tool = (*SetState)(nil)

func (t *SetState) Name() string { return "set_state" }

func (t *SetState) Capability() entities.Capability { return entities.CapabilityState }

func (t *SetState) Description() string {
	return "Put the screen reader INTO a mode, rather than toggling it and hoping. " +
		"Browse mode and focus mode are reached with the same key on most readers, so " +
		"pressing it is a coin flip whenever the page may have changed the mode itself " +
		"-- and a wrong guess sends every keystroke after it somewhere else. This says " +
		"where you want to be: already there does nothing at all (no sound, no " +
		"announcement), and the result tells you the state afterwards plus whether this " +
		"call moved anything. Use it to ARRIVE at a mode; press the gesture when the " +
		"toggle itself is what you are testing."
}

func (t *SetState) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"browse_mode": {
			"type": "string",
			"enum": ["browse", "focus"],
			"description": "Where to be: \"browse\" reads the document as flat text you arrow through, \"focus\" sends keys to the control. \"none\" is reportable by get_state and NOT settable -- it means the focus has no browsable document at all, which cannot be created by asking for it."
		}
	},
	"additionalProperties": false
}`)
}

func (t *SetState) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"state": {
			"type": "object",
			"description": "The reader's mode state AFTER this call -- the same shape get_state answers with, so you never need a second call to confirm you arrived.",
			"properties": {
				"browseMode": {"type": "string", "enum": ["browse", "focus", "none"]},
				"speechMode": {"type": "string"},
				"sleepMode": {"type": "boolean"},
				"inputHelp": {"type": "boolean"}
			},
			"required": ["browseMode", "speechMode", "sleepMode", "inputHelp"]
		},
		"changed": {
			"type": "array",
			"items": {"type": "string"},
			"description": "The fields this call actually moved. EMPTY means the reader was already in the state you asked for -- which is a success, and a different fact from a failed write (that comes back as an error naming what stopped it)."
		}
	},
	"required": ["state", "changed"]
}`)
}

type setStateParams struct {
	BrowseMode string `json:"browse_mode"`
}

type setStateResult struct {
	State   stateResult `json:"state"`
	Changed []string    `json:"changed"`
}

func (t *SetState) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	writer, err := ctx.StateWriter()
	if err != nil {
		return nil, err
	}
	var request setStateParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	if request.BrowseMode == "" {
		// An empty call would come back looking exactly like already being there.
		return nil, errors.New("name at least one mode to set; browse_mode is the only one this reader accepts today")
	}

	mode := request.BrowseMode
	result, err := writer.SetState(ports.StateWrite{BrowseMode: &mode})
	if err != nil {
		return nil, err
	}
	// Changed is never nil on the wire.
	changed := result.Changed
	if changed == nil {
		changed = []string{}
	}
	return setStateResult{
		State: stateResult{
			BrowseMode: result.State.BrowseMode,
			SpeechMode: result.State.SpeechMode,
			SleepMode:  result.State.SleepMode,
			InputHelp:  result.State.InputHelp,
		},
		Changed: changed,
	}, nil
}
