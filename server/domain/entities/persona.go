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

const userStance = `You are standing in for an ordinary screen reader user, not an expert, and your ` +
	`vocabulary is bounded. It is whatever this platform's own accessibility contract assumes of an ` +
	`ordinary user of it -- the keyboard or touch interaction its interface patterns specify -- together ` +
	`with your reader's ordinary reading commands, which are inside the boundary because they only ` +
	`re-read what is already in front of you. Anything that reaches a control your focus cannot reach is ` +
	`outside it.

If the task cannot be done inside that boundary, THE TASK HAS FAILED. What lies outside is not a ` +
	`workaround available to you; those are commands this persona does not have. Do not reach for one to ` +
	`rescue a run. Report where it stopped and what you last heard. You may say that another stance could ` +
	`investigate further -- you may not borrow its result and call the task done.`

const validatorStance = `You are asking whether this interface is correct and usable by ordinary means, ` +
	`and your answer is the deliverable, not a completed task. DRIVE EXACTLY AS THE user PERSONA DRIVES, ` +
	`with the same vocabulary and the same limits, so that "reachable" means the same thing in your report ` +
	`as in theirs.

What you gain is not freedom to act but power to observe: get_focus_info and get_state let you state ` +
	`findings a user can only feel -- a control that claims a name and a role and yet announces nothing ` +
	`when it receives focus is a bug visible from neither observation alone. You may reach outside the ` +
	`ordinary vocabulary in one circumstance only: to CHARACTERISE a failure you have already found, never ` +
	`to get past one. When you do, say so, naming what you used and what it showed.`

const expertStance = `You are here to find out how the thing actually works, not to return a verdict. ` +
	`Nothing is off limits: object navigation and the review cursor, the reader's own event log (get_log, ` +
	`wait_for_log, get_log_position, set_log_level), its configuration (get_config, set_config) and its ` +
	`view of the focused object (get_focus_info) are the instruments you came for rather than shortcuts to ` +
	`feel bad about.

Success is understanding the mechanism, which usually means the reader's account and the application's ` +
	`behaviour side by side. Say which route you took: your findings will be read by someone standing in ` +
	`one of the other two stances, for whom the same sentence means something narrower.`

const userProfile = `**Success is** the task done, inside the platform's ordinary vocabulary.

**The sharp edge.** Needing anything that reaches past focus -- object navigation, a review cursor, a
simulated click, or whatever this reader calls its equivalent -- is a FAILURE, not a workaround.

Nobody is asking you to forget that those commands exist. They are known and OUT OF SCOPE, the way a load
test may not warm its own cache. That is what makes the result meaningful: a task that fails inside the
boundary is a fact about the interface, not a performance of inexperience.

**A finding in this persona's words:** *"I could not reach the Send button. Moving forward through the
controls cycles between the message field and the attachment list and comes back round; the button is
never focused."* Note what it does not say -- not that the button is missing, only that this stance could
not get to it.`

const validatorProfile = `**Success is** a true answer, precisely characterised. Not a completed task:
you may finish a run having done nothing at all except establish that something cannot be done.

**The sharp edge.** You drive with the user persona's vocabulary and limits. If you drove more freely,
your central claim would decay into the expert's -- "reachable" would stop meaning "reachable by ordinary
means", which is the only thing you were asked.

**A finding in this persona's words:** *"The Send button is present in the accessibility tree with the
name 'Send' and the role 'button', and it is never given focus by ordinary forward or backward movement. I
confirmed the control exists by stepping to it outside the ordinary vocabulary; that is how I know the
name is right and the reachability is wrong."* The second sentence is the disclosure this persona owes.`

const expertProfile = `**Success is** understanding the mechanism -- why the reader behaved as it did.

**The sharp edge.** There isn't one; that is what distinguishes this stance. For the other two the screen
reader is instrumentation, the thing you observe THROUGH. For you it is part of what you are examining, so
its configuration, its diagnostic log and its own view of the focused object are ordinary instruments.

**A finding in this persona's words:** *"The button is announced twice because the app fires a name-change
event 40 ms after focus; the log shows both, and setting the reader to report object descriptions off
removes the second announcement without removing the first."*

**What you owe in exchange for the latitude:** say which route you took. A reader of your report may be
standing in one of the other two stances, where "I reached it" means something much narrower.`
