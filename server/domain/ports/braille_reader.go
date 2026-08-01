// screenreader-mcp domain -- the BrailleReader port (the `braille` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. The `braille` capability group (protocol.md §4).
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: 10b's get_braille tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `braille`.
//
// This port is the clearest argument for splitting by capability group rather
// than one fat BridgeClient: a reader without braille is expressible as a
// collaborator that was never handed over. With one wide interface, BrailleSince
// would exist for every reader alive and the absence would survive only as a
// runtime check somebody has to remember to write.
package ports

// BrailleEntry is one braille update, placed on the log journal's timeline.
//
// The braille counterpart of SpeechEntry, for the same reason: the braille ring
// is index-addressed and dies at teardown, so joining it to the log needs a
// shared coordinate (spec 0021). It matters more here than for speech, because
// get_braille is the ONLY braille fetch -- there is no get_last_braille -- so
// this is the sole route to a braille entry's coordinate.
type BrailleEntry struct {
	Text string
	// Index is this entry's place in the braille ring (the sinceIndex space).
	Index int
	// LogPosition is the journal position when it was captured (the get_log space).
	LogPosition int
}

// BrailleRange is a half-open window of captured braille: [FromIndex, ToIndex).
// Its own type rather than a shared one with speech: they are separate logs with
// separate indices, and a function that accepts either would be a function that
// can be handed the wrong one.
type BrailleRange struct {
	Entries   []BrailleEntry
	FromIndex int
	ToIndex   int
}

// BrailleReader is everything the `braille` capability can be asked.
type BrailleReader interface {
	// BrailleSince returns captured braille from sinceIndex onward.
	BrailleSince(sinceIndex int) (BrailleRange, error)
}
