// screenreader-mcp domain -- the BrailleReader port (the `braille` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `braille` capability group.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_braille tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `braille`.
package ports

type BrailleEntry struct {
	Text        string
	Index       int
	LogPosition int
	// EmittedAt is "YYYY-MM-DD HH:MM:SS.mmm"; see ports.SpeechEntry.
	EmittedAt string
}

// BrailleRange is half-open: [FromIndex, ToIndex).
type BrailleRange struct {
	Entries   []BrailleEntry
	FromIndex int
	ToIndex   int
}

type BrailleReader interface {
	BrailleSince(sinceIndex int) (BrailleRange, error)
}
