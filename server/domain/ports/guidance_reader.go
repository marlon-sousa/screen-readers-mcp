// screenreader-mcp domain -- the GuidanceReader port (the `guidance` capability).
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. The `guidance` capability group (spec 0029 Part 4): the one
// command, getGuidance, that asks the READER what its own persona vocabulary is.
// IMPLEMENTED BY: adapters/bridge/json_lines_client.go.
// USED BY: domain/controllers/reader_guidance.go, which caches the answer for
// the session and hands it to the screenreader://reader-guidance resource.
// HANDED OUT BY: the handshake, only when the reader announced `guidance`.
//
// WHY THIS PORT EXISTS AT ALL, when the server already publishes a guidance
// document of its own: that one can only state the RULE. The instances are
// keystrokes on NVDA and touch gestures on TalkBack, and this server does not
// know which reader it is driving until `hello` answers -- so the concrete half
// has to come from the bridge, which ships with the reader it describes.

package ports

// ReaderGuidance is one bridge's answer about one persona.
//
// The TEXT IS OPAQUE and this server never parses it. That is what lets a bridge
// author write for their own reader without negotiating a schema with anybody:
// the server transports it, frames it with the precedence rule, and forms no
// opinion about its contents. The cost is that a bridge's document can be wrong
// or stale and nothing upstream can tell -- which is stated in the spec's honest
// limits rather than papered over here.
type ReaderGuidance struct {
	// Persona is the value the bridge answered for, echoed as it received it.
	Persona string

	// Recognised is whether the bridge had persona-specific instruction for
	// that value. False is a real answer, not a failure: a newer server's
	// fourth persona meeting an older bridge gets the bridge's general text and
	// is told that is what happened, which is the designed degrade
	// (protocol.md §4). Silence would leave an agent believing it had been
	// instructed when it had not.
	Recognised bool

	// Text is the document, as markdown.
	Text string
}

// GuidanceReader is everything the `guidance` capability can be asked.
type GuidanceReader interface {
	// Guidance returns the bridge's own instruction for THIS session's persona.
	//
	// It takes no argument, and that is a decision rather than an omission: the
	// persona was fixed at `hello`, so asking for another one would let an agent
	// consult a stance it is not standing in.
	Guidance() (ReaderGuidance, error)
}
