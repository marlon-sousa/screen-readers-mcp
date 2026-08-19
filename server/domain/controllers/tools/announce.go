// screenreader-mcp domain -- the announce tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `interact`.
// USES: ports.Interact, through ToolContext.Interact().
// LISTED BY: registry.go.
//
// One of the three tools that address a HUMAN. Everything else here observes or
// drives a screen reader; this speaks to the person in front of it, through the
// reader's real synthesizer and UNDERNEATH whatever suppression the capture mode
// has in place -- which is the whole point, because the mode where the agent
// most needs to say something is the mode where the tester can hear nothing
// else.
//
// The description below carries the operational warning, and has to: in `silent`
// mode the tester hears this announcement and then nothing further, and cannot
// navigate. Since 11.2 there IS a reply channel -- `ask_user` opens a window in
// which the human hears normally and can answer -- so the division of labour is
// the thing to get across: announce TELLS, ask_user ASKS. An agent that reads
// this tool as a chat channel will strand somebody, which is why the description
// names ask_user rather than leaving the agent to find it.
package tools

import (
	"encoding/json"
	"errors"
	"strings"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// Announce speaks a message to the human operating the reader.
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
		"did. If you truly cannot proceed at all, say so and name " +
		"NVDA+control+shift+b, which stops the bridge and returns their machine."
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
	// Rejected before the port is touched: an empty announcement is two cue
	// beeps followed by silence, which a tester reads as a malfunction of the
	// one channel they are relying on.
	if strings.TrimSpace(request.Text) == "" {
		return nil, errors.New("text is required, and must not be empty or whitespace")
	}

	if err := interact.Announce(request.Text); err != nil {
		return nil, err
	}
	// Echo what was spoken, as press_gesture echoes its ids: the reader returns
	// only an acknowledgement, so the useful confirmation is that this exact
	// text reached it.
	return announceResult{Announced: request.Text}, nil
}
