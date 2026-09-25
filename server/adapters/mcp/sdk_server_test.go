// screenreader-mcp adapters -- the MCP server's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package mcp_test

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	mcpadapter "github.com/marlon-sousa/screen-readers-mcp/server/adapters/mcp"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

type stubTool struct {
	name       string
	capability entities.Capability
	schema     string
	// output is the declared output schema, empty for the plain object one.
	output string
	run    func(ctx tools.ToolContext, params json.RawMessage) (any, error)
}

func (s *stubTool) Name() string                    { return s.name }
func (s *stubTool) Capability() entities.Capability { return s.capability }
func (s *stubTool) Description() string             { return "a tool for the adapter's own tests" }

func (s *stubTool) InputSchema() json.RawMessage {
	if s.schema == "" {
		return json.RawMessage(`{"type":"object"}`)
	}
	return json.RawMessage(s.schema)
}

func (s *stubTool) OutputSchema() json.RawMessage {
	if s.output == "" {
		return json.RawMessage(`{"type":"object"}`)
	}
	return json.RawMessage(s.output)
}

func (s *stubTool) Execute(ctx tools.ToolContext, params json.RawMessage) (any, error) {
	if s.run != nil {
		return s.run(ctx, params)
	}
	return map[string]any{"ok": true}, nil
}

type harness struct {
	server  *mcpadapter.Server
	session *sdk.ClientSession
	control *fakes.FakeConnectionControl
	changed chan struct{}
}

func newHarness(t *testing.T, list ...tools.Tool) *harness {
	t.Helper()

	registry := tools.NewRegistry(list...)
	control := fakes.NewFakeConnectionControl()
	log := fakes.NewFakeLog()

	server, err := mcpadapter.NewServer(registry, log)
	if err != nil {
		t.Fatalf("building the server: %v", err)
	}
	server.Bind(
		tools.NewDispatcher(registry, control, fakes.NewFakeClock(), log, nil),
		control,
		controllers.NewReaderGuidance(control),
	)

	ctx := context.Background()
	clientTransport, serverTransport := sdk.NewInMemoryTransports()

	serverSession, err := server.Connect(ctx, serverTransport)
	if err != nil {
		t.Fatalf("connecting the server: %v", err)
	}
	t.Cleanup(func() { _ = serverSession.Close() })

	changed := make(chan struct{}, 32)
	client := sdk.NewClient(&sdk.Implementation{Name: "test", Version: "0"}, &sdk.ClientOptions{
		ToolListChangedHandler: func(context.Context, *sdk.ToolListChangedRequest) {
			select {
			case changed <- struct{}{}:
			default:
			}
		},
	})
	session, err := client.Connect(ctx, clientTransport, nil)
	if err != nil {
		t.Fatalf("connecting the client: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	return &harness{server: server, session: session, control: control, changed: changed}
}

func (h *harness) names(t *testing.T) []string {
	t.Helper()
	listing, err := h.session.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatalf("tools/list: %v", err)
	}
	names := make([]string, 0, len(listing.Tools))
	for _, tool := range listing.Tools {
		names = append(names, tool.Name)
	}
	slices.Sort(names)
	return names
}

func (h *harness) call(t *testing.T, name string) (*sdk.CallToolResult, error) {
	t.Helper()
	return h.session.CallTool(context.Background(), &sdk.CallToolParams{Name: name})
}

func text(result *sdk.CallToolResult) string {
	if len(result.Content) == 0 {
		return ""
	}
	if content, ok := result.Content[0].(*sdk.TextContent); ok {
		return content.Text
	}
	return ""
}

func ungatedStub() *stubTool { return &stubTool{name: "ungated_tool"} }

func gatedStub() *stubTool {
	return &stubTool{
		name:       "gated_tool",
		capability: entities.CapabilityBraille,
		run: func(ctx tools.ToolContext, _ json.RawMessage) (any, error) {
			if _, err := ctx.Braille(); err != nil {
				return nil, err
			}
			return map[string]any{"reached": true}, nil
		},
	}
}

func TestBindingAdvertisesEveryTool(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())

	if names := h.names(t); !slices.Equal(names, []string{"gated_tool", "ungated_tool"}) {
		t.Errorf("tools/list = %v, want every tool advertised from startup", names)
	}
}

func TestTheAdvertisedListNeverChanges(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())

	atStartup := h.names(t)

	built := testsupport.NewConnection("nvda", entities.CapabilityBraille)
	h.control.SetConnection(built.Connection)
	if names := h.names(t); !slices.Equal(names, atStartup) {
		t.Errorf("tools/list = %v after connecting, want %v -- unchanged", names, atStartup)
	}

	h.control.SetConnection(nil)
	if names := h.names(t); !slices.Equal(names, atStartup) {
		t.Errorf("tools/list = %v after disconnecting, want %v -- unchanged", names, atStartup)
	}

	select {
	case <-h.changed:
		t.Error("the server emitted tools/list_changed; nothing changed, so nothing should be announced")
	default:
	}
}

