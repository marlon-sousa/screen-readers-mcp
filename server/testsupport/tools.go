// screenreader-mcp testsupport -- a builder for a tool call's context.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: test scaffolding that builds a tool call's context, so a tool controller runs with no connection controller, MCP server or bridge.
// USED BY: every tool controller's test.
package testsupport

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
)

type ToolCall struct {
	Tool    tools.Tool
	Context tools.ToolContext
	Control *fakes.FakeConnectionControl
	Clock   *fakes.FakeClock
	Log     *fakes.FakeLog
}

func NewToolCall(tool tools.Tool) *ToolCall {
	control := fakes.NewFakeConnectionControl()
	clock := fakes.NewFakeClock()
	log := fakes.NewFakeLog()

	return &ToolCall{
		Tool:    tool,
		Control: control,
		Clock:   clock,
		Log:     log,
		Context: tools.ToolContext{
			Tool:    tool.Name(),
			Control: control,
			Clock:   clock,
			Log:     log,
		},
	}
}

func (c *ToolCall) WithConnection(connection *ports.ReaderConnection) *ToolCall {
	c.Context.Connection = connection
	c.Control.SetConnection(connection)
	return c
}

// Run sends nil arguments for "", which is what a client sends for a no-parameter tool.
func (c *ToolCall) Run(params string) (any, error) {
	var raw json.RawMessage
	if params != "" {
		raw = json.RawMessage(params)
	}
	return c.Tool.Execute(c.Context, raw)
}
