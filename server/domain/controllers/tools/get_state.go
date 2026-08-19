// screenreader-mcp domain -- the get_state tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `state`.
// USES: ports.StateInspector, through ToolContext.State().
// LISTED BY: registry.go.
//
// WHY THIS CAPABILITY EXISTS, from the bridge's hard-won gotcha: a reader
// answers some actions with an earcon rather than words -- NVDA+space toggling
// browse and focus mode is the standing example -- so a speech assertion has
// nothing to match. Two state snapshots either side of a gesture assert the
// toggle instead. That is the use case this tool's description has to teach.
package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// GetState reads queryable reader state.
type GetState struct{}

var _ Tool = (*GetState)(nil)

func (t *GetState) Name() string { return "get_state" }

func (t *GetState) Capability() entities.Capability { return entities.CapabilityState }

func (t *GetState) Description() string {
	return "Read the screen reader's own mode state: browse/focus mode, speech mode, " +
		"sleep mode and input help. Some reader actions are signalled by a BEEP " +
		"rather than by words -- toggling browse mode, for one -- so there is no " +
		"speech to assert on. Take a snapshot, press the gesture, take another, and " +
		"compare. Values are the reader's own vocabulary. Takes no parameters."
}

func (t *GetState) InputSchema() json.RawMessage {
	return json.RawMessage(`{"type":"object","properties":{},"additionalProperties":false}`)
}

func (t *GetState) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"browseMode": {
			"type": "string",
			"enum": ["browse", "focus", "none"],
			"description": "\"none\" when there is no browsable document, so the absence IS one of the three answers and never a missing field."
		},
		"speechMode": {"type": "string", "description": "The reader's speech mode, in its own vocabulary."},
		"sleepMode": {"type": "boolean", "description": "Whether the reader is asleep for the focused application -- when it is, it deliberately says nothing, which is not a fault to chase."},
		"inputHelp": {"type": "boolean", "description": "Whether input help is on. If it is, keys are DESCRIBED rather than acted on, which is a common explanation for a gesture appearing to do nothing."}
	},
	"required": ["browseMode", "speechMode", "sleepMode", "inputHelp"]
}`)
}

// stateResult reports BrowseMode as one of "browse" / "focus" / "none" (spec
// 0015). A reader with no browsable document says "none" rather than null: the
// absence IS one of the three answers, so an agent never has to special-case a
// missing field, and `if not state.browseMode` cannot silently conflate "focus
// mode" with "no such concept".
type stateResult struct {
	BrowseMode string `json:"browseMode"`
	SpeechMode string `json:"speechMode"`
	SleepMode  bool   `json:"sleepMode"`
	InputHelp  bool   `json:"inputHelp"`
}

func (t *GetState) Execute(ctx ToolContext, _ json.RawMessage) (any, error) {
	inspector, err := ctx.State()
	if err != nil {
		return nil, err
	}

	state, err := inspector.State()
	if err != nil {
		return nil, err
	}
	return stateResult{
		BrowseMode: state.BrowseMode,
		SpeechMode: state.SpeechMode,
		SleepMode:  state.SleepMode,
		InputHelp:  state.InputHelp,
	}, nil
}
