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
	"unicode/utf8"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// TypeText inserts literal text at the focused control.
type TypeText struct{}

var _ Tool = (*TypeText)(nil)

func (t *TypeText) Name() string { return "type_text" }

func (t *TypeText) Capability() entities.Capability { return entities.CapabilityTyping }

func (t *TypeText) Description() string {
	return "Type literal text into whatever currently holds focus -- a URL, a search " +
		"phrase, a form field. Unlike press_gesture, text is layout-independent Unicode " +
		"content, not a sequence of key commands: it lands correctly regardless of the " +
		"active keyboard layout, including punctuation and accented characters. Focus " +
		"the target control first (e.g. press_gesture [\"control+l\"] for a browser's " +
		"address bar), then call this. It does NOT interpret control characters, " +
		"newlines or Enter and does not submit anything -- compose that with " +
		"press_gesture afterwards."
}

func (t *TypeText) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"text": {
			"type": "string",
			"description": "The literal text to insert at the focused control, unchanged. Not interpreted: newlines and control characters are not acted on, and nothing is submitted."
		}
	},
	"required": ["text"],
	"additionalProperties": false
}`)
}

type typeTextParams struct {
	Text string `json:"text"`
}

type typeTextResult struct {
	Typed int `json:"typed"`
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

	if err := typer.TypeText(request.Text); err != nil {
		return nil, err
	}
	// The length, not the text: type_text is exactly how a secret would be
	// entered, and echoing it back would put the secret in the tool result
	// (spec 0019's transcript decision applies here too). Rune count, not byte
	// count, so a multi-byte character (e.g. "café") reports as one typed
	// character rather than however many UTF-8 bytes it took.
	return typeTextResult{Typed: utf8.RuneCountInString(request.Text)}, nil
}
