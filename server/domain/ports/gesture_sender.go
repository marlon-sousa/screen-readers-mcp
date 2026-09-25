// screenreader-mcp domain -- the GestureSender port (the `gestures` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `gestures` capability group.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the press_gesture tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `gestures`.
package ports

// GesturePress credits speech by dispatch-time coordinate, not causation, so
// speech caused by one key can land in the next key's range [SpeechFrom, SpeechTo).
type GesturePress struct {
	Gesture    string
	SpeechFrom int
	SpeechTo   int
}

// Observation says what had arrived by the window's close and where to resume;
// an empty Speech never means nothing happened.
type Observation struct {
	Speech    []SpeechEntry
	FromIndex int
	ToIndex   int
	// State is sampled at the close of the window; nil when the reader serves no `state`.
	State *ReaderState
}

type GestureOutcome struct {
	Observation
	Pressed []GesturePress
}

// TypeOutcome carries a length, never the text, because typing is how a secret is entered.
type TypeOutcome struct {
	Observation
	Typed int
}

type GestureSender interface {
	// PressGestures treats ids as opaque. graceMs is the wait after each key for
	// its speech, 0 to opt out; announce is spoken to the human before dispatch.
	PressGestures(ids []string, graceMs int, announce string) (GestureOutcome, error)
}
