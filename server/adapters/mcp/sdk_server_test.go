// screenreader-mcp adapters -- the MCP server's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// These drive a real SDK client against a real SDK server over the SDK's
// in-memory transports, with a SYNTHETIC tool registry -- one ungated tool and
// one gated one -- rather than the production list.
//
// Synthetic on purpose: what is under test is the adapter's own behaviour
// (schema validation, the constant tool list, capability enforcement), and a
// registry stated in the test makes the gate's before-and-after visible in one
// screen. The production tools are exercised end to end by the integration tier,
// which is where they belong.
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

// stubTool is a tool with a stated name, gate and behaviour.
type stubTool struct {
	name       string
	capability entities.Capability
	schema     string
	// output is the declared OUTPUT schema, empty for the plain object one.
	// Separate from schema above rather than a second field nobody sets,
	// because the pair being independently wrong is what tool_binding_test.go
	// is about.
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

// harness is a bound server with a client attached.
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
		// The reader-guidance controller reads the same connection source, so a
		// harness whose subject is tool publication gets the real one rather
		// than a fifth double: with nothing connected it answers ErrNoSession
		// and the resource renders the "connect first" document.
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

// gatedStub asks its ToolContext for the capability it is gated on, exactly as
// every real gated tool does -- which is what makes the structured capability
// error the tool's own answer rather than something the adapter invents.
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

// Binding advertises EVERY tool, gated or not (spec 0022, option (c)).
//
// A freshly started server with nothing connected offers the whole surface, and
// what an agent cannot yet DO is answered per call rather than by an absence.
func TestBindingAdvertisesEveryTool(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())

	if names := h.names(t); !slices.Equal(names, []string{"gated_tool", "ungated_tool"}) {
		t.Errorf("tools/list = %v, want every tool advertised from startup", names)
	}
}

// THE PROPERTY 11.6 TURNS ON: the advertised list is a constant.
//
// A session beginning and ending changes nothing about it, so a client that
// listed once and cached the answer forever is holding a CORRECT answer. That is
// what closes both failures wearing entry 11.6's symptom -- our own redeploy
// freezing a client's list, and an external client that never re-listed -- and
// it is why no `tools/list_changed` is emitted at all any more.
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

	// And nothing was ANNOUNCED either. A client with no notification handling
	// at all must be no worse off, which is the half of entry 11.6 that no
	// client-side remedy could reach.
	select {
	case <-h.changed:
		t.Error("the server emitted tools/list_changed; nothing changed, so nothing should be announced")
	default:
	}
}

// The hand-written schema reaches the client as authored: it is the agent-facing
// contract, so the adapter must not be quietly rewriting it.
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

// A malformed schema is a STARTUP error naming the tool. The SDK panics on one,
// at the moment the tool is added -- which for a gated tool is mid-session, in a
// goroutine serving an agent.
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

// A tool failure is a RESULT with IsError, not a JSON-RPC error: an agent can
// read the content of an errored result and self-correct within the turn.
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

// A successful result is carried BOTH ways: structured for a client that can use
// it, and the same JSON as text for the many that read content only.
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

// A tool that takes no parameters must survive being called with none. What
// arrives is either an empty raw message or `{}`, depending on how the client
// spelled the call, and the domain's decodeParams tolerates both -- which is why
// no tool may assume it was handed a JSON object.
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

// ENFORCEMENT, now that advertisement does none of it. The tool is listed; the
// reader cannot serve it; the call gets the structured capability error.
//
// This is the test that shows what the list was never doing. It passed before
// through the capability backstop, which answered for tools that were HAD but
// not published -- and it passes now through the ordinary path, unchanged in
// what it asserts, because the backstop only ever delegated to the same
// dispatcher and the error always came from the tool's own ToolContext.
func TestCallingAToolTheReaderCannotServeGivesTheStructuredCapabilityError(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())
	// A reader that announced speech only: the braille-gated tool is listed,
	// and the connection has no BrailleReader to hand over.
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

// With nothing connected at all the answer is the other one -- "connect first" --
// because the two situations have entirely different remedies.
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

// A name that was never a tool still gets the SDK's own error. Advertising
// everything widens the list to every tool this server HAS, and not one further.
func TestAGenuinelyUnknownToolStillGetsTheSDKsError(t *testing.T) {
	h := newHarness(t, ungatedStub(), gatedStub())

	if _, err := h.call(t, "nonsense"); err == nil {
		t.Fatal("a call for a name that is not a tool succeeded")
	}
}

// And a reader that DOES announce the capability runs the tool for real.
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

// errFailed is a plain tool failure, distinct from any of the domain's own error
// types -- so the assertions above are about the adapter's mapping and not about
// which error it happened to be handed.
var errFailed = errors.New("the reader refused: unknown gesture id")
