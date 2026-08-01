// screenreader-mcp domain -- the LogReader port (the `log` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. The `log` capability group (specs 0020, 0021), covering
// getLog, setLogLevel, getLogPosition and waitForLog -- every command that reads
// or configures the reader's diagnostic log.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_log, set_log_level, get_log_position and wait_for_log tool
// controllers.
// HANDED OUT BY: the handshake, only when the reader announced `log`.

package ports

import "time"

// GetLogParams is the domain shape of a getLog request (specs 0020, 0021).
//
// The three anchors -- SincePosition, LastSeconds, and CommandID/Windows -- are
// MUTUALLY EXCLUSIVE and resolved in that order. Supplying more than one is an
// error at the bridge rather than a precedence puzzle here.
type GetLogParams struct {
	// SincePosition reads forward from a mark the caller took earlier. Nothing is
	// consumed, so re-issuing the same position is idempotent -- which is what
	// makes a poll loop re-runnable with a different filter (spec 0021).
	SincePosition *int `json:"sincePosition,omitempty"`
	// LastSeconds reads back from now, for "it just happened" when no mark was
	// taken beforehand.
	LastSeconds *float64 `json:"lastSeconds,omitempty"`
	CommandID   *int     `json:"commandId,omitempty"`
	Windows     int      `json:"windows,omitempty"`
	MinLevel    *string  `json:"minLevel,omitempty"`
	Contains    []string `json:"contains,omitempty"`
	Exclude     []string `json:"exclude,omitempty"`
	Fields      []string `json:"fields,omitempty"`
	MaxEntries  int      `json:"maxEntries,omitempty"`
}

// LogSliceResult is the domain shape of a getLog response (specs 0020, 0021).
type LogSliceResult struct {
	Text      string `json:"text"`
	Entries   int    `json:"entries"`
	Matched   int    `json:"matched"`
	Truncated bool   `json:"truncated"`
	// NextPosition is the journal's position after this read; pass it back as
	// SincePosition to continue the tail with no gap and no repeat.
	NextPosition int `json:"nextPosition"`
	// Nil when the slice was anchored by position or time: such a read spans
	// whatever commands happen to fall in it and is attributable to none. A
	// pointer rather than a zero, because command id 0 is a real id.
	FromCommandID *int `json:"fromCommandId,omitempty"`
	ToCommandID   *int `json:"toCommandId,omitempty"`
	// CapturedAtLevel is EXACT for a command anchor -- a span has one level by
	// construction, since setLogLevel is itself a command and opens a new span --
	// but APPROXIMATE for a position or time anchor, which may straddle one. It
	// then reports the level currently in force.
	CapturedAtLevel string `json:"capturedAtLevel"`
}

// LogPosition is the journal's current mark: the programmatic F1 ritual.
//
// Returned by GetLogPosition, which reads no records at all -- paying for a slice
// to learn one integer defeats the purpose of marking the moment you start
// observing (spec 0021).
type LogPosition struct {
	Position int `json:"position"`
	// Time is wall clock, for lining a mark up against the session transcript and
	// against the human's "around then" without a format negotiation.
	Time string `json:"time"`
}

// LogWait asks the reader to block until a matching log record appears.
type LogWait struct {
	// Timeout is how long to wait. Zero means the bridge's own default.
	Timeout time.Duration
	// MinLevel drops records below this level; nil matches any level.
	MinLevel *string
	// Contains keeps only records whose message holds one of these substrings.
	Contains []string
}

// LogMatch is the outcome of a wait. A wait that expires is an ANSWER, not a
// fault -- "nothing went wrong in those thirty seconds" is exactly what an agent
// asked -- so Found reports it rather than an error.
type LogMatch struct {
	Found bool
	// Position is one past the match, so it feeds straight back in as the next
	// SincePosition. On a miss it is the journal's current position, which is
	// still a usable "from here" mark.
	Position int
	// Text is the matching record, formatted; empty when nothing matched.
	Text string
}

// LogLevelResult is the domain shape of a setLogLevel response (spec 0020).
type LogLevelResult struct {
	Level    string `json:"level"`
	Previous string `json:"previous"`
}

// LogReader is everything the `log` capability can be asked.
type LogReader interface {
	// GetLog returns a filtered, formatted slice of the reader's diagnostic log.
	GetLog(params GetLogParams) (LogSliceResult, error)

	// SetLogLevel raises or lowers the reader's logging floor for the rest of
	// the session. Forwards only -- records never emitted cannot be recovered.
	SetLogLevel(level string) (LogLevelResult, error)

	// LogPosition marks the present: the journal's current position and the wall
	// clock, and no records.
	LogPosition() (LogPosition, error)

	// WaitForLog blocks until a matching record lands or the timeout elapses.
	WaitForLog(wait LogWait) (LogMatch, error)
}
