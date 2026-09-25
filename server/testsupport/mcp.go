// screenreader-mcp testsupport -- a real MCP client driving the real server.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: test scaffolding assembling the whole production stack with only the bridge faked, reached over loopback.
// USED BY: server/tests/integration/ and the conformance tier.
package testsupport

import (
	"context"
	"encoding/json"
	"net"
	"testing"
	"time"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/wiring"
)

type MCPHarness struct {
	Session *sdk.ClientSession

	// Nil when the server under test is a separate process, as in the conformance tier.
	Server *wiring.Server

	// Nil when the bridge is real.
	Bridge *FakeBridge

	ToolsChanged chan struct{}
}

func StartMCP(t *testing.T, options BridgeOptions) *MCPHarness {
	t.Helper()

	bridge := NewFakeBridge(options)
	address := listen(t, bridge)

	server, err := wiring.Build(wiring.Options{
		ReaderFlags: []string{"nvda=tcp:" + address},
	})
	if err != nil {
		t.Fatalf("building the server: %v", err)
	}
	t.Cleanup(server.Connection.Close)

	ctx := context.Background()
	clientTransport, serverTransport := sdk.NewInMemoryTransports()

	serverSession, err := server.MCP.Connect(ctx, serverTransport)
	if err != nil {
		t.Fatalf("connecting the server: %v", err)
	}
	t.Cleanup(func() { _ = serverSession.Close() })

	harness := AttachMCP(t, clientTransport)
	harness.Server = server
	harness.Bridge = bridge
	return harness
}

func AttachMCP(t *testing.T, transport sdk.Transport) *MCPHarness {
	t.Helper()

	changed := make(chan struct{}, 32)
	client := sdk.NewClient(&sdk.Implementation{Name: "test-client", Version: "0"}, &sdk.ClientOptions{
		ToolListChangedHandler: func(context.Context, *sdk.ToolListChangedRequest) {
			// Non-blocking, so a test that ignores the notification cannot deadlock the SDK's reader.
			select {
			case changed <- struct{}{}:
			default:
			}
		},
	})

	session, err := client.Connect(context.Background(), transport, nil)
	if err != nil {
		t.Fatalf("connecting the client: %v", err)
	}
	t.Cleanup(func() { _ = session.Close() })

	return &MCPHarness{Session: session, ToolsChanged: changed}
}

func listen(t *testing.T, bridge *FakeBridge) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listening on loopback: %v", err)
	}
	t.Cleanup(func() { _ = listener.Close() })

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go bridge.Serve(conn)
		}
	}()
	return listener.Addr().String()
}

func (h *MCPHarness) ToolNames(t *testing.T) []string {
	t.Helper()
	listing, err := h.Session.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatalf("tools/list: %v", err)
	}
	names := make([]string, 0, len(listing.Tools))
	for _, tool := range listing.Tools {
		names = append(names, tool.Name)
	}
	return names
}

func (h *MCPHarness) Advertises(t *testing.T, name string) bool {
	t.Helper()
	for _, advertised := range h.ToolNames(t) {
		if advertised == name {
			return true
		}
	}
	return false
}

type ToolResult struct {
	Text string

	IsError bool
}

func (h *MCPHarness) Call(t *testing.T, name string, arguments map[string]any) ToolResult {
	t.Helper()
	result, err := h.Session.CallTool(context.Background(), &sdk.CallToolParams{
		Name: name, Arguments: arguments,
	})
	if err != nil {
		t.Fatalf("tools/call %s: %v", name, err)
	}
	answer := ToolResult{IsError: result.IsError}
	if len(result.Content) > 0 {
		if text, ok := result.Content[0].(*sdk.TextContent); ok {
			answer.Text = text.Text
		}
	}
	return answer
}

func (h *MCPHarness) CallExpectingProtocolError(t *testing.T, name string) error {
	t.Helper()
	_, err := h.Session.CallTool(context.Background(), &sdk.CallToolParams{Name: name})
	if err == nil {
		t.Fatalf("tools/call %s succeeded; a protocol error was expected", name)
	}
	return err
}

func (r ToolResult) Decode(t *testing.T, into any) {
	t.Helper()
	if r.IsError {
		t.Fatalf("the call failed: %s", r.Text)
	}
	if err := json.Unmarshal([]byte(r.Text), into); err != nil {
		t.Fatalf("decoding %s: %v", r.Text, err)
	}
}

func (h *MCPHarness) Connect(t *testing.T) ToolResult {
	t.Helper()
	return h.ConnectAs(t, "user")
}

func (h *MCPHarness) ConnectAs(t *testing.T, persona string) ToolResult {
	t.Helper()
	return h.Call(t, "connect_reader", map[string]any{
		"reader": "nvda", "mode": "silent", "persona": persona,
	})
}

func (h *MCPHarness) ReadInfo(t *testing.T) map[string]any {
	t.Helper()
	return h.ReadResource(t, "screenreader://info")
}

func (h *MCPHarness) ReadSessionRecord(t *testing.T) map[string]any {
	t.Helper()
	return h.ReadResource(t, "screenreader://session-record")
}

func (h *MCPHarness) ResourceURIs(t *testing.T) []string {
	t.Helper()
	listing, err := h.Session.ListResources(context.Background(), nil)
	if err != nil {
		t.Fatalf("resources/list: %v", err)
	}
	uris := make([]string, 0, len(listing.Resources))
	for _, resource := range listing.Resources {
		uris = append(uris, resource.URI)
	}
	return uris
}

func (h *MCPHarness) ReadGuidance(t *testing.T) string {
	t.Helper()
	return h.ReadResourceText(t, "screenreader://guidance")
}

func (h *MCPHarness) ReadReaderGuidance(t *testing.T) string {
	t.Helper()
	return h.ReadResourceText(t, "screenreader://reader-guidance")
}

func (h *MCPHarness) ReadResourceText(t *testing.T, uri string) string {
	t.Helper()
	read, err := h.Session.ReadResource(context.Background(), &sdk.ReadResourceParams{URI: uri})
	if err != nil {
		t.Fatalf("reading %s: %v", uri, err)
	}
	return read.Contents[0].Text
}

func (h *MCPHarness) ReadResource(t *testing.T, uri string) map[string]any {
	t.Helper()
	read, err := h.Session.ReadResource(context.Background(), &sdk.ReadResourceParams{URI: uri})
	if err != nil {
		t.Fatalf("reading %s: %v", uri, err)
	}
	var document map[string]any
	if err := json.Unmarshal([]byte(read.Contents[0].Text), &document); err != nil {
		t.Fatalf("decoding %s: %v", uri, err)
	}
	return document
}

// The settle is a real timeout because it waits on the SDK's own scheduling, which no injected clock reaches.
func (h *MCPHarness) AssertNoToolsChanged(t *testing.T) {
	t.Helper()
	select {
	case <-h.ToolsChanged:
		t.Error("the server emitted tools/list_changed; the advertised list must be a constant")
	case <-time.After(250 * time.Millisecond):
	}
}
