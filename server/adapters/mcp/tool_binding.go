// screenreader-mcp adapters -- binding a domain Tool to the SDK.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter mapping a domain Tool onto the go-sdk's non-generic registration, and a tool result onto an MCP call result.
// BUILT BY / USED BY: sdk_server.go, the only caller.
package mcp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// declare takes both schemas from the tool; the SDK does not validate results against the output schema on this path.
func declare(tool tools.Tool) *sdk.Tool {
	return &sdk.Tool{
		Name:         tool.Name(),
		Description:  precondition(tool) + tool.Description(),
		InputSchema:  tool.InputSchema(),
		OutputSchema: tool.OutputSchema(),
	}
}

// precondition is the sentence a gated tool's description opens with.
func precondition(tool tools.Tool) string {
	capability := tool.Capability()
	switch capability {
	case "":
		return ""
	case entities.GatedByItsSteps:
		return "REQUIRES A CONNECTED READER, but no one fixed capability: what this needs " +
			"depends on what you send it, and the whole request is checked against what the " +
			"reader announced BEFORE any of it is delivered. A request naming something the " +
			"reader cannot do is refused entire, saying which part of it asked -- read " +
			"screenreader://tools, or the guidance connect_reader returns, to see what this " +
			"reader can do. "
	}
	return "REQUIRES A CONNECTED READER that announced the `" + string(capability) +
		"` capability -- call connect_reader first, and read screenreader://tools " +
		"or the guidance it returns to see what this reader can do. Calling it " +
		"without that answers an error naming what is missing, never a wrong result. "
}

// validateSchema checks both schemas at startup, because the SDK panics on a non-object schema when the tool is added.
func validateSchema(tool tools.Tool) error {
	if err := validateObjectSchema(tool.Name(), "input", tool.InputSchema()); err != nil {
		return err
	}
	return validateObjectSchema(tool.Name(), "output", tool.OutputSchema())
}

func validateObjectSchema(tool, which string, declared json.RawMessage) error {
	var schema map[string]any
	if err := json.Unmarshal(declared, &schema); err != nil {
		return fmt.Errorf("tool %q: its %s schema is not valid JSON: %w", tool, which, err)
	}
	if schema["type"] != "object" {
		return fmt.Errorf(`tool %q: its %s schema must have "type": "object", got %v`,
			tool, which, schema["type"])
	}
	return nil
}

func handlerFor(dispatch *tools.Dispatcher, name string) sdk.ToolHandler {
	return func(_ context.Context, request *sdk.CallToolRequest) (*sdk.CallToolResult, error) {
		return callResult(dispatch.Execute(name, request.Params.Arguments))
	}
}

// callResult maps a tool failure to a result with IsError, so the agent can read it and self-correct.
func callResult(value any, failure error) (*sdk.CallToolResult, error) {
	if failure != nil {
		// A wiring mistake is ours, so it surfaces as a protocol error.
		if errors.Is(failure, tools.ErrUnknownTool) {
			return nil, failure
		}
		return &sdk.CallToolResult{
			Content: []sdk.Content{&sdk.TextContent{Text: failure.Error()}},
			IsError: true,
		}, nil
	}

	encoded, err := json.Marshal(value)
	if err != nil {
		return nil, fmt.Errorf("encoding the tool result: %w", err)
	}
	return &sdk.CallToolResult{
		Content:           []sdk.Content{&sdk.TextContent{Text: string(encoded)}},
		StructuredContent: value,
	}, nil
}
