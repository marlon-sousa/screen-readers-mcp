// screenreader-mcp domain -- the get_log tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `log`.
// USES: ports.LogReader, through ToolContext.ReaderLog().
// LISTED BY: registry.go.
//
// Returns a filtered, formatted slice of the reader's diagnostic log, anchored
// one of three mutually exclusive ways (spec 0021): since_position (a cursor the
// caller holds, so reads never consume), last_seconds (relative to now, for "it
// just happened" with no mark taken beforehand), or command_id/windows (0020's
// command-span anchor, still the default). The agent can filter by level, by
// message content, and by module/message exclusion, and can project which fields
// to render.
//
// The capture level reported is the floor that was in force for the span; an
// empty slice with capturedAtLevel above the requested minLevel tells the agent
// that the records it wants were never emitted, rather than that none exist --
// the two have entirely different remedies.

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
	return "Return a filtered, formatted slice of the screen reader's own diagnostic log. " +
		"There are THREE mutually exclusive ways to say which records you want, and " +
		"supplying more than one is an error. (1) sincePosition: read forward from a " +
		"mark taken earlier with get_log_position, or from a previous call's " +
		"nextPosition, or from the logPosition on a speech or braille entry. Nothing " +
		"is consumed, so re-issuing the same position with a different filter returns " +
		"the same records re-filtered -- this is the anchor to use when watching a " +
		"human drive the reader, or when polling while consequences arrive. " +
		"(2) lastSeconds: everything from N seconds ago until now, for \"that just " +
		"happened\" when no mark was taken. (3) commandId/windows: the log is also " +
		"partitioned by command -- each command's span runs from when it was " +
		"dispatched until the NEXT command was dispatched -- so you can ask for " +
		"\"what the reader logged for press_gesture id 7\" and get everything attributed to " +
		"it, including the work it caused after the call returned. Note that " +
		"attribution is by most-recent-command, not by causation: think for thirty " +
		"seconds after a keypress and those thirty seconds land in that keypress's " +
		"span. Parameters: sincePosition, lastSeconds, commandId (defaults to the most " +
		"recently marked command), windows (how many command spans to include, counting " +
		"back from the anchor; default 1), minLevel (drop records below this level -- " +
		"the LogLevel enum includes 'warning' and 'error' as filter-only values), " +
		"contains (keep only records whose message contains any of these substrings, " +
		"case-insensitive), exclude (drop records whose module or message contains any " +
		"of these, case-insensitive), fields (which fields to render; default " +
		"['time','level','module','message'] -- use ['level','message'] for the compact " +
		"form), maxEntries (default 200). Returns formatted text (like a slice of " +
		"the reader's own log file), the entry count, how many matched before the cap, whether the " +
		"result was truncated, nextPosition (pass it back as sincePosition to " +
		"continue the tail with no gap and no repeat), the command id range covered " +
		"(absent when anchored by position or time, since such a read is " +
		"attributable to no single command), and capturedAtLevel -- the floor in " +
		"force for the span. truncated:true on a sincePosition read means the " +
		"records you asked for aged out of the ring before you read them, which is " +
		"how a poll loop learns it fell behind. IMPORTANT: a log level " +
		"cannot be raised retroactively. If the reader's logger was at INFO when a command " +
		"ran, DEBUG records were never created and no filter can recover them. The " +
		"remedy is set_log_level, re-run the command, then get_log. capturedAtLevel " +
		"tells you which situation you are in without guesswork."
}

func (t *GetLog) InputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"sincePosition": {
				"type": "integer",
				"minimum": 0,
				"description": "Read forward from this journal position. Mutually exclusive with lastSeconds and commandId. Reading never consumes, so the same position can be re-read with a different filter."
			},
			"lastSeconds": {
				"type": "number",
				"exclusiveMinimum": 0,
				"description": "Read everything from this many seconds ago until now. Mutually exclusive with sincePosition and commandId."
			},
			"commandId": {
				"type": "integer",
				"description": "The request id whose span to anchor on. Defaults to the most recently marked command. Mutually exclusive with sincePosition and lastSeconds."
			},
			"windows": {
				"type": "integer",
				"default": 1,
				"description": "How many command spans to include, counting back from the anchor. Belongs to commandId only -- sending it with sincePosition or lastSeconds is refused, since those already say how far back to read."
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

func (t *GetLog) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"text": {
				"type": "string",
				"description": "The matching records, formatted and joined -- a slice of the reader's log as it would read on disk, rendered with whichever fields were asked for."
			},
			"entries": {"type": "integer", "description": "How many records this slice actually carries."},
			"matched": {"type": "integer", "description": "How many matched the filter BEFORE maxEntries capped it. Larger than entries means there is more where this came from."},
			"truncated": {
				"type": "boolean",
				"description": "Whether records were dropped. On a sincePosition read this means the records you asked for AGED OUT of the ring before you read them -- which is how a poll loop learns it fell behind, rather than silently missing them."
			},
			"nextPosition": {
				"type": "integer",
				"description": "The journal's position after this read. Pass it back as sincePosition to continue the tail with no gap and no repeat."
			},
			"fromCommandId": {
				"type": "integer",
				"description": "The first command span this slice covers. ABSENT when the read was anchored by position or time: such a read spans whatever commands fall in it and is attributable to none."
			},
			"toCommandId": {"type": "integer", "description": "The last command span it covers, on the same terms."},
			"capturedAtLevel": {
				"type": "string",
				"description": "The logging floor in force for the span. THIS IS THE FIELD THAT TELLS YOU WHICH SITUATION YOU ARE IN: an empty slice with capturedAtLevel above the minLevel you asked for means those records were never emitted at all, not that nothing happened -- and no filter can recover them. Raise the level with set_log_level, re-run the command, then read again. Exact for a command anchor; approximate for a position or time anchor, which may straddle a change."
			}
		},
		"required": ["text", "entries", "matched", "truncated", "nextPosition", "capturedAtLevel"]
	}`)
}

type getLogRequest struct {
	// Pointers, so "not asked for" is distinguishable from position 0 or zero
	// seconds -- the anchors are mutually exclusive, and a zero value that read
	// as "asked for" would silently collide with the default anchor.
	SincePosition *int     `json:"sincePosition"`
	LastSeconds   *float64 `json:"lastSeconds"`
	CommandID     *int     `json:"commandId"`
	Windows       int      `json:"windows"`
	MinLevel      *string  `json:"minLevel"`
	Contains      []string `json:"contains"`
	Exclude       []string `json:"exclude"`
	Fields        []string `json:"fields"`
	MaxEntries    int      `json:"maxEntries"`
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
	// The anchors are forwarded as given. The bridge owns the "at most one"
	// rule and refuses the rest; deciding it here as well would put the same
	// judgement in two places, and they would eventually disagree.
	return logPort.GetLog(ports.GetLogParams{
		SincePosition: request.SincePosition,
		LastSeconds:   request.LastSeconds,
		CommandID:     request.CommandID,
		Windows:       request.Windows,
		MinLevel:      request.MinLevel,
		Contains:      request.Contains,
		Exclude:       request.Exclude,
		Fields:        request.Fields,
		MaxEntries:    request.MaxEntries,
	})
}