func TestTheHandWrittenSchemaReachesTheClient(t *testing.T) {
	h := newHarness(t, &stubTool{
		name: "ungated_tool",
		schema: `{"type":"object","properties":{"gestures":{"type":"array",` +
			`"items":{"type":"string"}}},"required":["gestures"]}`,
	})

	listing, err := h.session.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatalf("tools/list: %v", err)
	}
	encoded, err := json.Marshal(listing.Tools[0].InputSchema)
	if err != nil {
		t.Fatalf("marshalling the schema: %v", err)
	}
	for _, want := range []string{`"required"`, `"gestures"`, `"array"`} {
		if !strings.Contains(string(encoded), want) {
			t.Errorf("schema = %s, want it to still contain %s", encoded, want)
		}
	}
}

func TestAMalformedSchemaFailsAtStartupRatherThanMidSession(t *testing.T) {
	log := fakes.NewFakeLog()

	_, err := mcpadapter.NewServer(
		tools.NewRegistry(&stubTool{name: "broken", schema: `{"type":"string"}`}), log,
	)
	if err == nil {
		t.Fatal("a non-object input schema was accepted")
	}
	if !strings.Contains(err.Error(), "broken") {
		t.Errorf("error = %q, want the offending tool named", err)
	}

	_, err = mcpadapter.NewServer(
		tools.NewRegistry(&stubTool{name: "worse", schema: `not json`}), log,
	)
	if err == nil {
		t.Fatal("an unparseable input schema was accepted")
	}
}

func TestAToolFailureIsAReadableResult(t *testing.T) {
	h := newHarness(t, &stubTool{
		name: "ungated_tool",
		run: func(tools.ToolContext, json.RawMessage) (any, error) {
			return nil, errFailed
		},
	})

	result, err := h.call(t, "ungated_tool")
	if err != nil {
		t.Fatalf("the failure surfaced as a protocol error: %v", err)
	}
	if !result.IsError {
		t.Error("IsError is false for a failed tool")
	}
	if !strings.Contains(text(result), errFailed.Error()) {
		t.Errorf("content = %q, want the reason the agent can act on", text(result))
	}
}

func TestASuccessfulResultIsCarriedAsTextAndStructuredContent(t *testing.T) {
	h := newHarness(t, &stubTool{
		name: "ungated_tool",
		run: func(tools.ToolContext, json.RawMessage) (any, error) {
			return map[string]any{"reader": "nvda"}, nil
		},
	})

	result, err := h.call(t, "ungated_tool")
	if err != nil {
		t.Fatalf("tools/call: %v", err)
	}
	if !strings.Contains(text(result), `"reader":"nvda"`) {
		t.Errorf("text content = %q, want the tool's JSON", text(result))
	}
	if result.StructuredContent == nil {
		t.Error("StructuredContent is empty")
	}
}

func TestAToolWithNoArgumentsIsCallable(t *testing.T) {
	var seen json.RawMessage
	h := newHarness(t, &stubTool{
		name: "ungated_tool",
		run: func(_ tools.ToolContext, params json.RawMessage) (any, error) {
			seen = params
			return map[string]any{"ok": true}, nil
		},
	})

	result, err := h.call(t, "ungated_tool")
	if err != nil {
		t.Fatalf("tools/call: %v", err)
	}
	if result.IsError {
		t.Fatalf("a no-argument call failed: %s", text(result))
	}
	if seen != nil && string(seen) != "{}" {
		t.Errorf("params = %s, want empty or an empty object", seen)
	}
}

func TestCallingAToolTheReaderCannotServeGivesTheStructuredCapabilityError(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	h.control.SetConnection(built.Connection)

	result, err := h.call(t, "gated_tool")
	if err != nil {
		t.Fatalf("it fell through to a protocol error: %v", err)
	}
	if !result.IsError {
		t.Fatal("a call the reader could not serve succeeded")
	}
	if !strings.Contains(text(result), "braille") {
		t.Errorf("content = %q, want the missing capability named", text(result))
	}
	if !strings.Contains(text(result), "nvda") {
		t.Errorf("content = %q, want the connected reader named", text(result))
	}
	if strings.Contains(text(result), "unknown tool") {
		t.Errorf("content = %q, want a capability error rather than the SDK's "+
			"unknown-tool answer", text(result))
	}
}

func TestCallingAGatedToolWithNoSessionSaysToConnectFirst(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())

	result, err := h.call(t, "gated_tool")
	if err != nil {
		t.Fatalf("it fell through to a protocol error: %v", err)
	}
	if !result.IsError || !strings.Contains(text(result), "connect_reader") {
		t.Errorf("content = %q, want it to name the tool that fixes this", text(result))
	}
}

func TestAGenuinelyUnknownToolStillGetsTheSDKsError(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())

	if _, err := h.call(t, "nonsense"); err == nil {
		t.Fatal("a call for a name that is not a tool succeeded")
	}
}

func TestAToolTheReaderCanServeRuns(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())
	built := testsupport.NewConnection("nvda", entities.CapabilityBraille)
	h.control.SetConnection(built.Connection)

	result, err := h.call(t, "gated_tool")
	if err != nil {
		t.Fatalf("tools/call: %v", err)
	}
	if result.IsError {
		t.Fatalf("a tool the reader announced was refused: %s", text(result))
	}
	if !strings.Contains(text(result), "reached") {
		t.Errorf("content = %q, want the tool's own answer", text(result))
	}
}

var errFailed = errors.New("the reader refused: unknown gesture id")
