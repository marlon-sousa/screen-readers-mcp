// screenreader-mcp domain -- the SilenceCap entity's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Spec 0032. The entity is a description plus one sentence, so what is worth
// pinning down is that the sentence says DIFFERENT things in the three cases --
// capped, uncapped, and "this bridge did not say" -- and above all that the
// third is not quietly reported as the second. An agent told "no cap here" goes
// quiet; an agent told "we do not know" narrates anyway, which is the safe
// direction and the whole reason the field is a pointer.
//
// Spec 0035 adds the second axis. Attendance is now DECLARED, so the sentence is
// a function of two facts rather than one, and the table below is the five rows
// that produces. The row that matters most is attended-but-uncapped: it cannot
// be expressed by a wire carrying only the cap, and it is the reason the entry
// exists. The three `attended: nil` rows are the COMPATIBILITY PATH for a bridge
// that predates the field, and they are pinned precisely so a later change
// cannot quietly alter what an older bridge's users are told.
package entities_test

import (
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func TestACappedMachineNamesBothThresholds(t *testing.T) {
	cap := &entities.SilenceCap{Enabled: true, WarnAfter: 45, LiftAfter: 90}
	sentence := cap.Sentence(nil)

	for _, want := range []string{"45s", "90s", "HUMAN IS EXPECTED"} {
		if !strings.Contains(sentence, want) {
			t.Errorf("the sentence does not mention %q: %s", want, sentence)
		}
	}
	// It has to say what to DO, or it is a fact rather than an instruction.
	if !strings.Contains(sentence, "Announce") {
		t.Errorf("the sentence never tells the agent what to do: %s", sentence)
	}
}

func TestAnUnattendedMachineSaysNotToNarrate(t *testing.T) {
	sentence := (&entities.SilenceCap{Enabled: false, WarnAfter: 45, LiftAfter: 90}).Sentence(nil)

	if !strings.Contains(sentence, "UNATTENDED") {
		t.Errorf("an uncapped machine is not named as such: %s", sentence)
	}
	if strings.Contains(sentence, "45") || strings.Contains(sentence, "90") {
		t.Errorf("thresholds quoted for a cap that does not run: %s", sentence)
	}
}

// The distinction the pointer exists for. A bridge that predates the field has
// not told us the machine is uncapped -- it has told us nothing -- and reporting
// silence as permission is exactly the failure this entry is about.
func TestABridgeThatDidNotSayIsNotReportedAsUncapped(t *testing.T) {
	var missing *entities.SilenceCap
	sentence := missing.Sentence(nil)

	if strings.Contains(sentence, "UNATTENDED") {
		t.Errorf("an unknown cap was reported as an unattended machine: %s", sentence)
	}
	if !strings.Contains(sentence, "did not say") {
		t.Errorf("the sentence does not admit it does not know: %s", sentence)
	}
	if !strings.Contains(sentence, "narrate anyway") {
		t.Errorf("the sentence does not steer to the safe side: %s", sentence)
	}
}

// -- spec 0035: attendance is declared -------------------------------------

func attended(v bool) *bool { return &v }

// The row that could not be said before: somebody is at the machine and nothing
// there will give them their speech back. Under the old wire this had to arrive
// as `enabled: false` and be reported as an empty room -- narrate to nobody --
// which is the exact inversion of what this person needs.
func TestAnAttendedMachineWithNoCapIsNotAnEmptyRoom(t *testing.T) {
	uncapped := &entities.SilenceCap{Enabled: false, WarnAfter: 45, LiftAfter: 90}
	sentence := uncapped.Sentence(attended(true))

	if strings.Contains(sentence, "UNATTENDED") {
		t.Errorf("a machine with somebody at it was reported as unattended: %s", sentence)
	}
	if !strings.Contains(sentence, "HUMAN IS EXPECTED") {
		t.Errorf("the sentence does not say a human is there: %s", sentence)
	}
	if !strings.Contains(sentence, "announce") {
		t.Errorf("the sentence never tells the agent to speak to them: %s", sentence)
	}
	// There is no lift coming, so promising one would be a lie in the direction
	// that costs the human their speech.
	if strings.Contains(sentence, "45s") || strings.Contains(sentence, "90s") {
		t.Errorf("thresholds quoted for a cap that does not run: %s", sentence)
	}
}

// The same declaration with no cap reported AT ALL -- an attended machine on a
// bridge that has no cap machinery, which is 0005's whole posture about a second
// reader. It gets the same answer, because what the agent must do is the same.
func TestAnAttendedMachineThatReportsNoCapAtAllStillSaysAHumanIsThere(t *testing.T) {
	var absent *entities.SilenceCap
	sentence := absent.Sentence(attended(true))

	if !strings.Contains(sentence, "HUMAN IS EXPECTED") {
		t.Errorf("a declared human vanished when the bridge reported no cap: %s", sentence)
	}
	if strings.Contains(sentence, "did not say") {
		t.Errorf("the bridge DID say who is there; the sentence pretends otherwise: %s", sentence)
	}
}

// A declared human overrides nothing on a capped machine -- the two agree, and
// the thresholds are still worth naming because meeting them is avoidable.
func TestAnAttendedCappedMachineStillNamesItsThresholds(t *testing.T) {
	sentence := (&entities.SilenceCap{Enabled: true, WarnAfter: 45, LiftAfter: 90}).Sentence(attended(true))

	for _, want := range []string{"45s", "90s", "HUMAN IS EXPECTED"} {
		if !strings.Contains(sentence, want) {
			t.Errorf("the sentence does not mention %q: %s", want, sentence)
		}
	}
}

// A DECLARED empty room, on a machine that also runs a cap. The cap is beside
// the point once nobody is there, and quoting its thresholds would invite an
// agent to narrate against a clock nobody is listening to.
func TestADeclaredUnattendedMachineIsAnEmptyRoomWhateverTheCapSays(t *testing.T) {
	capped := &entities.SilenceCap{Enabled: true, WarnAfter: 45, LiftAfter: 90}
	sentence := capped.Sentence(attended(false))

	if !strings.Contains(sentence, "UNATTENDED") {
		t.Errorf("a declared empty room is not named as one: %s", sentence)
	}
	if strings.Contains(sentence, "45s") || strings.Contains(sentence, "90s") {
		t.Errorf("thresholds quoted to an empty room: %s", sentence)
	}
}

// The compatibility path, pinned. A bridge that says nothing about attendance is
// an older build, and for one of those `enabled` IS the inversion of the
// machine's declared setting -- so inferring is right by construction there, and
// must keep producing exactly what it produced before this entry.
func TestAnOlderBridgeStillGetsTodaysThreeSentences(t *testing.T) {
	capped := &entities.SilenceCap{Enabled: true, WarnAfter: 45, LiftAfter: 90}
	if inferred, declared := capped.Sentence(nil), capped.Sentence(attended(true)); inferred != declared {
		t.Errorf("an older bridge's capped machine reads differently:\n%s\n%s", inferred, declared)
	}

	uncapped := &entities.SilenceCap{Enabled: false, WarnAfter: 45, LiftAfter: 90}
	if inferred, declared := uncapped.Sentence(nil), capped.Sentence(attended(false)); inferred != declared {
		t.Errorf("an older bridge's uncapped machine reads differently:\n%s\n%s", inferred, declared)
	}

	var absent *entities.SilenceCap
	if !strings.Contains(absent.Sentence(nil), "did not say") {
		t.Errorf("a bridge that said nothing at all no longer admits it: %s", absent.Sentence(nil))
	}
}
