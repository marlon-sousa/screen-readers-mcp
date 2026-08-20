// screenreader-mcp domain -- the SilenceCap entity's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Spec 0032. The entity is a description plus one sentence, so what is worth
// pinning down is that the sentence says DIFFERENT things in the three cases --
// capped, uncapped, and "this bridge did not say" -- and above all that the
// third is not quietly reported as the second. An agent told "no cap here" goes
// quiet; an agent told "we do not know" narrates anyway, which is the safe
// direction and the whole reason the field is a pointer.
package entities_test

import (
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func TestACappedMachineNamesBothThresholds(t *testing.T) {
	cap := &entities.SilenceCap{Enabled: true, WarnAfter: 45, LiftAfter: 90}
	sentence := cap.Sentence()

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
	sentence := (&entities.SilenceCap{Enabled: false, WarnAfter: 45, LiftAfter: 90}).Sentence()

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
	sentence := missing.Sentence()

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
