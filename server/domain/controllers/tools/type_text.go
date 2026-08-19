// screenreader-mcp domain -- the type_text tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `typing`.
// USES: ports.TextTyper, through ToolContext.Text().
// LISTED BY: registry.go.
//
// text IS OPAQUE, exactly as a gesture id is (spec 0005, principle 3): it is
// content, not a command, and this server routes it without interpreting it.
// Distinct from press_gesture, not a convenience wrapper over it -- typing a
// URL one character at a time through press_gesture resolves each character
// through the CURRENT keyboard layout and silently drops anything it cannot
// map; type_text is layout-independent Unicode injection (spec 0019).
package tools

import (
	"encoding/json"
	"errors"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// TypeText inserts literal text at the focused control.
type TypeText struct{}

var _ Tool = (*TypeText)(nil)

func (t *TypeText) Name() string { return "type_text" }

func (t *TypeText) Capability() entities.Capability { return entities.CapabilityTyping }

func (t *TypeText) Description() string {
	return "Type literal text into whatever currently holds focus -- a URL, a search " +
		"phrase, a form field -- and receive what the reader said. Unlike press_gesture, " +
		"text is layout-independent Unicode content, not a sequence of key commands: it " +
		"lands correctly regardless of the active keyboard layout, including " +
		"punctuation and accented characters. Focus the target control first (e.g. " +
		"press_gesture [\"control+l\"] for a browser's address bar), then call this. It " +
		"does NOT interpret control characters, newlines or Enter and does not submit " +
		"anything -- compose that with press_gesture afterwards. IMPORTANT -- KNOW " +
		"WHERE FOCUS IS FIRST: text goes wherever focus happens to be, so if the window " +
		"you believe is open is not, this lands in a document or a chat you did not " +
		"mean to touch. A field that is open is also not necessarily empty; some " +
		"windows keep their contents between openings and append to them. `grace_ms` " +
		"defaults to 0 here, unlike press_gesture: with \"speak typed characters\" on, " +
		"typing emits one utterance per character and none is worth waiting for -- raise " +
		"it when you expect the field itself to announce something. An empty `speech` " +
		"means nothing had arrived by that instant, never that nothing happened. " +
		"`state` reports the modes you cannot hear. Use `announce` to tell the human " +
		"what you are about to type, in your own words. The `typed` count is the length " +
		"of what was SENT, counted here -- it says nothing about what arrived anywhere, " +
		"and the text itself is never echoed back, because this is exactly how a " +
		"secret would be entered."
}

func (t *TypeText) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"text": {
			"type": "string",
			"description": "The literal text to insert at the focused control, unchanged. Not interpreted: newlines and control characters are not acted on, and nothing is submitted."
		},
		"grace_ms": {
			"type": "integer",
			"minimum": 0,
			"description": "How long to wait after the text goes in for the speech it caused, in milliseconds. Omit for the default (0): typing usually announces one character at a time, which is noise. Raise it when the field itself should say something."
		},
		"announce": {
			"type": "string",
			"description": "Spoken aloud to the human at the reader before the text is injected -- audible even in a silent session. Describe what you are typing rather than repeating it, if it is sensitive."
		}
	},
	"required": ["text"],
	"additionalProperties": false
}`)
}

func (t *TypeText) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"typed": {
			"type": "integer",
			"description": "The LENGTH of what was sent, counted by the reader that injected it. The text itself is never echoed back, because this is exactly how a secret would be entered."
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
	"required": ["typed", "speech", "speechFrom", "speechTo"]
}`)
}

type typeTextParams struct {
	Text     string `json:"text"`
	GraceMs  *int   `json:"grace_ms"`
	Announce string `json:"announce"`
}

type typeTextResult struct {
	// Typed is the LENGTH of what was sent, never the text: type_text is exactly
	// how a secret would be entered, and echoing it back would put the secret in
	// the tool result (spec 0019's transcript decision applies here too).
	Typed int `json:"typed"`
	observation
}

func (t *TypeText) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	typer, err := ctx.Text()
	if err != nil {
		return nil, err
	}
	var request typeTextParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	// Erased params cannot tell "text" absent from "text" sent as "": both
	// decode to the zero value, so both are treated as the same missing
	// argument. Unlike announce, whitespace is NOT rejected here -- a space or
	// a tab is legitimate literal content to insert, not noise.
	if request.Text == "" {
		return nil, errors.New("text is required")
	}
	grace := DefaultTypeGraceMs
	if request.GraceMs != nil {
		grace = *request.GraceMs
		if grace < 0 {
			return nil, errors.New("grace_ms cannot be negative")
		}
	}

	outcome, err := typer.TypeText(request.Text, grace, request.Announce)
	if err != nil {
		return nil, err
	}
	return typeTextResult{
		// The reader counts what it received; this server does not recount it.
		// One authority for the number, and it is the side that actually
		// injected the characters.
		Typed:       outcome.Typed,
		observation: observed(outcome.Observation),
	}, nil
}
