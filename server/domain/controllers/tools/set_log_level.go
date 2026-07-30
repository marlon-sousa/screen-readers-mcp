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
		"so if NVDA's root was at INFO when a command ran, DEBUG records were never " +
		"created and no filter can recover them. The loop is: raise the level with " +
		"set_log_level, re-run the command you are debugging, then get_log. " +
		"Downwards is free: the journal holds more than asked for and a filter " +
		"shows less. This is a real (if temporary) change to the reader -- at " +
		"debug/io levels the reader is slower, and the ring fills faster so " +
		"windows expire sooner. The level is restored at session teardown " +
		"regardless of how the session ends. Parameters: level (one of debug, io, " +
		"debugwarning, info, warning, error). Returns the level now in force and " +
		"the previous level."
}

func (t *SetLogLevel) InputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"level": {
				"type": "string",
				"enum": ["debug", "io", "debugwarning", "info", "warning", "error"],
				"description": "The logging level to set."
			}
		},
		"required": ["level"],
		"additionalProperties": false
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
