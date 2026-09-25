// screenreader-mcp domain -- the Persona entity's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
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

func TestTheSupersededDeveloperNameIsNotAnAlias(t *testing.T) {
	if _, err := entities.ParsePersona("developer"); err == nil {
		t.Error("`developer` was accepted; `expert` replaced it, and an alias " +
			"would make two names for one stance in every session record")
	}
}

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
