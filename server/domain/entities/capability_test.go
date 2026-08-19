// screenreader-mcp domain -- tests for capability.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Black-box (package entities_test): the set is exercised through exactly the
// surface the handshake and the tool gate use.
package entities_test

import (
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func TestSetHasWhatWasAnnounced(t *testing.T) {
	set := entities.NewSet([]string{"speech", "gestures"})

	if !set.Has(entities.CapabilitySpeech) {
		t.Error("speech was announced but Has says otherwise")
	}
	if set.Has(entities.CapabilityBraille) {
		t.Error("braille was not announced but Has says it was")
	}
}

// The zero Set is the answer for "no session yet", so it must behave as an empty
// set rather than panicking on a nil map.
func TestZeroSetHasNothing(t *testing.T) {
	var set entities.Set

	if set.Has(entities.CapabilitySpeech) {
		t.Error("the zero set claims a capability")
	}
	if got := set.All(); len(got) != 0 {
		t.Errorf("the zero set is not empty: %v", got)
	}
}

// protocol.md §4: a consumer must IGNORE an unknown capability string. Ignoring
// is not discarding -- the set still reports it, because it is what
// screenreader://info tells the agent about the reader, and a reader deserves an
// honest description even where this server has no tool to match.
func TestUnknownCapabilitiesAreRetainedNotRejected(t *testing.T) {
	set := entities.NewSet([]string{"speech", "announce", "teleportation"})

	if !set.Has(entities.CapabilitySpeech) {
		t.Error("a known capability was lost among unknown ones")
	}
	if diff := cmp.Diff([]string{"announce", "speech", "teleportation"}, set.Strings()); diff != "" {
		t.Errorf("announced set (-want +got):\n%s", diff)
	}
}

func TestAllIsSortedAndDeduplicated(t *testing.T) {
	set := entities.NewSet([]string{"state", "focus", "state"})

	want := []entities.Capability{entities.CapabilityFocus, entities.CapabilityState}
	if diff := cmp.Diff(want, set.All()); diff != "" {
		t.Errorf("All() (-want +got):\n%s", diff)
	}
}

// -- the contract's own gloss (spec 0031, 2.5) --------------------------------

// A capability cannot be added without saying what it IS. Persona's texts are
// guarded the same way and for the same reason: the vocabulary is the wire
// contract's, so a member with nothing to say is a hole in the contract rather
// than a document's omission.
//
// CapabilityGuidance is covered by this like any other, even though it gates a
// resource and heads no group in screenreader://tools -- what is being asserted
// is that the vocabulary is complete, not that one document has a place to print
// every member.
func TestEveryDeclaredCapabilityHasAMeaning(t *testing.T) {
	for _, capability := range entities.AllCapabilities() {
		if capability.Meaning() == "" {
			t.Errorf("%q has no meaning; a capability an agent is shown and cannot "+
				"interpret is the gap the meanings exist to close", capability)
		}
	}
}

// The gloss is for what THIS SERVER declares. A bridge may announce anything and
// NewSet keeps it, so an unknown string reaching Meaning must answer honestly
// rather than inventing a description of a group nobody here knows.
func TestAnUndeclaredCapabilityHasNoMeaning(t *testing.T) {
	if meaning := entities.Capability("teleportation").Meaning(); meaning != "" {
		t.Errorf("an undeclared capability was glossed as %q", meaning)
	}
}
