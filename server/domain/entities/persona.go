// screenreader-mcp domain -- Persona: what a session is standing in for.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. The stance a session declares at connect_reader, fixed for the
// session's lifetime, and the two texts that say what it means.
// BUILT BY: the agent, through connect_reader's `persona` parameter; carried in
// ports.SessionOptions and recorded on the ReaderSession.
// READ BY: connect_reader (Stance, in the result), the guidance resource
// (Profile, composed into the document), status and screenreader://info.
//
// Spec 0029. Its own type rather than a bare string for CaptureMode's reason: an
// unknown value fails at the tool boundary with a listing of what is valid,
// instead of travelling to a bridge to be rejected there.
//
// WHY THE TEXTS LIVE HERE, and not in adapters/mcp beside the guidance document
// they end up in: a DOMAIN controller needs one of them (connect_reader renders
// Stance into its result) and the domain may not import an adapter. Keying both
// off the enum also makes "add a persona without saying what it means" a
// compile error rather than something review has to catch.
//
// WHAT THESE TEXTS MUST NEVER CONTAIN is a keystroke. The ordinary vocabulary is
// the PLATFORM's, and this server does not know which platform it is driving
// until `hello` answers -- TalkBack has no keyboard and no Windows, so a list
// naming Tab or Alt+Down would be instructions that do not exist on the reader
// in front of the agent. This file states the RULE; the bridge's own document
// (spec 0029 Part 4, board entry 11.20) enumerates the instances.
package entities

import (
	_ "embed"
	"fmt"
	"strings"
)

// Persona is `user`, `validator` or `expert`.
type Persona string

const (
	// PersonaUser stands in for an ordinary, non-expert screen reader user.
	// Its vocabulary is bounded, and needing more is a failed task.
	PersonaUser Persona = "user"

	// PersonaValidator asks whether an interface is usable by ordinary means.
	// It drives exactly as PersonaUser drives; what it gains is observation.
	PersonaValidator Persona = "validator"

	// PersonaExpert is taking the mechanism apart. Nothing is off limits,
	// because what it owes is understanding rather than a verdict.
	PersonaExpert Persona = "expert"
)

// String is the wire spelling, which is also what an agent passes.
func (p Persona) String() string { return string(p) }

// AllPersonas is every persona, in the order they are presented to an agent --
// which is the order of increasing latitude, so the list reads as an argument
// rather than as an alphabetised set.
//
// Everything that enumerates personas goes through this: the guidance document
// composes its profiles from it, ParsePersona builds its error from it, and the
// tests assert that every member has both texts. Adding a persona is therefore
// one edit to this file.
func AllPersonas() []Persona {
	return []Persona{PersonaUser, PersonaValidator, PersonaExpert}
}

// ParsePersona validates a persona chosen by an agent.
//
// The error lists all three WITH the question each one asks, because a wrong
// guess should self-correct in the same turn rather than cost a round trip --
// and because for most agents this error is the first place personas are
// explained at all.
func ParsePersona(value string) (Persona, error) {
	for _, persona := range AllPersonas() {
		if Persona(value) == persona {
			return persona, nil
		}
	}

	choices := make([]string, 0, len(AllPersonas()))
	for _, persona := range AllPersonas() {
		choices = append(choices, fmt.Sprintf("%q (%s)", persona, persona.Question()))
	}
	return "", fmt.Errorf("persona %q: want one of %s", value, strings.Join(choices, ", "))
}

// Question is the one-line form: what this persona is asking. Used in the
// parse error and as each profile's heading.
func (p Persona) Question() string {
	switch p {
	case PersonaUser:
		return "can I do this?"
	case PersonaValidator:
		return "is this right?"
	case PersonaExpert:
		return "how does this actually work?"
	}
	return ""
}

// Stance is the short form, returned by connect_reader.
//
// Connect is the one moment an agent is guaranteed to be reading, and the first
// external run (spec 0027) is the evidence that a resource nobody points at goes
// unread. Short rather than the whole profile: text repeated in every result is
// text paid for on every reconnect.
func (p Persona) Stance() string {
	switch p {
	case PersonaUser:
		return userStance
	case PersonaValidator:
		return validatorStance
	case PersonaExpert:
		return expertStance
	}
	return ""
}

// Profile is the longer form, composed into screenreader://guidance so a persona
// can be chosen -- and put to the human for confirmation -- before connecting.
func (p Persona) Profile() string {
	switch p {
	case PersonaUser:
		return userProfile
	case PersonaValidator:
		return validatorProfile
	case PersonaExpert:
		return expertProfile
	}
	return ""
}

// The texts, as MARKDOWN FILES rather than Go string literals.
//
// They are documents: prose an agent reads, revised the way prose is revised.
// As `const` blocks they were 21 concatenation continuations, every code span
// had to break out of its raw string, and a diff on a reworded sentence was
// unreadable. //go:embed makes each one an ordinary .md file that an editor
// wraps, spell-checks and diffs, and the compiler still fails if one is missing
// -- which is the property Stance() and Profile() rely on.
//
// One var per file, deliberately, rather than an embed.FS keyed by name: a
// missing file is then a COMPILE error rather than an empty string discovered
// at runtime. That is the same guarantee the switch statements above give, kept
// rather than traded away for a shorter file.

//go:embed documents/user-stance.md
var userStance string

//go:embed documents/validator-stance.md
var validatorStance string

//go:embed documents/expert-stance.md
var expertStance string

//go:embed documents/user-profile.md
var userProfile string

//go:embed documents/validator-profile.md
var validatorProfile string

//go:embed documents/expert-profile.md
var expertProfile string
