// screenreader-mcp domain -- the wait_for_user_reply tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `interact`.
// USES: ports.Interact, through ToolContext.Interact().
// LISTED BY: registry.go.
//
// Polls for the human's answer to an ask_user prompt. Returns answered=false
// on a poll miss (the window is still open). The agent re-polls until
// answered=true or the bridge returns an error (expired/cancelled ticket).
package tools

import (
	"encoding/json"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// WaitForUserReply polls for the human's answer.
type WaitForUserReply struct{}

var _ Tool = (*WaitForUserReply)(nil)

func (t *WaitForUserReply) Name() string { return "wait_for_user_reply" }

func (t *WaitForUserReply) Capability() entities.Capability { return entities.CapabilityInteract }

func (t *WaitForUserReply) Description() string {
	return "Poll for the human's answer to a prompt you made with ask_user. " +
		"Pass the ticket ask_user gave you. If the human has not answered yet " +
		"this returns answered=false at its timeout; re-call until answered=true " +
		"or the bridge returns an error (the window expired). The timeout you " +
		"pass bounds THIS poll, not the whole window -- the window's own 300 s " +
		"deadline is the bridge's business."
}

func (t *WaitForUserReply) InputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"ticket": {
				"type": "string",
				"minLength": 1,
				"description": "The ticket ask_user returned."
			},
			"timeout": {
				"type": "number",
				"minimum": 0,
				"description": "How long THIS poll may block for, in seconds. Default 30. The bridge's window (300 s from ask_user) is separate -- this only bounds the individual call."
			}
		},
		"required": ["ticket"],
		"additionalProperties": false
	}`)
}

type waitForUserReplyParams struct {
	Ticket  string  `json:"ticket"`
	Timeout float64 `json:"timeout,omitempty"`
}

type waitForUserReplyResult struct {
	Answered bool   `json:"answered"`
	Text     string `json:"text"`
}

func (t *WaitForUserReply) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	interact, err := ctx.Interact()
	if err != nil {
		return nil, err
	}
	var request waitForUserReplyParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}

	timeout := time.Duration(request.Timeout * float64(time.Second))
	reply, err := interact.WaitForUserReply(request.Ticket, timeout)
	if err != nil {
		return nil, err
	}
	return waitForUserReplyResult{Answered: reply.Answered, Text: reply.Text}, nil
}
