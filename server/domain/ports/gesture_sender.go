// screenreader-mcp domain -- the GestureSender port (the `gestures` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. The `gestures` capability group (protocol.md §4).
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: 10b's press_gesture tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `gestures`.
package ports

// GesturePress is one dispatched gesture and the slice of the speech ring it is
// credited with: the half-open range [SpeechFrom, SpeechTo).
//
// An EMPTY range is the useful case as often as not -- it is how a silent key
// becomes visible instead of inferred, which a batched {"pressed": ["h","h","h"]}
// could not express at all. Attribution is by DISPATCH-TIME COORDINATE, not by
// causation (spec 0025): speech caused by gesture n can land after gesture n+1
// went out and is then credited to n+1, so the reliable readings are the
// aggregate window and "this key's span was empty".
type GesturePress struct {
	Gesture    string
	SpeechFrom int
	SpeechTo   int
}

// Observation is what a mutating call saw within its grace window.
//
// THE CONTRACT IS ONE SENTENCE (spec 0025, protocol.md §7.3): it says what had
// arrived by a stated instant, and where to resume. It never says that is all
// there is. That is why there is no Complete or Finished field here and will not
// be one -- an empty Speech means "nothing had arrived by then", a fact, not
// "nothing happened", a claim no bridge can support. The caller resumes from
// ToIndex.
type Observation struct {
	Speech    []SpeechEntry
	FromIndex int
	ToIndex   int
	// State is the reader's mode-state sampled at the CLOSE of the window --
	// getState's four fields, deliberately NOT focus information. A browse/focus
	// toggle is synchronous with the script that performed it and already
	// complete here, and is the one thing a silent session cannot hear; focus
	// movement is asynchronous, so a sample taken now reports the place the user
	// LEFT (spec 0023, upheld by 0025). Nil when the reader serves no `state`.
	State *ReaderState
}

// GestureOutcome is an Observation plus which key is credited with what.
type GestureOutcome struct {
	Observation
	Pressed []GesturePress
}

// TypeOutcome is an Observation plus how much was sent. Typed is a LENGTH, never
// the text: typing is exactly how a secret would be entered (spec 0019).
type TypeOutcome struct {
	Observation
	Typed int
}

// GestureSender presses reader gestures.
type GestureSender interface {
	// PressGestures presses the given gesture ids in order, blocking until
	// each has been processed, then reports what was said.
	//
	// The ids are OPAQUE (spec 0005 principle 3): `kb:NVDA+f7` means
	// something to NVDA and to the agent, and nothing to this server, which
	// routes the string without interpreting it. That is what keeps the
	// chassis reader-agnostic -- a JAWS gesture vocabulary needs no code
	// change here.
	//
	// graceMs is how long the reader waits after EACH key for the speech it
	// caused; 0 opts out. announce is spoken to the human at the reader before
	// anything is dispatched, and rides along here rather than costing a call of
	// its own -- the thing that protects a mute tester must not be the thing
	// that costs the most (spec 0025).
	PressGestures(ids []string, graceMs int, announce string) (GestureOutcome, error)
}
