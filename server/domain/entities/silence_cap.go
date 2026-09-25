// screenreader-mcp domain -- SilenceCap: what the reader's machine does about silence.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, the bridge's silence-cap policy as received at `hello`, plus the sentence an agent is given about it.
// BUILT BY: adapters/bridge/handshake.go, from the wire's SilenceCapInfo.
// READ BY: the connect_reader tool, which states it in its result.
//
// Read-only: no command in this server may change it, or an agent could raise its own ceiling.
package entities

import "fmt"

type SilenceCap struct {
	Enabled bool

	WarnAfter float64

	// LiftAfter is in seconds; capture is unaffected when it lifts.
	LiftAfter float64
}

// Sentence infers attendance from the cap only when `attended` is nil.
func (c *SilenceCap) Sentence(attended *bool) string {
	if attended == nil {
		return c.inferredSentence()
	}
	if !*attended {
		return sentenceUnattended
	}
	if c != nil && c.Enabled {
		return c.cappedSentence()
	}
	return sentenceAttendedUncapped
}

// inferredSentence is a guess for bridges that do not declare attendance, and
// must never be reached when the bridge did declare.
func (c *SilenceCap) inferredSentence() string {
	if c == nil {
		return "This reader did not say whether it bounds how long a silent session may " +
			"keep its human unable to hear. Assume it does not, and narrate anyway."
	}
	if !c.Enabled {
		return sentenceUnattended
	}
	return c.cappedSentence()
}

func (c *SilenceCap) cappedSentence() string {
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

const (
	sentenceUnattended = "This machine is configured as UNATTENDED: nobody is expected to be " +
		"listening, and nothing will interrupt a silent session to restore speech. " +
		"Do not spend round trips narrating to an empty room."

	sentenceAttendedUncapped = "A HUMAN IS EXPECTED AT THIS MACHINE, and it does NOT bound how long a " +
		"silent session may keep them unable to hear: nothing will interrupt the " +
		"session to restore speech, however long you work. They hear only what you " +
		"deliberately say to them, so announce before any stretch of work that does " +
		"not drive the reader."
)
