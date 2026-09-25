// screenreader-mcp domain -- the GuidanceReader port (the `guidance` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, the `guidance` capability group: the reader's own persona vocabulary.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: domain/controllers/reader_guidance.go, which caches the answer for the session.
// HANDED OUT BY: the handshake, only when the reader announced `guidance`.

package ports

// ReaderGuidance text is opaque: this server must never parse it.
type ReaderGuidance struct {
	Persona string

	// Recognised false means Text is the bridge's general guidance, not a failure.
	Recognised bool

	Text string
}

type GuidanceReader interface {
	// Guidance takes no persona: the session's was fixed at `hello`.
	Guidance() (ReaderGuidance, error)
}
