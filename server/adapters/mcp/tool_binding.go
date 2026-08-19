// screenreader-mcp adapters -- binding a domain Tool to the SDK.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. Maps a domain Tool onto the go-sdk's tool registration, and a
// tool result onto an MCP call result.
// BUILT BY / USED BY: sdk_server.go, which is the only caller.
// DEPENDS ON: the go-sdk and domain/controllers/tools. Nothing here reaches the
// bridge or the wire.
//
// THIS FILE IS THE WHOLE OF THE PER-TOOL BINDING, and it is generic: there is
// one bind function and no per-tool code anywhere in this package. That is what
// spec 0013's erased-params decision bought, and it is why the registry can be
// the single tool list -- there is no second place a tool has to be mentioned.
//
// It uses the SDK's NON-GENERIC registration path, (*mcp.Server).AddTool, whose
// handler receives raw json.RawMessage arguments and whose Tool.InputSchema
// accepts a hand-written schema verbatim. The top-level generic mcp.AddTool
// would derive a schema from a per-tool Go struct, which a uniform domain Tool
// interface has to erase again -- forcing exactly the per-tool binding code this
// design exists to avoid.
package mcp

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
)

// declare turns a domain Tool into the SDK's description of it.
//
// BOTH schemas come from the tool itself, which is what stops the client's tool
// list and screenreader://tools disagreeing about a result shape (spec 0031,
// 3.3): they are composed from the same two methods, so there is still no second
// place a tool is described.
//
// Declaring an output schema does NOT make the SDK police results against it on
// this registration path -- that validation lives on the generic path this
// server deliberately does not use (spec 0031, 3.4). Conformance stays ours, and
// is tested in the domain, against the result structs themselves.
func declare(tool tools.Tool) *sdk.Tool {
	return &sdk.Tool{
		Name:         tool.Name(),
		Description:  precondition(tool) + tool.Description(),
		InputSchema:  tool.InputSchema(),
		OutputSchema: tool.OutputSchema(),
	}
}

// precondition is the sentence a gated tool's description opens with.
//
// WHAT IT REPLACES. Under spec 0013 a gated tool was simply absent until its
// capability was announced, and the absence was the message. Spec 0022 (option
// (c)) advertises everything, so the message has to be said in words -- and
// saying it here is what the absence had going for it: an agent learns the
// precondition at the same instant it learns the tool exists, without having to
// call one to find out.
//
// COMPOSED HERE RATHER THAN WRITTEN INTO NINETEEN DESCRIPTIONS. A tool's own
// Description() says what the tool DOES, which is the tool's business; whether a
// session is required is the CATALOG's, and it is already recorded there. Adding
// a gated tool therefore gets this for free, which is the same reason the
// catalog is derived from the registry rather than hand-maintained beside it --
// and it is why no reader is named: `tool.Capability()` is a capability string,
// and spec 0005 principle 2 keeps reader names out of this file by construction.
func precondition(tool tools.Tool) string {
	capability := tool.Capability()
	if capability == "" {
		return ""
	}
	return "REQUIRES A CONNECTED READER that announced the `" + string(capability) +
		"` capability -- call connect_reader first, and read screenreader://tools " +
		"or the guidance it returns to see what this reader can do. Calling it " +
		"without that answers an error naming what is missing, never a wrong result. "
}

// validateSchema checks a tool's hand-written schemas before anything is
// registered.
//
// The SDK PANICS on a schema that is not a JSON object schema, at the moment the
// tool is added -- which for a gated tool is mid-session, on a successful
// handshake, in a goroutine serving an agent. Checking every tool once at
// startup turns that into a startup error naming the tool.
//
// BOTH schemas, since spec 0031: AddTool applies the same "type": "object" check
// to the output schema and panics in the same place, so leaving that one
// unchecked would reintroduce exactly the crash this function exists to prevent.
func validateSchema(tool tools.Tool) error {
	if err := validateObjectSchema(tool.Name(), "input", tool.InputSchema()); err != nil {
		return err
	}
	return validateObjectSchema(tool.Name(), "output", tool.OutputSchema())
}

// validateObjectSchema is that check, for one of them. `which` names the schema
// in the error, because "tool %q: its schema is not valid JSON" would send
// somebody looking in the wrong half of the file.
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

// handlerFor is the one handler every tool is registered with.
//
// It closes over the tool NAME rather than the tool, so every call reaches the
// domain through the same dispatcher. There used to be two routes -- an ordinary
// call and the capability backstop's retracted-tool path -- and spec 0022 left
// one: with every tool advertised, no call can arrive for an unpublished tool,
// so the backstop had nothing left to answer and was deleted.
func handlerFor(dispatch *tools.Dispatcher, name string) sdk.ToolHandler {
	return func(_ context.Context, request *sdk.CallToolRequest) (*sdk.CallToolResult, error) {
		return callResult(dispatch.Execute(name, request.Params.Arguments))
	}
}

// callResult maps a domain answer onto MCP's.
//
// A tool failure becomes a RESULT with IsError set, not a protocol error. That
// is the SDK's own guidance and it matters here more than usual: an agent can
// see the content of an errored result and self-correct within the turn --
// connect first, ask a reader that has braille -- whereas a JSON-RPC error is a
// transport-level fault it can only report.
func callResult(value any, failure error) (*sdk.CallToolResult, error) {
	if failure != nil {
		// A wiring mistake is ours, not the agent's, so it surfaces as a
		// protocol error rather than as advice the agent cannot act on.
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
	// Both forms, deliberately: StructuredContent for a client that can use
	// it, and the same JSON as text for the many that read content only.
	return &sdk.CallToolResult{
		Content:           []sdk.Content{&sdk.TextContent{Text: string(encoded)}},
		StructuredContent: value,
	}, nil
}
