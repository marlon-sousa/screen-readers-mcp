// screenreader-mcp domain -- the Persona entity's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Spec 0029. Two jobs here. One is ordinary parsing. The other is the guarantee
// that makes the enum safe to build documents from: EVERY persona has every
// text, so "add a fourth persona and forget to say what it means" cannot ship.
package entities_test

import (
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func TestParsePersonaAcceptsTheThree(t *testing.T) {
	for _, want := range entities.AllPersonas() {
		got, err := entities.ParsePersona(want.String())
		if err != nil {
			t.Errorf("ParsePersona(%q): %v", want, err)
		}
		if got != want {
			t.Errorf("ParsePersona(%q) = %q", want, got)
		}
	}
}

// The parse error is where most agents will meet personas for the first time,
// so it has to teach rather than merely refuse: all three, each with the
// question it asks.
func TestParsePersonaRefusesTheRestAndNamesTheChoices(t *testing.T) {
	for _, value := range []string{"", "tester", "User", "developer"} {
		_, err := entities.ParsePersona(value)
		if err == nil {
			t.Fatalf("ParsePersona(%q) was accepted", value)
		}
		for _, persona := range entities.AllPersonas() {
			if !strings.Contains(err.Error(), persona.String()) {
				t.Errorf("ParsePersona(%q) error = %q, want %q listed", value, err, persona)
			}
			if !strings.Contains(err.Error(), persona.Question()) {
				t.Errorf("ParsePersona(%q) error = %q, want the question %q",
					value, err, persona.Question())
			}
		}
	}
}

// `developer` was the name this persona carried while it was being designed
// (board entry 11.19, before the 2026-08-17 widening). It is not a valid value,
// and the check above already proves it is refused -- this names why, so nobody
// reintroduces it as an alias out of kindness.
func TestTheSupersededDeveloperNameIsNotAnAlias(t *testing.T) {
	if _, err := entities.ParsePersona("developer"); err == nil {
		t.Error("`developer` was accepted; `expert` replaced it, and an alias " +
			"would make two names for one stance in every session record")
	}
}

// The guarantee the guidance document and connect_reader both rely on.
func TestEveryPersonaHasAQuestionAStanceAndAProfile(t *testing.T) {
	for _, persona := range entities.AllPersonas() {
		if persona.Question() == "" {
			t.Errorf("%q has no question", persona)
		}
		if persona.Stance() == "" {
			t.Errorf("%q has no stance; connect_reader would return an empty "+
				"instruction for a session that declared it", persona)
		}
		if persona.Profile() == "" {
			t.Errorf("%q has no profile; screenreader://guidance would describe "+
				"a persona an agent can choose without saying what it is", persona)
		}
	}
}

// The whole point of the correction on 2026-08-17: this server does not know
// which platform it is driving until `hello` answers, so a keystroke in any of
// these texts is a instruction that may not exist on the reader in front of the
// agent. TalkBack has neither a keyboard nor Windows.
func TestNoPersonaTextNamesAKeystroke(t *testing.T) {
	forbidden := []string{"Alt+", "Tab", "Windows+", "NVDA+", "JAWS", "Shift+", "Ctrl+", "Control+"}
	for _, persona := range entities.AllPersonas() {
		for _, text := range []string{persona.Stance(), persona.Profile()} {
			for _, key := range forbidden {
				if strings.Contains(text, key) {
					t.Errorf("%q names %q: the ordinary vocabulary is the PLATFORM's, "+
						"and this server states the rule while the bridge enumerates "+
						"the instances (spec 0029)", persona, key)
				}
			}
		}
	}
}
