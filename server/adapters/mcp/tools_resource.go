// screenreader-mcp adapters -- the screenreader://tools resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. Serves `screenreader://tools`: every tool this server has, the
// capability that gates it, and both of its schemas.
// BUILT BY: sdk_server.go's Bind, beside the other four resources.
// DEPENDS ON: the *tools.Registry the Server ALREADY holds -- not BuildRegistry,
// so the document describes the registry this process is actually running rather
// than a second one built to be described.
//
// Spec 0031. It exists because an external agent, mid-task and connected
// cleanly, opened the Go source to find out what it could call -- and was right
// to, because nothing published the answer. "Fix that and I won't."
//
// STATIC AND COMPLETE, and that is the whole point (2.1). It lists gated tools
// with no reader connected, and it lists tools the connected reader could not
// run. Filtering it to what is currently callable is the one temptation to
// refuse: the complaint was that a fresh tool list showed only the ungated few,
// and a session-filtered document would show exactly the same few. Worse, a
// document whose content depends on session state is a document a client may
// cache across a state change -- which is entry 11.6's failure mode, re-imported
// into the one place chosen precisely because it could not have it.
//
// So it answers "what does this server offer, and what does each one need?" The
// other question -- "what can I call right now?" -- is answered by intersecting
// this with screenreader://info, which reports what the connected reader
// announced from the same vocabulary. Neither can go stale, because neither
// depends on the other's timing.
//
// READER-AGNOSTIC, therefore, and it must stay so: it names the CAPABILITY that
// gates each tool and stops there. The registry does not know which reader is
// connected and this document must not learn (spec 0005 principle 2).
//
// EVERY PER-TOOL LINE IS COMPOSED FROM THE REGISTRY at read time, the way
// guidanceDocument composes persona profiles. A tool therefore cannot be missing
// from the document, and no sentence about a tool exists to be edited: the
// entry's own warning is that a hand-written cheat-sheet disagreeing with the
// registry is worse than none.
package mcp

