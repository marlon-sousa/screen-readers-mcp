// screenreader-mcp domain -- ToolCatalog's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Black-box (package entities_test), exercising the catalog through the surface
// the MCP adapter uses.
//
// WHAT THESE STOPPED PROVING, and where it went. Spec 0013's acceptance
// criterion 10 had a first clause -- "a tool whose capability is absent is NOT
// advertised" -- and this file was its proof. Spec 0022 (option (c), agreed
// 2026-08-19) withdrew that clause: every tool is advertised, and what a reader
// cannot do is enforced per CALL rather than per LIST, by ToolContext. So the
// gate tests below became All() and the enforcement proof lives in
// controllers/tools' context tests and in the integration tier's no-braille
// scenario, which asserts on the ERROR rather than on an absence.
package entities_test

import (
	"slices"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// A catalog shaped like the real one: four ungated tools plus a few gated ones
// spanning three capabilities, one of which has two tools.
func catalog() entities.ToolCatalog {
	return entities.NewToolCatalog([]entities.ToolGate{
		{Name: "list_readers"},
		{Name: "connect_reader"},
		{Name: "disconnect_reader"},
		{Name: "status"},
		{Name: "get_speech", Capability: entities.CapabilitySpeech},
		{Name: "get_last_speech", Capability: entities.CapabilitySpeech},
		{Name: "get_braille", Capability: entities.CapabilityBraille},
		{Name: "press_gesture", Capability: entities.CapabilityGestures},
	})
}

// The whole publication answer: every tool, in the order the table was built.
func TestAllIsEveryToolInRegistryOrder(t *testing.T) {
	want := []string{
		"list_readers", "connect_reader", "disconnect_reader", "status",
		"get_speech", "get_last_speech", "get_braille", "press_gesture",
	}
	if got := catalog().All(); !slices.Equal(got, want) {
		t.Errorf("All() = %v, want %v", got, want)
	}
}

// The point of option (c), stated as a test: nothing a reader announced can
// change what is advertised, so a client holding a stale list holds a correct
// one. There is no argument to pass -- and that IS the property.
func TestAllTakesNoAnnouncedCapabilitiesAtAll(t *testing.T) {
	first := catalog().All()
	second := catalog().All()

	if !slices.Equal(first, second) {
		t.Errorf("All() = %v then %v; the advertised list must be a constant", first, second)
	}
	// A gated tool is present whether or not any reader could serve it. What
	// stops the call is ToolContext, not this table.
	if !slices.Contains(first, "get_braille") {
		t.Error("All() omitted get_braille; every tool is advertised regardless of capability")
	}
}

// Still asked, by the tools resource: what gates this tool?
func TestCapabilityOfDistinguishesOurToolsFromStrangers(t *testing.T) {
	capability, known := catalog().CapabilityOf("get_braille")
	if !known || capability != entities.CapabilityBraille {
		t.Errorf("CapabilityOf(get_braille) = %q, %v; want braille, true", capability, known)
	}

	capability, known = catalog().CapabilityOf("list_readers")
	if !known || capability != "" {
		t.Errorf("CapabilityOf(list_readers) = %q, %v; want ungated, true", capability, known)
	}

	if _, known := catalog().CapabilityOf("nonsense"); known {
		t.Error("CapabilityOf(nonsense) claimed to know a tool that does not exist")
	}
}

func TestCapabilitiesAreTheDistinctGatesSorted(t *testing.T) {
	want := []entities.Capability{
		entities.CapabilityBraille, entities.CapabilityGestures, entities.CapabilitySpeech,
	}
	if got := catalog().Capabilities(); !slices.Equal(got, want) {
		t.Errorf("Capabilities() = %v, want %v", got, want)
	}
}

// The catalog must not be a window onto its caller's slice: a table that could
// be edited after it was built is not a decision table.
func TestTheCatalogCopiesTheGatesItWasGiven(t *testing.T) {
	gates := []entities.ToolGate{{Name: "get_braille", Capability: entities.CapabilityBraille}}
	built := entities.NewToolCatalog(gates)

	gates[0].Name = "mutated"

	if got := built.All(); !slices.Equal(got, []string{"get_braille"}) {
		t.Errorf("All() = %v after the caller edited its slice; want the built table", got)
	}
}
