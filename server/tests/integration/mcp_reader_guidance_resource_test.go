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

// ZERO round trips, however many times it is read (spec 0022 A.5).
//
// This test used to want ONE, and the change is the point: spec 0029 4.4 made
// the fetch lazy and cached, so a first read paid a round trip and later reads
// did not. The document now arrives in the handshake, so no read pays. Counted
// at the BRIDGE, because that is the round trip in question -- counting reads at
// the resource would prove nothing.
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

// A bridge built before the handshake carried the document still works, and
// still pays only once.
//
// THE FORWARD-COMPATIBILITY PROMISE, TESTED. protocol.md §2 says unknown fields
// are ignored in both directions, which is what lets wire v1 be amended in
// place -- but an older BRIDGE simply omits the field, and the server has to
// notice and fall back to `getGuidance`. Spec 0029 4.4's lazy cache survives for
// exactly this path, which is why it was kept rather than deleted.
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

// guidanceFetches counts the getGuidance round trips this bridge was asked for.
func guidanceFetches(h *testsupport.MCPHarness) int {
	fetches := 0
	for _, command := range h.Bridge.Received() {
		if command == wire.CommandGetGuidance {
			fetches++
		}
	}
	return fetches
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

// THE DOCUMENT ARRIVES WITH THE SESSION, not on a request for it (spec 0022 A.5).
//
// The URI stays beside it, for a re-read; what changed is that an agent which
// never reads a resource still has the vocabulary. That is the failure this
// answers: two external runs (specs 0027 and 0030) each held a pointer to this
// document and each went elsewhere -- one to PowerShell, one to the Go source.
//
// It matters more under option (c) than it would have before. Every tool is
// advertised from startup, so the tool list no longer narrows itself to what
// this reader can do; this is where an agent learns that, unasked.
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
	// And the pointer survives: re-reading mid-session must not mean scrolling
	// back through a transcript.
	if result.ReaderGuidance == "" {
		t.Error("readerGuidance is empty; the resource must still be named for a re-read")
	}
	// It cost nothing. connect is still one round trip (spec 0025).
	if fetches := guidanceFetches(h); fetches != 0 {
		t.Errorf("connecting made %d getGuidance round trips; want 0", fetches)
	}
}

// A bridge that publishes none says so by omission, and connect still succeeds.
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
