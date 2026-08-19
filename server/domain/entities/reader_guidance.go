// screenreader-mcp domain -- ReaderGuidanceDocument: the reader's own account.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. One session's reader-supplied guidance, plus the facts a frame
// around it needs: whose account this is, and what it answers for.
// BUILT BY: adapters/bridge/handshake.go, from the `hello` reply (spec 0022
// A.5), or by controllers/reader_guidance.go from a `getGuidance` round trip
// when talking to a bridge that predates the handshake field.
// READ BY: controllers/reader_guidance.go and, through it, the
// screenreader://reader-guidance resource and connect_reader's result.
//
// IT LIVES IN entities RATHER THAN BESIDE ITS CONTROLLER because a port now
// carries it: ReaderConnection holds the document the handshake delivered, and
// ports may not import controllers. The controller keeps an alias, so the name
// callers already use still resolves.
//
// THE TEXT IS OPAQUE. This server transports and frames it and never parses it,
// which is what lets a bridge author write for their own reader without
// negotiating a schema -- and why a TalkBack bridge can enumerate swipes where
// NVDA's enumerates keystrokes.
package entities

// ReaderGuidanceDocument is one session's reader-supplied guidance.
type ReaderGuidanceDocument struct {
	// Reader is the name the bridge announced, so a frame can say whose
	// account the agent is reading.
	Reader string

	// Persona is what the bridge answered for, as it echoed it back.
	Persona Persona

	// Recognised is false when the bridge had no section for that persona.
	// A false with general text is a real answer, not a failure: silence
	// would leave an agent believing it had been instructed when it had not.
	Recognised bool

	// Text is the bridge's markdown, untouched.
	Text string
}
