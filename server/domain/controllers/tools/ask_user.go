// screenreader-mcp domain -- the ask_user tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `interact`.
// USES: ports.Interact, through ToolContext.Interact().
// LISTED BY: registry.go.
//
// Presents a prompt to the human and returns a ticket immediately. The agent
// then polls with wait_for_user_reply. Speech suppression is suspended for the
// duration of the interaction window; the human hears normally.
package tools

import (
	"encoding/json"
	"errors"
	"strings"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// AskUser presents a prompt to the human operating the reader.
type AskUser struct{}

var _ Tool = (*AskUser)(nil)

func (t *AskUser) Name() string { return "ask_user" }

func (t *AskUser) Capability() entities.Capability { return entities.CapabilityInteract }

func (t *AskUser) Description() string {
	return "Ask the human a question or tell them to do something, then return " +
		"immediately with a ticket. The human hears normally while the window is " +
		"open (speech suppression is suspended). After this call, poll with " +
		"wait_for_user_reply until the human acknowledges or the window expires. " +
		"Only ONE prompt may be outstanding at a time."
}

func (t *AskUser) InputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"prompt": {
				"type": "string",
				"minLength": 1,
				"description": "What to say to the human. Keep it to a sentence or two -- it is spoken aloud. Say what you need them to do and that they should press NVDA+control+shift+A when done."
			}
		},
		"required": ["prompt"],
		"additionalProperties": false
	}`)
}

func (t *AskUser) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"ticket": {
			"type": "string",
			"description": "The outstanding prompt's ticket. Pass it to wait_for_user_reply, and keep polling until answered is true or the bridge says the window expired. Only one prompt may be outstanding at a time."
		}
	},
	"required": ["ticket"]
}`)
}

type askUserParams struct {
	Prompt string `json:"prompt"`
}

type askUserResult struct {
	Ticket string `json:"ticket"`
}

func (t *AskUser) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	interact, err := ctx.Interact()
	if err != nil {
		return nil, err
	}
	var request askUserParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	if strings.TrimSpace(request.Prompt) == "" {
		return nil, errors.New("prompt is required, and must not be empty or whitespace")
	}

	ticket, err := interact.AskUser(request.Prompt)
	if err != nil {
		return nil, err
	}
	return askUserResult{Ticket: ticket}, nil
}
