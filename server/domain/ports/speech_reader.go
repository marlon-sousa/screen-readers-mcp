// screenreader-mcp domain -- the SpeechReader port (the `speech` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `speech` capability group.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the speech tool controllers.
// HANDED OUT BY: the handshake, only when the reader announced `speech`.
package ports

import "time"

type SpeechEntry struct {
	Text        string
	Index       int
	LogPosition int
	// EmittedAt is "YYYY-MM-DD HH:MM:SS.mmm" when the reader emitted the
	// utterance, which in live mode can be seconds before it is heard; empty
	// when the reader did not supply one.
	EmittedAt string
}

// SpeechRange Entries omits utterances that rendered empty, so len(Entries) is
// not ToIndex - FromIndex; use each entry's Index. ToIndex is the next sinceIndex.
type SpeechRange struct {
	Entries   []SpeechEntry
	FromIndex int
	ToIndex   int
}

type LastSpeech struct {
	Text  string
	Index int
	// LogPosition is 0 for the empty sentinel.
	LogPosition int
	// EmittedAt is empty for the sentinel.
	EmittedAt string
}

type SpeechWait struct {
	Text string

	// AfterIndex nil means anywhere in what has been captured, which the wire
	// distinguishes from 0.
	AfterIndex *int

	// Timeout zero means the bridge's own default.
	Timeout time.Duration
}

type SpeechMatch struct {
	Found bool
	Index int
	Text  string
	// LogPosition on a miss is the journal's current position.
	LogPosition int
	// EmittedAt is empty on a miss.
	EmittedAt string
}

type SpeechReader interface {
	SpeechSince(sinceIndex int) (SpeechRange, error)

	LastSpeech() (LastSpeech, error)

	NextSpeechIndex() (int, error)

	WaitForSpeech(wait SpeechWait) (SpeechMatch, error)

	// WaitForSpeechToFinish's bool reports whether speech settled; a zero timeout
	// means the bridge's own default.
	WaitForSpeechToFinish(timeout time.Duration) (bool, error)
}
