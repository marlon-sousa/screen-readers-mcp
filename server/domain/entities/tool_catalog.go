// screenreader-mcp domain -- ToolCatalog: what gates what.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. The record of which capability gates which tool.
//
// It was spec 0013's VISIBILITY gate, keyed on the announced capability set.
// Spec 0022 (agreed 2026-08-19, option (c)) took visibility away from it: every
// tool is advertised from startup now, so `All()` is the whole publication
// answer and no capability set goes in. What survives is the TABLE -- which
// capability gates which tool -- because that is still true, still published in
// `screenreader://tools`, and still what ToolContext enforces per call.
// BUILT BY: domain/controllers/tools/registry.go, from the one hand-written tool
// list. (SPEC AMENDMENT, rides in 10b: the layout summary's "Built by" column
// says connection.go. Deriving the gate from the registry instead is what keeps
// the two from drifting -- the registry is the single tool list, so a tool that
// exists is a tool the catalog knows about, by construction rather than by
// somebody remembering.)
// READ BY: adapters/mcp/sdk_server.go (which names to register, once, at Bind)
// and adapters/mcp/tools_resource.go (what gates each tool, for the document).
//
// NO READER NAME APPEARS HERE, only capability strings. That is spec 0005's
// first chassis principle rendered as a type: "JAWS has no braille" is not
// something this file could express even if somebody wanted it to.
package entities

import "sort"

// ToolGate is one tool's entry: its name and what gates it.
type ToolGate struct {
	// Name is the tool's MCP name.
	Name string

	// Capability is the group a reader must announce for this tool to be
	// advertised. EMPTY means ungated -- the four discovery and connection
	// tools, which must be there before any reader is, since they are how a
	// reader gets connected in the first place.
	Capability Capability
}

// ToolCatalog is the whole table. Immutable once built.
type ToolCatalog struct {
	gates []ToolGate
	by    map[string]ToolGate
}

// NewToolCatalog builds the table. The order given is preserved, because it is
// the order the tool list is published in and a stable order is worth having
// wherever an agent or a diff reads the result.
func NewToolCatalog(gates []ToolGate) ToolCatalog {
	by := make(map[string]ToolGate, len(gates))
	for _, gate := range gates {
		by[gate.Name] = gate
	}
	return ToolCatalog{gates: append([]ToolGate(nil), gates...), by: by}
}

// All is every tool this server has, in registry order.
//
// EVERY tool, whatever is connected and whatever any reader announced. That is
// spec 0022's option (c), agreed 2026-08-19: the advertised list is now a
// constant, so a client holding a stale copy of it is holding a correct one.
//
// What this does NOT change is who may CALL one. Advertisement and enforcement
// were already separate -- a tool reaches its port through ToolContext's
// accessors, which answer a CapabilityError whenever there is no session or the
// reader announced nothing (see controllers/tools/tool_context.go). The gate on
// the LIST only ever bought a shorter list; it never made an unusable call fail.
//
// The order is preserved because it is the order the list is published in, and a
// stable order is worth having wherever an agent or a diff reads the result.
func (c ToolCatalog) All() []string {
	names := make([]string, 0, len(c.gates))
	for _, gate := range c.gates {
		names = append(names, gate.Name)
	}
	return names
}

// CapabilityOf reports what gates a tool, and whether the catalog knows the name
// at all. Read by the MCP adapter's backstop, which must tell "a tool of ours
// that is currently retracted" from "a name that was never a tool".
func (c ToolCatalog) CapabilityOf(name string) (Capability, bool) {
	gate, known := c.by[name]
	return gate.Capability, known
}

// Capabilities is every capability the catalog gates something on, sorted. It
// answers "which capabilities does this server actually have tools for?", which
// is a different question from what a reader announced -- protocol.md §4 lets a
// bridge announce groups we have no tool for, and a reader deserves to be
// described honestly either way.
func (c ToolCatalog) Capabilities() []Capability {
	seen := map[Capability]struct{}{}
	var all []Capability
	for _, gate := range c.gates {
		if gate.Capability == "" {
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
