// screenreader-mcp domain -- the wait_for_user_reply tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, gated on interact.
// USES: ports.Interact, through ToolContext.Interact().
// LISTED BY: registry.go.
// Answers answered=false on a poll miss; an expired or cancelled ticket is an error.
package tools

import (
	"encoding/json"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// defaultPollTimeout is sent explicitly: omitted, the client sizes its deadline from the 5 s contract default while the bridge waits 30 s, and the late reply then reads as a dead connection.
const defaultPollTimeout = 30 * time.Second

// maxPollTimeout mirrors the bridge's cap: a poll may not outlast the session's 120 s inactivity watchdog, which is not refreshed when a handler returns.
const maxPollTimeout = 110 * time.Second

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
		"deadline is the bridge's business, so re-poll rather than asking for one " +
		"long wait (a single poll is capped at 110 s)."
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
				"maximum": 110,
				"description": "How long THIS poll may block for, in seconds. Default 30, maximum 110 -- a longer poll would outlive the session's inactivity watchdog, so the bridge clamps it. The bridge's window (300 s from ask_user) is separate: this only bounds the individual call, so keep polling until answered."
			}
		},
		"required": ["ticket"],
		"additionalProperties": false
	}`)
}

func (t *WaitForUserReply) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"answered": {
			"type": "boolean",
			"description": "Whether the human acknowledged before THIS poll timed out. False is normal: re-call with the same ticket. The prompt's own window is separate and longer."
		},
		"text": {
			"type": "string",
			"description": "What the human said, when the bridge collects a reply. Empty when they only acknowledged, and when the poll returned unanswered."
		}
	},
	"required": ["answered", "text"]
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
	if timeout <= 0 {
		timeout = defaultPollTimeout
	}
	if timeout > maxPollTimeout {
		timeout = maxPollTimeout
	}

	reply, err := interact.WaitForUserReply(request.Ticket, timeout)
	if err != nil {
		return nil, err
	}
	return waitForUserReplyResult{Answered: reply.Answered, Text: reply.Text}, nil
}
