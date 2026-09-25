// screenreader-mcp domain -- the disconnect_reader tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, ungated.
// USES: ConnectionControl.Disconnect, via ToolContext.
// LISTED BY: registry.go.
package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

type DisconnectReader struct{}

var _ Tool = (*DisconnectReader)(nil)

func (t *DisconnectReader) Name() string { return "disconnect_reader" }

func (t *DisconnectReader) Capability() entities.Capability { return "" }

func (t *DisconnectReader) Description() string {
	return "End the current screen reader session. The tool list is unchanged by " +
		"this -- nothing is withdrawn -- but every gated tool goes back to " +
		"refusing, naming the absent session rather than a missing capability. " +
		"The reader restores anything it changed for the session -- speech " +
		"and its own log level. Takes no parameters, and is not an error when no " +
		"session is live. Reconnect with connect_reader; the new session starts " +
		"fresh, with new logs and speech indices starting over."
}

func (t *DisconnectReader) InputSchema() json.RawMessage {
	return json.RawMessage(`{"type":"object","properties":{},"additionalProperties":false}`)
}

func (t *DisconnectReader) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"disconnected": {
			"type": "boolean",
			"description": "Whether a live session was actually ended. False means there was nothing to disconnect -- a different fact from having ended one, and neither is a failure."
		},
		"reader": {
			"type": "string",
			"description": "The reader whose session ended. Absent when none was live."
		}
	},
	"required": ["disconnected"]
}`)
}

type disconnectResult struct {
	Disconnected bool   `json:"disconnected"`
	Reader       string `json:"reader,omitempty"`
}

func (t *DisconnectReader) Execute(ctx ToolContext, _ json.RawMessage) (any, error) {
	// Read before disconnecting: afterwards there is nothing left to name.
	reader := ""
	if ctx.Connection != nil {
		reader = ctx.Connection.Session.Reader.Name
	}

	if err := ctx.Control.Disconnect(); err != nil {
		return nil, err
	}
	return disconnectResult{Disconnected: reader != "", Reader: reader}, nil
}
