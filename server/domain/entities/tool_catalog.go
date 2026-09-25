// screenreader-mcp domain -- ToolCatalog: what gates what.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, the table of which capability gates which tool.
// BUILT BY: domain/controllers/tools/registry.go, from the one hand-written tool list.
// READ BY: adapters/mcp/sdk_server.go and adapters/mcp/tools_resource.go.
//
// No reader name may appear here, only capability strings.
package entities

import "sort"

// GatedByItsSteps is a property of the table, not a capability: it never crosses
// the wire and no bridge can announce it.
const GatedByItsSteps Capability = "(its steps)"

type ToolGate struct {
	Name string

	// Capability empty means ungated, callable before any session exists.
	Capability Capability
}

type ToolCatalog struct {
	gates []ToolGate
	by    map[string]ToolGate
}

func NewToolCatalog(gates []ToolGate) ToolCatalog {
	by := make(map[string]ToolGate, len(gates))
	for _, gate := range gates {
		by[gate.Name] = gate
	}
	return ToolCatalog{gates: append([]ToolGate(nil), gates...), by: by}
}

// All is every tool, whatever any reader announced; ToolContext enforces capabilities per call.
func (c ToolCatalog) All() []string {
	names := make([]string, 0, len(c.gates))
	for _, gate := range c.gates {
		names = append(names, gate.Name)
	}
	return names
}

func (c ToolCatalog) CapabilityOf(name string) (Capability, bool) {
	gate, known := c.by[name]
	return gate.Capability, known
}

func (c ToolCatalog) Capabilities() []Capability {
	seen := map[Capability]struct{}{}
	var all []Capability
	for _, gate := range c.gates {
		if gate.Capability == "" || gate.Capability == GatedByItsSteps {
			continue
		}
		if _, ok := seen[gate.Capability]; ok {
			continue
		}
		seen[gate.Capability] = struct{}{}
		all = append(all, gate.Capability)
	}
	sort.Slice(all, func(i, j int) bool { return all[i] < all[j] })
	return all
}
