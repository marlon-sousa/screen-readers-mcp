// screenreader-mcp domain -- the LogReader port (the `log` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `log` capability group: every command that reads or configures the reader's diagnostic log.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_log, set_log_level, get_log_position and wait_for_log tool controllers.
// HANDED OUT BY: the handshake, only when the reader announced `log`.

package ports

import "time"

// GetLogParams anchors SincePosition, LastSeconds and CommandID are mutually
// exclusive; the bridge rejects more than one.
type GetLogParams struct {
	// SincePosition consumes nothing, so re-reading from it is idempotent.
	SincePosition *int     `json:"sincePosition,omitempty"`
	LastSeconds   *float64 `json:"lastSeconds,omitempty"`
	CommandID     *int     `json:"commandId,omitempty"`
	Windows       int      `json:"windows,omitempty"`
	MinLevel      *string  `json:"minLevel,omitempty"`
	Contains      []string `json:"contains,omitempty"`
	Exclude       []string `json:"exclude,omitempty"`
	Fields        []string `json:"fields,omitempty"`
	MaxEntries    int      `json:"maxEntries,omitempty"`
}

type LogSliceResult struct {
	Text      string `json:"text"`
	Entries   int    `json:"entries"`
	Matched   int    `json:"matched"`
	Truncated bool   `json:"truncated"`
	// NextPosition fed back as SincePosition continues with no gap and no repeat.
	NextPosition int `json:"nextPosition"`
	// FromCommandID is nil for a position or time anchor; 0 is a real id.
	FromCommandID *int `json:"fromCommandId,omitempty"`
	ToCommandID   *int `json:"toCommandId,omitempty"`
	// CapturedAtLevel is exact for a command anchor and approximate otherwise.
	CapturedAtLevel string `json:"capturedAtLevel"`
}

type LogPosition struct {
	Position int    `json:"position"`
	Time     string `json:"time"`
}

type LogWait struct {
	// Timeout zero means the bridge's own default.
	Timeout time.Duration
	// MinLevel nil matches any level.
	MinLevel *string
	Contains []string
}

// LogMatch.Found false is an answer, not a fault.
type LogMatch struct {
	Found bool
	// Position is one past the match, or the journal's current position on a miss.
	Position int
	// Text is empty when nothing matched.
	Text string
}

type LogLevelResult struct {
	Level    string `json:"level"`
	Previous string `json:"previous"`
}

type LogReader interface {
	GetLog(params GetLogParams) (LogSliceResult, error)

	// SetLogLevel works forwards only; records never emitted cannot be recovered.
	SetLogLevel(level string) (LogLevelResult, error)

	LogPosition() (LogPosition, error)

	WaitForLog(wait LogWait) (LogMatch, error)
}
