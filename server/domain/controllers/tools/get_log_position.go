// screenreader-mcp domain -- the get_log_position tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, gated on log.
// USES: ports.LogReader, through ToolContext.ReaderLog().
// LISTED BY: registry.go.

package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

type GetLogPosition struct{}

var _ Tool = (*GetLogPosition)(nil)

func (t *GetLogPosition) Name() string                    { return "get_log_position" }
func (t *GetLogPosition) Capability() entities.Capability { return entities.CapabilityLog }

func (t *GetLogPosition) Description() string {
	return "Mark the screen reader's diagnostic log at this instant, and return the " +
		"mark. Returns position (the journal's current append position) and time " +
		"(wall clock, for lining the mark up against a session transcript or against " +
		"a human's account of when something happened). Returns NO records -- this is " +
		"the cheap \"note where I am\" call. The pattern is: call this, then do " +
		"something (or ask a human to), then call get_log with since_position set to " +
		"the position you got back, which returns exactly the records from that " +
		"interval. Use it whenever you are about to observe rather than act: watching " +
		"a person work, waiting for an intermittent fault, or polling while the " +
		"consequences of a keypress arrive. It is the log's counterpart to " +
		"get_next_speech_index. Takes no parameters."
}

func (t *GetLogPosition) InputSchema() json.RawMessage {
	return json.RawMessage(`{"type":"object","properties":{},"additionalProperties":false}`)
}

func (t *GetLogPosition) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"position": {
				"type": "integer",
				"description": "The journal's current append position: the mark. Hand it back to get_log as sincePosition to read exactly what happened after this instant. No records are returned here -- that is the point of the call."
			},
			"time": {
				"type": "string",
				"description": "The wall clock at the mark, for lining it up against a session transcript or against a human's account of when something happened."
			}
		},
		"required": ["position", "time"]
	}`)
}

type logPositionResult struct {
	Position int    `json:"position"`
	Time     string `json:"time"`
}

func (t *GetLogPosition) Execute(ctx ToolContext, _ json.RawMessage) (any, error) {
	logPort, err := ctx.ReaderLog()
	if err != nil {
		return nil, err
	}
	mark, err := logPort.LogPosition()
	if err != nil {
		return nil, err
	}
	return logPositionResult{Position: mark.Position, Time: mark.Time}, nil
}
