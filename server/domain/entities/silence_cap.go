// screenreader-mcp domain -- SilenceCap: what the reader's machine does about silence.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. The bridge's silence-cap policy as received at `hello`, plus the
// sentence an agent is given about it.
// BUILT BY: adapters/bridge/handshake.go, mapping the wire's SilenceCapInfo into
// domain vocabulary.
// READ BY: the connect_reader tool, which states it in its result.
//
// Spec 0032. READ-ONLY THROUGHOUT, and that is the design rather than an
// omission: whether a silence is bounded is a property of the machine the reader
// runs on, set on that machine, and there is no command anywhere in this server
// that changes it. An agent that could raise its own ceiling does not have one.
//
// It earns its place in the connect result because it changes what a well-behaved
// agent does. On a capped machine, narrate before any stretch of work that does
// not drive the reader -- the narration resets the clock, so a narrating agent
// never meets the cap at all. On an uncapped one, do not spend round trips
// narrating to a room nobody is in. Without this an agent cannot tell those two
// situations apart, and must either narrate uselessly forever or guess.
package entities

import "fmt"

// SilenceCap is a reader's answer to "do you bound how long you may keep your
// human unable to hear you, and by how much?".
//
// A POINTER is what travels on the session, and nil is a third answer, distinct
// from both booleans: this bridge did not say. That is an older build rather than
// an uncapped machine, and reporting it as "uncapped" would tell an agent it may
// go quiet on a machine that has no idea what quiet costs.
type SilenceCap struct {
	// Enabled is whether the cap runs on this machine at all.
	Enabled bool

	// WarnAfter is how long a silence runs before the reader warns its human,
	// in seconds.
	WarnAfter float64

	// LiftAfter is how long it runs before the reader stops suppressing, in
	// seconds. Capture is unaffected -- the agent keeps every entry, every
	// index and every timestamp; what changes is that the words also reach
	// the speakers.
	LiftAfter float64
}

// Sentence is what an agent is told, in one line it can act on.
//
// Rendered here rather than in the tool, for Persona.Stance's reason: a DOMAIN
// controller needs it (connect_reader puts it in the result) and the domain may
// not import an adapter. It names no tool of this server, because the reader
// bounding the silence has no idea which client is driving it -- what it names is
// the behaviour, and every client's word for "say something to the human" is the
// same `announce`.
func (c *SilenceCap) Sentence() string {
	if c == nil {
		return "This reader did not say whether it bounds how long a silent session may " +
			"keep its human unable to hear. Assume it does not, and narrate anyway."
	}
	if !c.Enabled {
		return "This machine is configured as UNATTENDED: nobody is expected to be " +
			"listening, and nothing will interrupt a silent session to restore speech. " +
			"Do not spend round trips narrating to an empty room."
	}
	return fmt.Sprintf(
		"A HUMAN IS EXPECTED AT THIS MACHINE. In a silent session they hear nothing "+
			"except what you deliberately say to them, so this reader measures how long "+
			"that has been: it warns them after %.0fs of hearing nothing from you, and "+
			"after %.0fs it stops suppressing speech altogether (your capture is "+
			"unaffected -- get_speech still returns everything). Announce before any "+
			"stretch of work that does not drive the reader, and you will never meet it.",
		c.WarnAfter, c.LiftAfter,
	)
}