import (
	"bytes"
	"context"
	_ "embed"
	"encoding/json"
	"fmt"
	"strings"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// ToolsURI is the resource's address.
const ToolsURI = "screenreader://tools"

// addToolsResource registers the resource.
//
// Takes no session source, exactly like the guidance resource: there is nothing
// to be connected to in order to read what a server offers, and being readable
// before connecting is most of the value.
func (s *Server) addToolsResource() {
	s.sdk.AddResource(
		&sdk.Resource{
			URI:      ToolsURI,
			Name:     "every tool, what gates it, and what it returns",
			MIMEType: "text/markdown",
			Description: "The complete reference for this server's tools -- readable BEFORE " +
				"connecting and unchanged by any session. Every tool is here, gated or not: " +
				"what it is for, the capability a reader must announce for it to be " +
				"callable, the parameters it takes and the shape of a successful result, " +
				"both as JSON Schema. Reader-agnostic: it names capabilities, never one " +
				"reader's keys. Read screenreader://info for the capabilities THIS reader " +
				"announced, and the two together tell you what you can call right now. " +
				"Read this instead of guessing a tool's parameters or its result fields.",
		},
		func(_ context.Context, _ *sdk.ReadResourceRequest) (*sdk.ReadResourceResult, error) {
			return &sdk.ReadResourceResult{Contents: []*sdk.ResourceContents{{
				URI:      ToolsURI,
				MIMEType: "text/markdown",
				Text:     toolsDocument(s.registry),
			}}}, nil
		},
	)
}

// toolsDocument assembles the served text: the static frame, then one section
// per tool, grouped under the capability that gates it.
//
// Built per read rather than once at init, for guidanceDocument's reason: it is
// cheap, and a package-level variable built from another package's function is a
// start-order dependency nobody can see.
//
// THE GATE IS READ FROM THE CATALOG, not from the tool. The catalog is what the
// server actually filters publication with, so composing the document from it
// makes "the document says what gates this" and "this is what gates it" the same
// sentence rather than two that agree today.
func toolsDocument(registry *tools.Registry) string {
	catalog := registry.Catalog()

	var document strings.Builder
	document.WriteString(toolsFrame)
	for _, group := range groupByCapability(registry) {
		fmt.Fprintf(&document, "\n%s\n", heading(group.capability))
		for _, tool := range group.tools {
			capability, _ := catalog.CapabilityOf(tool.Name())
			fmt.Fprintf(&document,
				"\n### `%s`\n\n%s\n\n%s\n\nParameters:\n\n```json\n%s\n```\n\nReturns:\n\n```json\n%s\n```\n",
				tool.Name(),
				gate(capability),
				// The tool's own text, WITHOUT the precondition sentence the tool
				// list carries: the gate() line above has already said it, at more
				// length. They cannot drift despite being worded differently,
				// because both render the same catalog fact rather than two
				// hand-written claims about it (spec 0031 3.3).
				tool.Description(),
				readable(tool.InputSchema()),
				readable(tool.OutputSchema()),
			)
		}
	}
	return document.String()
}

// group is one capability's tools, in registry order.
type group struct {
	capability entities.Capability
	tools      []tools.Tool
}

// groupByCapability keeps the registry's own order, and the order of first
// appearance for the groups themselves -- which puts the ungated four first,
// because that is how the registry is written and why it is written that way.
func groupByCapability(registry *tools.Registry) []group {
	var groups []group
	index := map[entities.Capability]int{}
	for _, tool := range registry.All() {
		at, seen := index[tool.Capability()]
		if !seen {
			at = len(groups)
			index[tool.Capability()] = at
			groups = append(groups, group{capability: tool.Capability()})
		}
		groups[at].tools = append(groups[at].tools, tool)
	}
	return groups
}

// heading introduces one group: the capability, and the contract's own account
// of what it is.
//
// The meaning comes from the entity (spec 0031, 2.5), so a capability cannot be
// added without one, and what it says here is what the wire contract says it is
// -- not a gloss this document invented for its own use.
func heading(capability entities.Capability) string {
	if capability == "" {
		return "## Always available\n\nThese need no capability and no session. They are how you " +
			"find a reader, open a session, end it, and ask whether it is still alive -- so they " +
			"stay callable across a disconnect, which is what lets you reconnect after one."
	}
	return fmt.Sprintf("## The `%s` capability\n\n%s", capability, capability.Meaning())
}

// gate is the one-line answer to "can I call this?", repeated per tool rather
// than left to the heading: an agent that jumped to a tool should not have to
// scroll back to find out what it needs.
func gate(capability entities.Capability) string {
	if capability == "" {
		return "**Ungated.** Callable whenever this server is running."
	}
	return fmt.Sprintf("**Gated on `%s`.** Callable only while a reader that announced "+
		"that capability is connected.", capability)
}

// readable re-indents a hand-written schema so the fenced block reads the same
// way whoever wrote it: some are one line, some are already laid out.
//
// A schema that will not parse is served verbatim rather than dropped -- but it
// cannot get here, because NewServer refuses to start with one (tool_binding.go).
func readable(schema json.RawMessage) string {
	var indented bytes.Buffer
	if err := json.Indent(&indented, compact(schema), "", "  "); err != nil {
		return string(schema)
	}
	return indented.String()
}

// compact strips the existing layout first, so json.Indent is re-indenting
// rather than indenting what is already indented.
func compact(schema json.RawMessage) []byte {
	var flat bytes.Buffer
	if err := json.Compact(&flat, schema); err != nil {
		return schema
	}
	return flat.Bytes()
}

// The frame: the preamble and the error convention, as a MARKDOWN FILE rather
// than a Go string literal (AGENTS.md rule 9).
//
// IT NAMES NO TOOL, and a test asserts it. That is the second of spec 0031 Part
// 4's three measures against drift: everything tool-specific is composed above,
// so there is nowhere here for a copy of the truth to be helpfully pasted and
// then quietly rot.
//
//go:embed documents/tools-frame.md
var toolsFrame string
