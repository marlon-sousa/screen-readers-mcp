// screenreader-mcp domain -- the announce tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller for one tool, gated on `interact`.
// LISTED BY: registry.go.
package tools

import (
	"encoding/json"
	"errors"
	"strings"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

type Announce struct{}

var _ Tool = (*Announce)(nil)

func (t *Announce) Name() string { return "announce" }

func (t *Announce) Capability() entities.Capability { return entities.CapabilityInteract }

func (t *Announce) Description() string {
	return "Speak a short message OUT LOUD to the human sitting at the screen reader. " +
		"This reaches a person, not a log: it interrupts them, so use it when you " +
		"genuinely need their attention and not to narrate your progress. It is " +
		"audible even in silent capture mode, where the reader's own speech is " +
		"suppressed -- that is what it is for. IMPORTANT: this tool only TELLS. In " +
		"silent mode the human hears this and nothing else: they cannot read the " +
		"screen or reach your chat window, and announce gives them no way to reply. " +
		"So announce a statement (\"I am partway through the form; carry on watching\") " +
		"and use ask_user for anything you need an answer or an action for -- it hands " +
		"speech back to them, tells them which key answers you, and reports what they " +
		"did. If you truly cannot proceed at all, say so and tell them to use their " +
		"reader's panic gesture, which stops the bridge and returns their machine; " +
		"screenreader://reader-guidance names it, and connect_reader hands you that " +
		"document in full."
}

func (t *Announce) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"text": {
			"type": "string",
			"minLength": 1,
			"description": "What to say. Keep it to a sentence or two -- it is spoken aloud and interrupts the person, and a long message is hard to hold in memory by ear. Say what you need and what you want them to do about it."
		}
	},
	"required": ["text"],
	"additionalProperties": false
}`)
}

func (t *Announce) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"announced": {
			"type": "string",
			"description": "The text that reached the reader, echoed back. The reader returns only an acknowledgement, so this exact text having arrived is the useful confirmation -- it does not tell you the human understood it, or that they are still there."
		}
	},
	"required": ["announced"]
}`)
}

type announceParams struct {
	Text string `json:"text"`
}

type announceResult struct {
	Announced string `json:"announced"`
}

func (t *Announce) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	interact, err := ctx.Interact()
	if err != nil {
		return nil, err
	}
	var request announceParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	// An empty announcement is two cue beeps then silence, which a tester reads as a malfunction.
	if strings.TrimSpace(request.Text) == "" {
		return nil, errors.New("text is required, and must not be empty or whitespace")
	}

	if err := interact.Announce(request.Text); err != nil {
		return nil, err
	}
	// The reader returns only an acknowledgement, so echoing the text is the useful confirmation.
	return announceResult{Announced: request.Text}, nil
}
