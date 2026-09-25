// screenreader-mcp domain -- the DocumentReader port (the `document` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `document` capability group.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: the get_document_snapshot tool controller.
// HANDED OUT BY: the handshake, only when the reader announced `document`.
package ports

// SnapshotLine ordinals are absolute, whatever line the read started at.
type SnapshotLine struct {
	Line int
	Text string
}

// DocumentSnapshot.CapturedAt is the reader's own wall clock, in its log's format.
type DocumentSnapshot struct {
	// HasDocument false means no document at all, not an empty one.
	HasDocument bool
	CapturedAt  string
	Title       string
	Lines       []SnapshotLine
	FromLine    int
	ToLine      int
	// TruncatedBy is "none", "maxLines" or "maxChars", never empty.
	TruncatedBy string
}

// DocumentBounds zero means no limit, so the zero value is the whole document.
type DocumentBounds struct {
	FromLine int
	MaxLines int
	MaxChars int
}

type DocumentReader interface {
	Snapshot(bounds DocumentBounds) (DocumentSnapshot, error)
}
