// screenreader-mcp domain -- the LogReader port (the `log` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. The `log` capability group (spec 0020), covering getLog and
// setLogLevel -- every command that reads or configures the reader's diagnostic log.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_log and set_log_level tool controllers.
// HANDED OUT BY: the handshake, only when the reader announced `log`.

package ports

// GetLogParams is the domain shape of a getLog request (spec 0020).
type GetLogParams struct {
	CommandID  *int     `json:"commandId,omitempty"`
	Windows    int      `json:"windows,omitempty"`
	MinLevel   *string  `json:"minLevel,omitempty"`
	Contains   []string `json:"contains,omitempty"`
	Exclude    []string `json:"exclude,omitempty"`
	Fields     []string `json:"fields,omitempty"`
	MaxEntries int      `json:"maxEntries,omitempty"`
}

// LogSliceResult is the domain shape of a getLog response (spec 0020).
type LogSliceResult struct {
	Text            string `json:"text"`
	Entries         int    `json:"entries"`
	Matched         int    `json:"matched"`
	Truncated       bool   `json:"truncated"`
	FromCommandID   int    `json:"fromCommandId"`
	ToCommandID     int    `json:"toCommandId"`
	CapturedAtLevel string `json:"capturedAtLevel"`
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
}
