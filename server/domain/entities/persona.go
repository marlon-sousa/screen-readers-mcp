// screenreader-mcp domain -- Persona: what a session is standing in for.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, the stance a session declares at connect_reader, fixed for the session, and the texts that say what it means.
// BUILT BY: the agent, through connect_reader's `persona` parameter, carried in ports.SessionOptions.
// READ BY: connect_reader, the guidance resource, status and screenreader://info.
package entities

import (
	_ "embed"
	"fmt"
	"strings"
)

type Persona string

const (
	PersonaUser Persona = "user"

	PersonaValidator Persona = "validator"

	PersonaExpert Persona = "expert"
)

func (p Persona) String() string { return string(p) }

// AllPersonas is in order of increasing latitude, and is the one list every enumeration reads.
func AllPersonas() []Persona {
	return []Persona{PersonaUser, PersonaValidator, PersonaExpert}
}

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
