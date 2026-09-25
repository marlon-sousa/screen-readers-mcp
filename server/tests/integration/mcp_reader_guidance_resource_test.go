//go:build integration

// screenreader-mcp tests -- screenreader://reader-guidance, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario for screenreader://reader-guidance, which the server frames without reading.
package integration_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/mcp"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestTheReaderGuidanceIsPublishedBeforeAnythingIsConnected(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	if !contains(h.ResourceURIs(t), mcp.ReaderGuidanceURI) {
		t.Fatalf("resources/list = %v, want %s among them", h.ResourceURIs(t), mcp.ReaderGuidanceURI)
	}

	document := h.ReadReaderGuidance(t)
	for _, want := range []string{
		"No reader is connected",
		"screenreader://guidance",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the no-session document never says %q:\n%s", want, document)
		}
	}
}

// The phrase comes from the fake bridge, so nothing on this side of the wire could produce it.
func TestTheReadersOwnTextArrivesFramedByTheServer(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	h.ConnectAs(t, "validator")

	document := h.ReadReaderGuidance(t)

	if !strings.Contains(document, testsupport.DefaultGuidanceText) {
		t.Errorf("the bridge's own text did not reach the agent intact:\n%s", document)
	}
	for _, want := range []string{
		"fakereader",
		"validator",
		"screenreader://guidance",
		"the stance wins",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the framed document never says %q:\n%s", want, document)
		}
	}
}

func TestReadingTheReaderGuidanceCostsNoRoundTripAtAll(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	h.Connect(t)

	first := h.ReadReaderGuidance(t)
	second := h.ReadReaderGuidance(t)

	if fetches := guidanceFetches(h); fetches != 0 {
		t.Errorf("the bridge was asked for its guidance %d times; want 0 -- the "+
			"handshake already carried it", fetches)
	}
	if first != second {
		t.Error("two reads of one session's guidance returned different documents")
	}
	if first == "" {
		t.Error("the document is empty; the handshake copy never reached the resource")
	}
}

func TestAnOlderBridgeStillServesItsGuidanceInOneRoundTrip(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{OmitHandshakeGuidance: true})
	h.Connect(t)

	first := h.ReadReaderGuidance(t)
	h.ReadReaderGuidance(t)

	if fetches := guidanceFetches(h); fetches != 1 {
		t.Errorf("the bridge was asked for its guidance %d times; want exactly 1 -- "+
			"fetched because the handshake carried none, then cached", fetches)
	}
	if !strings.Contains(first, testsupport.DefaultGuidanceText) {
		t.Errorf("the fetched document did not reach the resource:\n%s", first)
	}
}

func guidanceFetches(h *testsupport.MCPHarness) int {
	fetches := 0
	for _, command := range h.Bridge.Received() {
		if command == wire.CommandGetGuidance {
			fetches++
		}
	}
	return fetches
}

func TestConnectingDoesNotFetchTheReaderGuidance(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	h.Connect(t)

	for _, command := range h.Bridge.Received() {
		if command == wire.CommandGetGuidance {
			t.Fatal("connect fetched the guidance; it must be lazy")
		}
	}
}

func TestABridgeWithoutTheCapabilityYieldsADocumentAndNotAnError(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Capabilities: []wire.Capability{wire.CapabilitySpeech},
	})
	h.Connect(t)

	document := h.ReadReaderGuidance(t)
	for _, want := range []string{
		"publishes no guidance of its own",
		"reaches what focus cannot",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the unavailable document never says %q:\n%s", want, document)
		}
	}
}

func TestAnUnrecognisedPersonaIsSaidOutLoud(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	h.Bridge.Handle(wire.CommandGetGuidance, func(json.RawMessage) (any, error) {
		return wire.GetGuidanceResult{
			Persona:    "user",
			Recognised: false,
			Text:       "this bridge's general guidance",
		}, nil
	})
	h.Connect(t)

	document := h.ReadReaderGuidance(t)
	if !strings.Contains(document, "this bridge's general guidance") {
		t.Errorf("the general text was withheld:\n%s", document)
	}
	if !strings.Contains(document, "did not recognise the persona") {
		t.Errorf("the agent was not told the persona went unrecognised:\n%s", document)
	}
}

// The domain cannot import the adapter, so it repeats this URI; this keeps the two copies equal.
func TestConnectNamesTheReaderGuidanceResourceAndItIsPublished(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	var result struct {
		ReaderGuidance string `json:"readerGuidance"`
	}
	h.ConnectAs(t, "expert").Decode(t, &result)

	if result.ReaderGuidance != mcp.ReaderGuidanceURI {
		t.Fatalf("connect_reader returned readerGuidance %q, want %q",
			result.ReaderGuidance, mcp.ReaderGuidanceURI)
	}
	if !contains(h.ResourceURIs(t), result.ReaderGuidance) {
		t.Errorf("connect_reader points at %s, which resources/list does not publish: %v",
			result.ReaderGuidance, h.ResourceURIs(t))
	}
}

func TestConnectOmitsTheResourceWhenTheReaderPublishesNone(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Capabilities: []wire.Capability{wire.CapabilitySpeech},
	})

	var result map[string]any
	h.Connect(t).Decode(t, &result)

	if got, present := result["readerGuidance"]; present {
		t.Errorf("readerGuidance = %v, want absent for a bridge that announced no guidance", got)
	}
}

func TestReconnectingUnderAnotherPersonaServesTheNewStance(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	h.ConnectAs(t, "user")
	first := h.ReadReaderGuidance(t)
	h.Call(t, "disconnect_reader", nil)

	h.ConnectAs(t, "expert")
	second := h.ReadReaderGuidance(t)

	if !strings.Contains(first, "`user` stance") {
		t.Errorf("the first document did not frame the user stance:\n%s", first)
	}
	if !strings.Contains(second, "`expert` stance") {
		t.Errorf("the second document served the previous session's stance:\n%s", second)
	}
}

func TestConnectingReturnsTheReaderGuidanceInFull(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	var result struct {
		ReaderGuidance     string `json:"readerGuidance"`
		ReaderGuidanceText string `json:"readerGuidanceText"`
	}
	h.Connect(t).Decode(t, &result)

	if result.ReaderGuidanceText != testsupport.DefaultGuidanceText {
		t.Errorf("readerGuidanceText = %q, want the bridge's own document %q",
			result.ReaderGuidanceText, testsupport.DefaultGuidanceText)
	}
	if result.ReaderGuidance == "" {
		t.Error("readerGuidance is empty; the resource must still be named for a re-read")
	}
	if fetches := guidanceFetches(h); fetches != 0 {
		t.Errorf("connecting made %d getGuidance round trips; want 0", fetches)
	}
}

func TestConnectingToABridgeWithNoGuidanceOmitsTheDocument(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilitySpeech))

	var result struct {
		ReaderGuidance     string `json:"readerGuidance"`
		ReaderGuidanceText string `json:"readerGuidanceText"`
	}
	connected := h.Connect(t)
	if connected.IsError {
		t.Fatalf("connect_reader: %s", connected.Text)
	}
	connected.Decode(t, &result)

	if result.ReaderGuidanceText != "" {
		t.Errorf("readerGuidanceText = %q, want it absent for a reader that "+
			"announced no guidance", result.ReaderGuidanceText)
	}
	if result.ReaderGuidance != "" {
		t.Errorf("readerGuidance = %q, want it absent too -- an absent field is "+
			"the honest answer, not a pointer at a document that explains nothing",
			result.ReaderGuidance)
	}
}
