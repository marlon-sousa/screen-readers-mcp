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

// defaultPollTimeout is what an omitted `timeout` means, filled in HERE rather
// than left to the bridge's own default.
//
// The bridge would default it to 30 s, but the client sizes its local deadline
// from the value it sent -- and when nothing is sent it can only guess. It
// guesses with the contract default shared by the other waiting commands (5 s),
// which is far shorter than 30, so the client would give up first, return a
// timeout instead of `answered: false`, and leave the bridge's late reply
// unread in the stream -- which the NEXT call reads as a mismatched id and
// treats as a dead connection. Sending the value explicitly keeps the two ends
// agreeing about when to stop waiting.
const defaultPollTimeout = 30 * time.Second

// maxPollTimeout mirrors the bridge's own cap on a single poll (spec 0016).
//
// A poll may not outlast the session's command-inactivity watchdog (120 s by
// default), which is measured from the moment the command is DISPATCHED and is
// deliberately not refreshed when a handler returns: a poll that blocked longer
// than the window would answer the agent and then have the session torn down
// under it. The bridge clamps for every client; this is the same number said
// out loud in the schema, so an agent never has to discover it by losing a
// session.
const maxPollTimeout = 110 * time.Second

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

	// Fill the default and apply the cap here, so the value the bridge receives
	// is the same one the client sizes its deadline from (see defaultPollTimeout)
	// and no poll can outlive the inactivity watchdog (see maxPollTimeout).
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
