// screenreader-mcp domain -- the SpeechReader port (the `speech` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. One capability GROUP, not one command -- protocol.md §4
// groups these five commands under `speech`, and the port set mirrors the
// capability set exactly so a missing capability is a missing collaborator.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: 10b's speech tool controllers, one controller per tool.
// HANDED OUT BY: the handshake, which sets this port on the ReaderConnection
// only when the reader announced `speech` -- so a reader without it produces a
// nil collaborator rather than a runtime check.
//
// Its DTOs live in this file, per AGENTS.md: a port's own types belong with the
// port. They are domain vocabulary; adapters/bridge maps them to and from the
// generated wire structs.
package ports

import "time"

// SpeechEntry is one captured utterance, placed on the log journal's timeline.
//
// LogPosition is the journal's append position at the moment this sequence was
// captured (spec 0021), and it is why this is a list rather than the joined blob
// it used to be: three Down-arrow presses produce three utterances, so whichever
// one's coordinate a single string carried, the other two had none. It matters
// most in a SILENT session, where the bridge suppresses speech before NVDA
// reaches its own "Speaking" log line, so the journal holds no speech record at
// all -- the coordinate still points at the events that surrounded the utterance.
type SpeechEntry struct {
	Text string
	// Index is this entry's place in the speech ring (the sinceIndex space).
	Index int
	// LogPosition is the journal position when it was captured (the get_log space).
	LogPosition int
	// EmittedAt is wall clock at the moment the reader EMITTED this utterance,
	// as "YYYY-MM-DD HH:MM:SS.mmm" -- the shape getLogPosition returns and the
	// session transcript writes, so it can be pasted into a search of the
	// reader's own log (spec 0028).
	//
	// Emitted, NOT heard: live mode captures at the point the sequence is queued
	// for the synth, so an utterance behind a long one can be seconds from
	// audible. Right for "did the application respond promptly", wrong for "when
	// did the user hear it". Empty when the reader did not supply one.
	EmittedAt string
}

// SpeechRange is a half-open window of captured speech: [FromIndex, ToIndex).
// ToIndex is exactly the sinceIndex to pass next, with no overlap and no gap
// (protocol.md §7).
//
// Entries omits utterances that rendered empty, so len(Entries) is NOT
// ToIndex - FromIndex and entry i is not at index FromIndex + i. That mismatch is
// exactly why each entry carries its own Index.
type SpeechRange struct {
	Entries   []SpeechEntry
	FromIndex int
	ToIndex   int
}

// LastSpeech is the most recent captured utterance and the index it occupies.
type LastSpeech struct {
	Text  string
	Index int
	// LogPosition places it on the journal's timeline; 0 for the empty sentinel.
	LogPosition int
	// EmittedAt is when the reader emitted it; see SpeechEntry. Empty for the
	// sentinel, which was never emitted.
	EmittedAt string
}

// SpeechWait asks the reader to block until matching speech appears.
type SpeechWait struct {
	// Text is what to wait for.
	Text string

	// AfterIndex restricts the match to items at or after that index. Nil
	// means "anywhere in what has been captured", which is a different
	// question from "at or after 0" only in intent -- but the wire
	// distinguishes them, so the domain does too.
	AfterIndex *int

	// Timeout is how long to wait. Zero means the bridge's own default.
	Timeout time.Duration
}

// SpeechMatch is the outcome of a wait. Found says whether the text appeared;
// Index and Text describe the match when it did.
type SpeechMatch struct {
	Found bool
	Index int
	Text  string
	// LogPosition is the journal position of the match -- the coordinate for
	// "show me what the reader was doing when it said that". On a miss it is the
	// journal's CURRENT position, so it is still a usable "from here" mark, the
	// same convention Index already follows (spec 0021).
	LogPosition int
	// EmittedAt is when the match was emitted; see SpeechEntry. Empty on a miss:
	// Index and LogPosition stay useful as a "from here" mark, but there is no
	// instant to report for speech that never arrived (spec 0028).
	EmittedAt string
}

// SpeechReader is everything the `speech` capability can be asked.
type SpeechReader interface {
	// SpeechSince returns captured speech from sinceIndex onward.
	SpeechSince(sinceIndex int) (SpeechRange, error)

	// LastSpeech returns the most recent utterance.
	LastSpeech() (LastSpeech, error)

	// NextSpeechIndex returns the index the next captured item will take, so
	// a caller can note "now", act, and then read only what its action
	// produced.
	NextSpeechIndex() (int, error)

	// WaitForSpeech blocks until the text appears or the timeout elapses.
	WaitForSpeech(wait SpeechWait) (SpeechMatch, error)

	// WaitForSpeechToFinish blocks until speech settles or the timeout
	// elapses; the bool reports which. A zero timeout means the bridge's own
	// default.
	WaitForSpeechToFinish(timeout time.Duration) (bool, error)
}
