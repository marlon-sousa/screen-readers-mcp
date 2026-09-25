// screenreader-mcp domain -- ReaderGuidanceDocument: the reader's own account.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, one session's reader-supplied guidance plus whose account it is and what persona it answers for.
// BUILT BY: adapters/bridge/handshake.go from the `hello` reply, or controllers/reader_guidance.go from a `getGuidance` round trip.
// READ BY: controllers/reader_guidance.go, and through it screenreader://reader-guidance and connect_reader's result.
//
// The text is opaque: this server frames it and must never parse it.
package entities

type ReaderGuidanceDocument struct {
	Reader string

	Persona Persona

	// Recognised is false when the bridge had no section for that persona, and
	// Text is then its general guidance, not a failure.
	Recognised bool

	Text string
}
