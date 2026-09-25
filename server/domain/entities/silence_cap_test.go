// screenreader-mcp domain -- the SilenceCap entity's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
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

func attended(v bool) *bool { return &v }

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
	if strings.Contains(sentence, "45s") || strings.Contains(sentence, "90s") {
		t.Errorf("thresholds quoted for a cap that does not run: %s", sentence)
	}
}

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

func TestAnAttendedCappedMachineStillNamesItsThresholds(t *testing.T) {
	sentence := (&entities.SilenceCap{Enabled: true, WarnAfter: 45, LiftAfter: 90}).Sentence(attended(true))

	for _, want := range []string{"45s", "90s", "HUMAN IS EXPECTED"} {
		if !strings.Contains(sentence, want) {
			t.Errorf("the sentence does not mention %q: %s", want, sentence)
		}
	}
}

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
