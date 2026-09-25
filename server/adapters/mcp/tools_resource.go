// screenreader-mcp adapters -- the screenreader://tools resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter serving the static, complete, reader-agnostic `screenreader://tools` resource, composed from the running registry.
// BUILT BY: sdk_server.go's Bind.
//
// It must not filter to the session: a session-dependent document is one a client may cache across a state change.
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

const ToolsURI = "screenreader://tools"

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

// toolsDocument reads each gate from the catalog, so the document and the gate are the same fact.
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
				tool.Description(),
				readable(tool.InputSchema()),
				readable(tool.OutputSchema()),
			)
		}
	}
	return document.String()
}

type group struct {
	capability entities.Capability
	tools      []tools.Tool
}

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

func heading(capability entities.Capability) string {
	switch capability {
	case "":
		return "## Always available\n\nThese need no capability and no session. They are how you " +
			"find a reader, open a session, end it, and ask whether it is still alive -- so they " +
			"stay callable across a disconnect, which is what lets you reconnect after one."
	case entities.GatedByItsSteps:
		return "## Gated by its steps\n\nThese need a connected reader, but not one fixed " +
			"capability: what they require is decided by the CALL. Each is checked against what " +
			"this session announced before anything is delivered, and a request naming something " +
			"the reader cannot do is refused whole, saying which part of it asked."
	}
	return fmt.Sprintf("## The `%s` capability\n\n%s", capability, capability.Meaning())
}

func gate(capability entities.Capability) string {
	switch capability {
	case "":
		return "**Ungated.** Callable whenever this server is running."
	case entities.GatedByItsSteps:
		return "**Gated by its steps.** Callable while a reader is connected that announced " +
			"whatever the particular call asks for -- so what it needs depends on what you send, " +
			"and the whole request is checked before any of it is delivered."
	}
	return fmt.Sprintf("**Gated on `%s`.** Callable only while a reader that announced "+
		"that capability is connected.", capability)
}

// readable re-indents a schema; one that will not parse is served verbatim, though NewServer refuses to start with one.
func readable(schema json.RawMessage) string {
	var indented bytes.Buffer
	if err := json.Indent(&indented, compact(schema), "", "  "); err != nil {
		return string(schema)
	}
	return indented.String()
}

func compact(schema json.RawMessage) []byte {
	var flat bytes.Buffer
	if err := json.Compact(&flat, schema); err != nil {
		return schema
	}
	return flat.Bytes()
}

// The frame names no tool; a test asserts it.
//
//go:embed documents/tools-frame.md
var toolsFrame string
