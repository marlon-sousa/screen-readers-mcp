//go:build integration

// screenreader-mcp tests -- connecting to a bridge over real loopback TCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario over a real loopback TCP leaf, through the production dialing composition.
package integration_test

import (
	"encoding/json"
	"net"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/bridge"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func listenLoopback(t *testing.T, fake *testsupport.FakeBridge) string {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listening on loopback: %v", err)
	}
	t.Cleanup(func() { listener.Close() })

	go func() {
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			go fake.Serve(conn)
		}
	}()
	return "tcp:" + listener.Addr().String()
}

func newHandshake() *bridge.Handshake {
	return bridge.NewHandshake(bridge.DialerFor, fakes.NewFakeClock(), fakes.NewFakeLog())
}

func TestASessionIsEstablishedOverRealLoopbackTCP(t *testing.T) {
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{
		Reader: wire.ReaderInfo{Name: "nvda", Version: "2026.1"},
	})
	spec := listenLoopback(t, fake)

	connection, err := newHandshake().Dial(
		testsupport.Reader(t, "nvda", spec),
		ports.SessionOptions{Mode: entities.CaptureSilent},
	)
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}
	t.Cleanup(func() { connection.Lifecycle.Close() })

	if connection.Session.Reader.Name != "nvda" {
		t.Errorf("reader = %q, want the one hello announced", connection.Session.Reader.Name)
	}
	if connection.Endpoint.String() != spec {
		t.Errorf("answered by %s, want %s", connection.Endpoint, spec)
	}
}

func TestACommandRoundTripsOverRealLoopbackTCP(t *testing.T) {
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	fake.Handle(wire.CommandGetSpeech, func(params json.RawMessage) (any, error) {
		return wire.SpeechResult{
			Entries:   []wire.SpeechEntry{{Text: "Edit  blank", Index: 1, LogPosition: 12}},
			FromIndex: 0,
			ToIndex:   1,
		}, nil
	})
	spec := listenLoopback(t, fake)

	connection, err := newHandshake().Dial(
		testsupport.Reader(t, "nvda", spec),
		ports.SessionOptions{Mode: entities.CaptureSilent},
	)
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}
	t.Cleanup(func() { connection.Lifecycle.Close() })

	speech, err := connection.Speech.SpeechSince(0)
	if err != nil {
		t.Fatalf("SpeechSince: %v", err)
	}
	if len(speech.Entries) != 1 || speech.Entries[0].Text != "Edit  blank" || speech.ToIndex != 1 {
		t.Errorf("speech = %+v, want the bridge's own answer", speech)
	}
	if speech.Entries[0].LogPosition != 12 {
		t.Errorf("logPosition = %d, want the 12 the bridge sent", speech.Entries[0].LogPosition)
	}
}

func TestADeadFirstEndpointFallsThroughToTheSecond(t *testing.T) {
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	live := listenLoopback(t, fake)

	// A port that was listening and is not any more stands in for a bridge switched to the other transport.
	dead, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listening: %v", err)
	}
	deadSpec := "tcp:" + dead.Addr().String()
	dead.Close()

	connection, err := newHandshake().Dial(
		testsupport.Reader(t, "nvda", deadSpec, live),
		ports.SessionOptions{Mode: entities.CaptureSilent},
	)
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}
	t.Cleanup(func() { connection.Lifecycle.Close() })

	if connection.Endpoint.String() != live {
		t.Errorf("answered by %s, want the second endpoint %s", connection.Endpoint, live)
	}
}

func TestDisconnectingSendsBye(t *testing.T) {
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	spec := listenLoopback(t, fake)

	connection, err := newHandshake().Dial(
		testsupport.Reader(t, "nvda", spec),
		ports.SessionOptions{Mode: entities.CaptureSilent},
	)
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}

	if err := connection.Lifecycle.Bye(); err != nil {
		t.Fatalf("Bye: %v", err)
	}
	if err := connection.Lifecycle.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}
	if !fake.SawBye() {
		t.Error("the bridge never saw bye")
	}
}
