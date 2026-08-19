// screenreader-mcp domain -- the get_focus_info tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `focus`.
// USES: ports.FocusInspector, through ToolContext.Focus().
// LISTED BY: registry.go.
//
// Role and state strings are the READER's vocabulary and pass through opaquely.
// The agent knows what NVDA means by "editableText" and what JAWS means by its
// own spelling; this server does not, and must not learn.
package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// GetFocusInfo reads the focus object.
type GetFocusInfo struct{}

var _ Tool = (*GetFocusInfo)(nil)

func (t *GetFocusInfo) Name() string { return "get_focus_info" }

func (t *GetFocusInfo) Capability() entities.Capability { return entities.CapabilityFocus }

func (t *GetFocusInfo) Description() string {
	return "Describe the object the screen reader currently has focus on: its name, " +
		"role, states, value and owning application. Role and state strings are the " +
		"READER's own vocabulary, not a normalised one -- read screenreader://info to " +
		"learn which reader you are driving. This is INTROSPECTION, for two jobs: " +
		"asserting in a test what a control reports about itself, and answering when " +
		"the reader said nothing you could listen to. It is NOT how you orient " +
		"yourself -- a user finds out where they are by pressing the reader's own " +
		"report-focus command and listening, and orienting by reading the object " +
		"model instead tests the platform accessibility API rather than the reader. " +
		"See screenreader://guidance. Takes no parameters."
}

func (t *GetFocusInfo) InputSchema() json.RawMessage {
	return json.RawMessage(`{"type":"object","properties":{},"additionalProperties":false}`)
}

func (t *GetFocusInfo) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"name": {"type": "string", "description": "The object's accessible name. AN EMPTY NAME IS A FINDING, not a blank: it is a control the person at the machine cannot identify."},
		"role": {"type": "string", "description": "Its role, in the READER's own vocabulary -- not a normalised one. Read screenreader://info to learn which reader you are driving."},
		"states": {"type": "array", "items": {"type": "string"}, "description": "Its states, in the reader's vocabulary. Empty list, never null."},
		"value": {"type": ["string", "null"], "description": "Its value, or null. Null and the empty string are DIFFERENT answers -- \"this object has no value\" against \"its value is empty\" -- so both are reported as they come."},
		"appModule": {"type": ["string", "null"], "description": "The reader's own module handling the owning application, or null where the reader names none."}
	},
	"required": ["name", "role", "states", "value", "appModule"]
}`)
}

// focusResult keeps Value and AppModule as pointers, because the wire
// distinguishes "this object has no value" from "its value is the empty string",
// and collapsing the two would throw away a real answer.
type focusResult struct {
	Name      string   `json:"name"`
	Role      string   `json:"role"`
	States    []string `json:"states"`
	Value     *string  `json:"value"`
	AppModule *string  `json:"appModule"`
}

func (t *GetFocusInfo) Execute(ctx ToolContext, _ json.RawMessage) (any, error) {
	focus, err := ctx.Focus()
	if err != nil {
		return nil, err
	}

	info, err := focus.FocusInfo()
	if err != nil {
		return nil, err
	}
	states := info.States
	if states == nil {
		// An empty list rather than JSON null: "this object has no states" is
		// an answer an agent can iterate over without a special case.
		states = []string{}
	}
	return focusResult{
		Name:      info.Name,
		Role:      info.Role,
		States:    states,
		Value:     info.Value,
		AppModule: info.AppModule,
	}, nil
}
