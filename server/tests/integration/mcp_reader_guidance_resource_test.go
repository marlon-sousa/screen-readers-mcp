//go:build integration

// screenreader-mcp tests -- screenreader://reader-guidance, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario. Spec 0029 Part 4: the reader says what its own
// vocabulary is, and the server frames it without reading it.
//
// Asserting on prose is usually a bad trade, so this file asserts the decisions
// rather than the wording: that the bridge's own text reaches the agent
// unaltered, that the frame stating precedence is around it, that both degraded
// states are documents rather than errors, that a second read costs no round
// trip, and that the URI connect_reader hands out is really published. Every one
// of those is silently wrong-looking-right if broken.
package integration_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/mcp"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// Registered like the other three, so an agent that reads it too early gets an
// explanation rather than a resource-not-found -- which reads as a fault in this
// server and tells the agent nothing about what to do next.
func TestTheReaderGuidanceIsPublishedBeforeAnythingIsConnected(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})

	if !contains(h.ResourceURIs(t), mcp.ReaderGuidanceURI) {
		t.Fatalf("resources/list = %v, want %s among them", h.ResourceURIs(t), mcp.ReaderGuidanceURI)
	}

	document := h.ReadReaderGuidance(t)
	for _, want := range []string{
		// It says which state this is...
		"No reader is connected",
		// ...and what to read in the meantime, which is the whole point of
		// answering rather than erroring.
		"screenreader://guidance",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the no-session document never says %q:\n%s", want, document)
		}
	}
}

// The bridge's text arrives whole, with the precedence frame around it. The
// phrase asserted on comes from the FAKE BRIDGE, so it could not have been
// produced by anything on this side of the wire.
func TestTheReadersOwnTextArrivesFramedByTheServer(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	h.ConnectAs(t, "validator")

	document := h.ReadReaderGuidance(t)

	if !strings.Contains(document, testsupport.DefaultGuidanceText) {
		t.Errorf("the bridge's own text did not reach the agent intact:\n%s", document)
	}
	for _, want := range []string{
		// Whose account this is, and for which stance -- both substituted into
		// the frame from the live session.
		"fakereader",
		"validator",
		// The precedence rule (spec 0029 4.1). The server never parses the
		// bridge's text and so can never check it; stating precedence in the
		// frame is what enforces it where it is actually decided, in the
		// agent's reading.
		"screenreader://guidance",
		"the stance wins",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the framed document never says %q:\n%s", want, document)
		}
	}
}

// Cached for the session (spec 0029 4.4). Counted at the BRIDGE, because that is
// the round trip the cache exists to avoid -- counting reads at the resource
// would prove nothing.
func TestReadingTheReaderGuidanceTwiceMakesOneRoundTrip(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	h.Connect(t)

	h.ReadReaderGuidance(t)
	h.ReadReaderGuidance(t)

	fetches := 0
	for _, command := range h.Bridge.Received() {
		if command == wire.CommandGetGuidance {
			fetches++
		}
	}
	if fetches != 1 {
		t.Errorf("the bridge was asked for its guidance %d times; want 1", fetches)
	}
}

// Nothing is fetched at connect: a session that never asks never pays, and
// connect stays one round trip.
func TestConnectingDoesNotFetchTheReaderGuidance(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{})
	h.Connect(t)

	for _, command := range h.Bridge.Received() {
		if command == wire.CommandGetGuidance {
			t.Fatal("connect fetched the guidance; it must be lazy")
		}
	}
}

// A bridge that announced no `guidance` is a supported configuration, not a
// fault -- so the agent is told that, told the rule still holds, and told what
// to do instead.
func TestABridgeWithoutTheCapabilityYieldsADocumentAndNotAnError(t *testing.T) {
	h := testsupport.StartMCP(t, testsupport.BridgeOptions{
		Capabilities: []wire.Capability{wire.CapabilitySpeech},
	})
	h.Connect(t)

	document := h.ReadReaderGuidance(t)
	for _, want := range []string{
		"publishes no guidance of its own",
		// The rule survives the reader having nothing to say about it, which is
		// the sentence that keeps this from reading as "anything goes".
		"reaches what focus cannot",
	} {
		if !strings.Contains(document, want) {
			t.Errorf("the unavailable document never says %q:\n%s", want, document)
		}
	}
}

// An unrecognised persona gets the bridge's general text AND is told so. Silence
// would leave the agent believing it had been instructed for its stance.
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

// connect_reader names the resource at the earliest instant it exists (spec 0029
// 3.4), and the URI it names must be one that is really published. The domain
// cannot import the adapter, so the constant is repeated there -- this is the
// guard that keeps the repetition honest, and a dangling pointer here is
// invisible to every other test: the call succeeds and the agent gets a
// resource-not-found at the moment it takes our advice.
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

// And it is ABSENT rather than misleading when the reader publishes none: a URI
// naming a document that would only say "this reader has nothing to say" is
// worse than no field, because an agent would spend a read finding out.
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

// The persona the bridge is asked about is the session's, so reconnecting under
// a different one produces a different document rather than the cached first.
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
