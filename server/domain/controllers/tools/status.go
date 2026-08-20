// screenreader-mcp domain -- the status tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. UNGATED.
// USES: ConnectionControl.Status, .Current and .Verify, via ToolContext.
// LISTED BY: registry.go.
//
// WHEN A SESSION IS LIVE THIS MAKES A REAL `ping` ROUND TRIP, so the answer is
// proof rather than possibly-stale local state. Two things make that worth the
// round trip. A bridge can die without this server noticing, since it only finds
// out when it next speaks. And an idle agent LOSES ITS SESSION BY DESIGN: the
// bridge's command-inactivity watchdog is deliberately not reset by `ping`
// (protocol.md §6), so a keepalive cannot mask an abandoned session -- which
// means "am I still connected?" is a question this server genuinely cannot
// answer from memory.
//
// This is also why `ping` is not a tool of its own: what an agent wants from it
// is "is this connection real right now?", which is exactly this answer.
package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// Status reports the connection.
type Status struct{}

var _ Tool = (*Status)(nil)

func (t *Status) Name() string { return "status" }

func (t *Status) Capability() entities.Capability { return "" }

func (t *Status) Description() string {
	return "Report the screen reader connection: its state, why it is in that " +
		"state, and the current session if there is one. When a session is live " +
		"this makes a real round trip to the reader, so the answer is proof rather " +
		"than a cached guess -- an idle session can be dropped by the reader's own " +
		"inactivity watchdog, and a silent session can have had its speech restored " +
		"by the reader's silence cap. Takes no parameters."
}

func (t *Status) InputSchema() json.RawMessage {
	return json.RawMessage(`{"type":"object","properties":{},"additionalProperties":false}`)
}

func (t *Status) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"state": {
			"type": "string",
			"enum": ["disconnected", "connecting", "connected", "incompatible"],
			"description": "Where the one connection stands. \"incompatible\" is a bridge that answered while announcing a protocol version this server does not support: the remedy is to update one of the two components, not to retry."
		},
		"reason": {
			"type": "string",
			"description": "Why the state holds. Populated for the states you must act on, absent for the uneventful ones."
		},
		"live": {
			"type": "boolean",
			"description": "The outcome of a REAL round trip to the reader: true when it answered, false when it did not, and ABSENT when there was no session to ask. This is why the answer is proof rather than a cached guess."
		},
		"liveError": {
			"type": "string",
			"description": "Why the round trip failed, when it did."
		},
		"suppressing": {
			"type": "boolean",
			"description": "Whether the reader is withholding speech from the person at that machine RIGHT NOW -- read from the same round trip as the live field above, so it is current rather than remembered. A silent session normally answers true. It answers FALSE once the reader's silence cap has restored speech (see connect_reader's silenceCap): that costs you nothing, since capture is unaffected and get_speech still returns everything, but the human can hear their machine again. Absent when there was no session to ask, and when the bridge does not report it."
		},
		"session": {
			"type": "object",
			"description": "The live session. Absent when none is -- including when the round trip above just discovered it was gone.",
			"properties": {
				"reader": {"type": "string", "description": "The connected reader's name."},
				"readerVersion": {"type": "string", "description": "The reader's own version."},
				"endpoint": {"type": "string", "description": "The endpoint it is connected over."},
				"capabilities": {
					"type": "array",
					"items": {"type": "string"},
					"description": "What this reader announced it can do. Intersect this with screenreader://tools to know which tools are callable right now."
				},
				"mode": {"type": "string", "enum": ["silent", "live"], "description": "The capture mode this session is fixed to."},
				"persona": {"type": "string", "description": "What this session declared it stands for. Absent for a session that predates personas."},
				"synth": {"type": "string", "description": "The speech synthesizer in use."},
				"logPath": {"type": "string", "description": "The reader-side session transcript."},
				"bridgeVersion": {"type": "string", "description": "The bridge build serving this session. Absent when the bridge did not say."},
				"protocolVersion": {"type": "integer", "description": "The wire protocol version both halves agreed on."}
			},
			"required": ["reader", "readerVersion", "endpoint", "capabilities", "mode", "synth", "logPath", "protocolVersion"]
		}
	},
	"required": ["state"]
}`)
}

// statusSession is the live session as the agent sees it.
type statusSession struct {
	Reader        string   `json:"reader"`
	ReaderVersion string   `json:"readerVersion"`
	Endpoint      string   `json:"endpoint"`
	Capabilities  []string `json:"capabilities"`
	Mode          string   `json:"mode"`
	// Persona is what this session declared it stands for (spec 0029) -- part of
	// the answer to "what am I in the middle of?", because it decides what the
	// run's findings mean.
	Persona       string `json:"persona,omitempty"`
	Synth         string `json:"synth"`
	LogPath       string `json:"logPath"`
	BridgeVersion string `json:"bridgeVersion,omitempty"`
	ProtocolVer   int    `json:"protocolVersion"`
}

type statusResult struct {
	State  string `json:"state"`
	Reason string `json:"reason,omitempty"`

	// Live is the outcome of the round trip: true when the reader answered,
	// false when it did not, and absent when there was no session to ask.
	Live *bool `json:"live,omitempty"`

	// LiveError is why the round trip failed, when it did.
	LiveError string `json:"liveError,omitempty"`

	// Suppressing is whether the reader is withholding speech from its human
	// right now, off the same round trip as Live above.
	//
	// This is how a silence-cap LIFT is discoverable by asking (spec 0032
	// Part 5). Nothing is pushed -- a lift arrives as no error, no exception
	// and no field on an unrelated result -- so an agent that never looks
	// carries on working correctly and simply does not know the room got
	// loud. That is an acceptable outcome: the mechanism exists for the
	// human, and the human is served either way. This is for the agent that
	// does want to know.
	//
	// A pointer, because "the bridge did not say" is a third answer.
	Suppressing *bool `json:"suppressing,omitempty"`

	Session *statusSession `json:"session,omitempty"`
}

func (t *Status) Execute(ctx ToolContext, _ json.RawMessage) (any, error) {
	// Verify FIRST: it re-checks the wire and records a loss it finds, so the
	// state read afterwards is the corrected one rather than the one this
	// process happened to be holding. Its error is reported, not returned --
	// "the connection is gone" is the answer status was asked for, not a
	// failure of the tool.
	var (
		live        *bool
		liveError   string
		suppressing *bool
	)
	if ctx.Connection != nil {
		report, err := ctx.Control.Verify()
		answered := err == nil
		live = &answered
		if err != nil {
			liveError = err.Error()
		} else {
			// Only from a round trip that actually answered: a report from a
			// failed ping describes nothing, and reporting it would be
			// guessing in the one tool built not to.
			suppressing = report.Suppressing
		}
	}

	recorded := ctx.Control.Status()
	result := statusResult{
		State:       recorded.State.String(),
		Reason:      recorded.Reason,
		Live:        live,
		LiveError:   liveError,
		Suppressing: suppressing,
	}

	// Re-read the connection AFTER Verify: if the round trip discovered a
	// loss, there is no session left to describe.
	if connection := ctx.Control.Current(); connection != nil {
		session := connection.Session
		result.Session = &statusSession{
			Reader:        session.Reader.Name,
			ReaderVersion: session.Reader.Version,
			Endpoint:      connection.Endpoint.String(),
			Capabilities:  session.Capabilities.Strings(),
			Mode:          session.Mode.String(),
			Persona:       session.Persona.String(),
			Synth:         session.Synth,
			LogPath:       session.LogPath,
			BridgeVersion: session.BridgeVersion,
			ProtocolVer:   session.ProtocolVersion,
		}
	}
	return result, nil
}
