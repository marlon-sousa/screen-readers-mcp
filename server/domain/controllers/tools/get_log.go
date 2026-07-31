// screenreader-mcp domain -- the get_log tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `log`.
// USES: ports.LogReader, through ToolContext.ReaderLog().
// LISTED BY: registry.go.
//
// Returns a filtered, formatted slice of the reader's diagnostic log for one
// or more command windows. The agent can filter by level, by message content,
// and by module/message exclusion, and can project which fields to render.
//
// The capture level reported is the floor that was in force while the window
// was recorded; an empty slice with capturedAtLevel above the requested
// minLevel tells the agent that the records it wants were never emitted,
// rather than that none exist -- the two have entirely different remedies.

package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// GetLog reads and filters the reader's diagnostic log.
type GetLog struct{}

var _ Tool = (*GetLog)(nil)

func (t *GetLog) Name() string                    { return "get_log" }
func (t *GetLog) Capability() entities.Capability { return entities.CapabilityLog }

func (t *GetLog) Description() string {
	return "Return a filtered, formatted slice of the screen reader's own diagnostic log " +
		"for one or more command windows. The log is bracketed by command -- each command " +
		"records the journal position before and after dispatch, so you can ask for " +
		"\"what NVDA logged while press_gesture id 7 ran\" and get exactly that window, " +
		"with nothing from before or after. Parameters: commandId (defaults to the most " +
		"recently marked command), windows (how many command windows to include, counting " +
		"back from the anchor; default 1), minLevel (drop records below this level -- " +
		"the LogLevel enum includes 'warning' and 'error' as filter-only values), " +
		"contains (keep only records whose message contains any of these substrings, " +
		"case-insensitive), exclude (drop records whose module or message contains any " +
		"of these, case-insensitive), fields (which fields to render; default " +
		"['time','level','module','message'] -- use ['level','message'] for the compact " +
		"form), maxEntries (default 200). Returns formatted text (like a slice of " +
		"nvda.log), the entry count, how many matched before the cap, whether the " +
		"result was truncated, the command id range covered, and capturedAtLevel -- " +
		"the floor in force while the window was recorded. IMPORTANT: a log level " +
		"cannot be raised retroactively. If NVDA's logger was at INFO when a command " +
		"ran, DEBUG records were never created and no filter can recover them. The " +
		"remedy is set_log_level, re-run the command, then get_log. capturedAtLevel " +
		"tells you which situation you are in without guesswork."
}

func (t *GetLog) InputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"commandId": {
				"type": "integer",
				"description": "The request id whose window to anchor on. Defaults to the most recently marked command."
			},
			"windows": {
				"type": "integer",
				"default": 1,
				"description": "How many command windows to include, counting back from the anchor."
			},
			"minLevel": {
				"type": "string",
				"enum": ["debug", "io", "debugwarning", "info", "warning", "error"],
				"description": "Drop records below this level."
			},
			"contains": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Keep only records whose message contains any of these substrings (case-insensitive)."
			},
			"exclude": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Drop records whose module or message contains any of these (case-insensitive)."
			},
			"fields": {
				"type": "array",
				"items": {"type": "string", "enum": ["time", "level", "module", "message", "thread", "thread_id"]},
				"description": "Which fields to render per record. Default: time, level, module, message."
			},
			"maxEntries": {
				"type": "integer",
				"default": 200,
				"description": "Maximum number of records to return."
			}
		},
		"additionalProperties": false
	}`)
}

type getLogRequest struct {
	CommandID  *int     `json:"commandId"`
	Windows    int      `json:"windows"`
	MinLevel   *string  `json:"minLevel"`
	Contains   []string `json:"contains"`
	Exclude    []string `json:"exclude"`
	Fields     []string `json:"fields"`
	MaxEntries int      `json:"maxEntries"`
}

func (t *GetLog) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	logPort, err := ctx.ReaderLog()
	if err != nil {
		return nil, err
	}
	var request getLogRequest
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	return logPort.GetLog(ports.GetLogParams{
		CommandID:  request.CommandID,
		Windows:    request.Windows,
		MinLevel:   request.MinLevel,
		Contains:   request.Contains,
		Exclude:    request.Exclude,
		Fields:     request.Fields,
		MaxEntries: request.MaxEntries,
	})
}
