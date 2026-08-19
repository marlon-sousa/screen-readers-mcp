// screenreader-mcp domain -- the set_log_level tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `log`.
// USES: ports.LogReader, through ToolContext.ReaderLog().
// LISTED BY: registry.go.

package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// SetLogLevel changes the reader's diagnostic log verbosity.
type SetLogLevel struct{}

var _ Tool = (*SetLogLevel)(nil)

func (t *SetLogLevel) Name() string                    { return "set_log_level" }
func (t *SetLogLevel) Capability() entities.Capability { return entities.CapabilityLog }

func (t *SetLogLevel) Description() string {
	return "Change the screen reader's own diagnostic logging level for the rest of " +
		"this session. IMPORTANT: a log level CANNOT be raised retroactively. " +
		"Python's logging decides at the *logger* whether a record exists at all, " +
		"so if the reader's root logger was at INFO when a command ran, DEBUG records were never " +
		"created and no filter can recover them. The loop is: raise the level with " +
		"set_log_level, re-run the command you are debugging, then get_log. " +
		"Downwards is free: the journal holds more than asked for and a filter " +
		"shows less. This is a real (if temporary) change to the reader -- at " +
		"debug/io levels the reader is slower, and the ring fills faster so " +
		"windows expire sooner. The level is restored at session teardown " +
		"regardless of how the session ends. Parameters: level (one of debug, io, " +
		"debugwarning, info -- 'warning' and 'error' exist as get_log minLevel " +
		"filters but cannot be SET, since lowering the reader's own floor would " +
		"silence warnings in the user's own log). Returns the level now in force " +
		"and the previous level."
}

func (t *SetLogLevel) InputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"level": {
				"type": "string",
				"enum": ["debug", "io", "debugwarning", "info"],
				"description": "The logging level to set. 'warning' and 'error' are get_log minLevel filters only, not settable: lowering the reader's own floor would silence warnings in the user's log for the rest of the session."
			}
		},
		"required": ["level"],
		"additionalProperties": false
	}`)
}

func (t *SetLogLevel) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"level": {
				"type": "string",
				"description": "The level now in force for the rest of the session. Restored at teardown however the session ends."
			},
			"previous": {
				"type": "string",
				"description": "What it was before. Records that were never emitted at the previous level cannot be recovered by raising it now -- re-run the command you are debugging, then read the log."
			}
		},
		"required": ["level", "previous"]
	}`)
}

type setLogLevelRequest struct {
	Level string `json:"level"`
}

func (t *SetLogLevel) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	logPort, err := ctx.ReaderLog()
	if err != nil {
		return nil, err
	}
	var request setLogLevelRequest
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	return logPort.SetLogLevel(request.Level)
}
