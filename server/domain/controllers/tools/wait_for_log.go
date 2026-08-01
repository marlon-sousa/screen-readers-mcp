// screenreader-mcp domain -- the wait_for_log tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `log`.
// USES: ports.LogReader, through ToolContext.ReaderLog().
// LISTED BY: registry.go.
//
// The journal's answer to wait_for_speech, and PULL, not push: the agent asks
// and waits, so nothing in this protocol tails or streams unasked (spec 0021).
// For "watch me, a bug is about to happen", block at minLevel error and get the
// moment it happens, instead of picking a poll cadence and hoping.
//
// NOT FINDING A RECORD IS AN ANSWER, NOT A FAILURE -- wait_for_speech's
// established manners, for the same reason: "nothing went wrong in those thirty
// seconds" is frequently exactly what was being checked, and an error would make
// that indistinguishable from a broken connection.

package tools

import (
	"encoding/json"
	"errors"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// WaitForLog blocks until a matching log record is journalled.
type WaitForLog struct{}

var _ Tool = (*WaitForLog)(nil)

func (t *WaitForLog) Name() string                    { return "wait_for_log" }
func (t *WaitForLog) Capability() entities.Capability { return entities.CapabilityLog }

func (t *WaitForLog) Description() string {
	return "Wait until the screen reader logs a record matching min_level and/or " +
		"contains, or until the timeout elapses. Returns found=true with the matching " +
		"record and the journal position just past it, or found=false if nothing " +
		"matched -- NOT matching is a normal answer, not an error, so this is also how " +
		"you assert that nothing went wrong during an interval. Only records logged " +
		"AFTER this call begins can match, so an error from earlier in the session " +
		"never satisfies \"wait for the next error\". The returned position feeds " +
		"straight back into get_log as since_position, which reads what happened " +
		"after the trigger without repeating the trigger itself. Use this instead of " +
		"polling get_log in a loop: for an intermittent fault, block at " +
		"min_level 'error' and reproduce, and you get the moment it happens rather " +
		"than a cadence you had to guess. Requires at least one of min_level or " +
		"contains -- waiting for any record at all would return on the first thing " +
		"the reader did, which is never what anyone meant."
}

func (t *WaitForLog) InputSchema() json.RawMessage {
	return json.RawMessage(`{
		"type": "object",
		"properties": {
			"min_level": {
				"type": "string",
				"enum": ["debug", "io", "debugwarning", "info", "warning", "error"],
				"description": "Match only records at or above this level. 'error' is the usual choice for catching a fault as it happens."
			},
			"contains": {
				"type": "array",
				"items": {"type": "string"},
				"description": "Match a record whose message contains any of these substrings (case-insensitive)."
			},
			"timeout": {
				"type": "number",
				"exclusiveMinimum": 0,
				"maximum": 110,
				"description": "How long to wait, in seconds. Omit to use the reader's own default. Capped at 110 seconds, the reader's own limit on a single blocking command."
			}
		},
		"additionalProperties": false
	}`)
}

type waitForLogRequest struct {
	MinLevel *string  `json:"min_level"`
	Contains []string `json:"contains"`
	Timeout  float64  `json:"timeout"`
}

type waitForLogResult struct {
	Found bool `json:"found"`
	// Position is one past the match, so it is directly usable as get_log's
	// since_position. On a miss it is the journal's current position, which is
	// still a usable "from here" mark.
	Position int    `json:"position"`
	Text     string `json:"text"`
}

func (t *WaitForLog) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	logPort, err := ctx.ReaderLog()
	if err != nil {
		return nil, err
	}
	var request waitForLogRequest
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}
	if request.MinLevel == nil && len(request.Contains) == 0 {
		// Refused here rather than at the bridge, for the same reason
		// wait_for_speech refuses the empty string: an unfiltered wait returns on
		// the very next thing the reader logs, which looks like a working
		// assertion while asserting nothing.
		return nil, errors.New("at least one of min_level or contains is required")
	}

	wait := ports.LogWait{MinLevel: request.MinLevel, Contains: request.Contains}
	if request.Timeout > 0 {
		wait.Timeout = time.Duration(request.Timeout * float64(time.Second))
		// The same cap wait_for_user_reply applies, and for the same reason: a
		// blocking command may not outlast the session's command-inactivity
		// watchdog, or the reader answers and then tears the session down under
		// the agent. Said out loud here, and in the schema, so an agent never has
		// to discover it by losing a session.
		if wait.Timeout > maxPollTimeout {
			wait.Timeout = maxPollTimeout
		}
	}

	match, err := logPort.WaitForLog(wait)
	if err != nil {
		return nil, err
	}
	return waitForLogResult{Found: match.Found, Position: match.Position, Text: match.Text}, nil
}
