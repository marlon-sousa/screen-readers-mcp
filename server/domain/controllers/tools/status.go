// screenreader-mcp domain -- the status tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, ungated.
// USES: ConnectionControl.Status, .Current and .Verify, via ToolContext.
// LISTED BY: registry.go.
// A live session gets a real ping round trip: a bridge can die unnoticed, and the inactivity watchdog is not reset by ping.
package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

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

type statusSession struct {
	Reader        string   `json:"reader"`
	ReaderVersion string   `json:"readerVersion"`
	Endpoint      string   `json:"endpoint"`
	Capabilities  []string `json:"capabilities"`
	Mode          string   `json:"mode"`
	Persona       string   `json:"persona,omitempty"`
	Synth         string   `json:"synth"`
	LogPath       string   `json:"logPath"`
	BridgeVersion string   `json:"bridgeVersion,omitempty"`
	ProtocolVer   int      `json:"protocolVersion"`
}

type statusResult struct {
	State  string `json:"state"`
	Reason string `json:"reason,omitempty"`

	// Live is absent when there was no session to ask.
	Live *bool `json:"live,omitempty"`

	LiveError string `json:"liveError,omitempty"`

	// Suppressing is nil when the bridge did not say.
	Suppressing *bool `json:"suppressing,omitempty"`

	Session *statusSession `json:"session,omitempty"`
}

func (t *Status) Execute(ctx ToolContext, _ json.RawMessage) (any, error) {
	// Verify first, so the state read afterwards is the corrected one; its error is reported, not returned.
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
			// Only from a round trip that answered: a failed ping's report describes nothing.
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

	// Re-read after Verify: a loss it found leaves no session to describe.
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
