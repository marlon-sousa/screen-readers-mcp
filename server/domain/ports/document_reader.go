// screenreader-mcp domain -- the DocumentReader port (the `document` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. The `document` capability group (protocol.md §4).
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_document_snapshot tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `document`.
//
// Why this group exists (spec 0026, board entry 11.13): reading a page line by
// line costs one round trip PER LINE, and that is where the 2026-08-03 run died
// -- it reached a results page and never got the three titles. Nothing else in
// this protocol reduces the NUMBER of steps; spec 0025 made a step cheaper,
// which is a different problem.
//
// A reader that renders no flat document simply does not announce the group, and
// this port is never handed out. A reader that does, but is not in one right now,
// answers HasDocument false -- an ordinary fact an agent branches on, never an
// error.
package ports

// SnapshotLine is one line of the document, as the reader renders it.
//
// The line carries its own ordinal because the coordinate is most of the value:
// it is what lets an agent say "the third result is at line 14" and act from
// there. Ordinals are ABSOLUTE -- line 14 is line 14 whether or not the read
// started at 0.
type SnapshotLine struct {
	Line int
	Text string
}

// DocumentSnapshot is the reader's flat document at one instant.
//
// CapturedAt is not decoration. This is a still frame, and whatever the document
// did afterwards is not in here; nothing in the shape can say whether it did
// anything. It is the reader's own wall clock, in the format the reader stamps
// its log with, so an agent can join a snapshot to what it heard.
type DocumentSnapshot struct {
	// HasDocument is false for a dialog, a native application, the desktop --
	// which is a real answer and NOT an empty document. Collapsing the two
	// sends an agent in opposite directions.
	HasDocument bool
	CapturedAt  string
	Title       string
	Lines       []SnapshotLine
	FromLine    int
	ToLine      int
	// TruncatedBy is "none", "maxLines" or "maxChars" -- a closed value set
	// with no null, so `if truncatedBy == ""` cannot be how a caller asks
	// (spec 0015's doctrine, spec 0026's application of it).
	TruncatedBy string
}

// DocumentBounds is what the caller asked for. Zero means NO limit, for both
// caps, and the zero value of this struct is therefore "the whole document" --
// which is the ordinary call.
type DocumentBounds struct {
	FromLine int
	MaxLines int
	MaxChars int
}

// DocumentReader hands over the reader's flat document rendering, whole.
type DocumentReader interface {
	Snapshot(bounds DocumentBounds) (DocumentSnapshot, error)
}
