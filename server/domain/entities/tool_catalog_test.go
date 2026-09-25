// screenreader-mcp domain -- ToolCatalog's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package entities_test

import (
	"slices"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

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

func TestAllIsEveryToolInRegistryOrder(t *testing.T) {
	want := []string{
		"list_readers", "connect_reader", "disconnect_reader", "status",
		"get_speech", "get_last_speech", "get_braille", "press_gesture",
	}
	if got := catalog().All(); !slices.Equal(got, want) {
		t.Errorf("All() = %v, want %v", got, want)
	}
}

func TestAllTakesNoAnnouncedCapabilitiesAtAll(t *testing.T) {
	first := catalog().All()
	second := catalog().All()

	if !slices.Equal(first, second) {
		t.Errorf("All() = %v then %v; the advertised list must be a constant", first, second)
	}
	if !slices.Contains(first, "get_braille") {
		t.Error("All() omitted get_braille; every tool is advertised regardless of capability")
	}
}

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

func TestTheCatalogCopiesTheGatesItWasGiven(t *testing.T) {
	gates := []entities.ToolGate{{Name: "get_braille", Capability: entities.CapabilityBraille}}
	built := entities.NewToolCatalog(gates)

	gates[0].Name = "mutated"

	if got := built.All(); !slices.Equal(got, []string{"get_braille"}) {
		t.Errorf("All() = %v after the caller edited its slice; want the built table", got)
	}
}
