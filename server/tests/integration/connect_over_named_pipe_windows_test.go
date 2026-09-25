//go:build integration && windows

// screenreader-mcp tests -- connecting to a bridge over a real named pipe.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario, Windows only, exercising the pipe leaf and pipe scan against the real namespace.
package integration_test

import (
	"encoding/json"
	"testing"
	"time"

	winio "github.com/Microsoft/go-winio"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery"
	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// The name is the test's own, so a real bridge installed on the machine can never satisfy the test.
func listenPipe(t *testing.T, fake *testsupport.FakeBridge, name string) string {
	t.Helper()
	listener, err := winio.ListenPipe(`\\.\pipe\`+name, nil)
	if err != nil {
		t.Fatalf("listening on pipe %s: %v", name, err)
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
	return name
}

func TestASessionIsEstablishedOverARealNamedPipe(t *testing.T) {
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	name := listenPipe(t, fake, "screenreaderMcpTestBridge")

	connection, err := newHandshake().Dial(
		testsupport.Reader(t, "nvda", "local:"+name),
		ports.SessionOptions{Mode: entities.CaptureSilent},
	)
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}
	t.Cleanup(func() { connection.Lifecycle.Close() })

	if _, err := connection.Lifecycle.Ping(); err != nil {
		t.Errorf("Ping over a real pipe: %v", err)
	}
}

// go-winio reports an idle read as winio.ErrTimeout, not os.ErrDeadlineExceeded, which the client would
// otherwise read as a dead connection.
func TestACommandSlowerThanThePollIntervalSurvivesOverARealPipe(t *testing.T) {
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	fake.Handle(wire.CommandGetSpeech, func(json.RawMessage) (any, error) {
		time.Sleep(6 * adapterports.PollInterval)
		return wire.SpeechResult{
			Entries:   []wire.SpeechEntry{{Text: "spoken slowly", Index: 1, LogPosition: 12}},
			FromIndex: 0,
			ToIndex:   1,
		}, nil
	})
	name := listenPipe(t, fake, "screenreaderMcpSlowTestBridge")

	connection, err := newHandshake().Dial(
		testsupport.Reader(t, "nvda", "local:"+name),
		ports.SessionOptions{Mode: entities.CaptureSilent},
	)
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}
	t.Cleanup(func() { connection.Lifecycle.Close() })

	captured, err := connection.Speech.SpeechSince(0)
	if err != nil {
		t.Fatalf("a slow command over a real pipe: %v", err)
	}
	if len(captured.Entries) != 1 || captured.Entries[0].Text != "spoken slowly" {
		t.Errorf("entries = %+v, want the slow answer", captured.Entries)
	}
}

func TestTheProbeSeesARealListeningPipe(t *testing.T) {
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	name := listenPipe(t, fake, "screenreaderMcpProbeTestBridge")

	probe := discovery.NewLocalProbe(discovery.NewLocalDirectory())
	listening := testsupport.Endpoint(t, "local:"+name)
	absent := testsupport.Endpoint(t, "local:screenreaderMcpNoSuchBridge")

	live := probe.Live([]entities.Endpoint{listening, absent})

	if len(live) != 1 || live[0] != listening {
		t.Errorf("live = %v, want exactly the pipe that is listening", live)
	}
}
