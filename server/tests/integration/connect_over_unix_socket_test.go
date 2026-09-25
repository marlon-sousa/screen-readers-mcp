//go:build integration && !windows

// screenreader-mcp tests -- connecting to a bridge over a real Unix socket.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario, POSIX only, where the local socket derivation meets a real kernel; nothing here
// names a path, so the rendezvous by bare name is what is tested.
package integration_test

import (
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery"
	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// Not t.TempDir(): a unix socket path is capped at 103 usable bytes, and macOS's $TMPDIR alone takes 49.
func runtimeDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "srmcp")
	if err != nil {
		t.Fatalf("making a runtime directory: %v", err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	t.Setenv("XDG_RUNTIME_DIR", dir)
	return dir
}

// A socket file outlives the process that made it, so the listener unlinks before binding.
func listenSocket(t *testing.T, fake *testsupport.FakeBridge, name string) string {
	t.Helper()

	dir, err := entities.LocalSocketDir(entities.LocalSocketDirs{RuntimeDir: os.Getenv("XDG_RUNTIME_DIR")})
	if err != nil {
		t.Fatalf("resolving the socket directory: %v", err)
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		t.Fatalf("making %s: %v", dir, err)
	}
	path := filepath.Join(dir, name+".sock")
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		t.Fatalf("unlinking %s: %v", path, err)
	}

	listener, err := net.Listen("unix", path)
	if err != nil {
		t.Fatalf("listening on %s: %v", path, err)
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

func TestASessionIsEstablishedOverARealUnixSocket(t *testing.T) {
	runtimeDir(t)
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	name := listenSocket(t, fake, "screenreaderMcpTestBridge")

	connection, err := newHandshake().Dial(
		testsupport.Reader(t, "nvda", "local:"+name),
		ports.SessionOptions{Mode: entities.CaptureSilent},
	)
	if err != nil {
		t.Fatalf("Dial: %v", err)
	}
	t.Cleanup(func() { connection.Lifecycle.Close() })

	if _, err := connection.Lifecycle.Ping(); err != nil {
		t.Errorf("Ping over a real socket: %v", err)
	}
}

func TestACommandSlowerThanThePollIntervalSurvivesOverARealSocket(t *testing.T) {
	runtimeDir(t)
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	fake.Handle(wire.CommandGetSpeech, func(json.RawMessage) (any, error) {
		time.Sleep(6 * adapterports.PollInterval)
		return wire.SpeechResult{
			Entries:   []wire.SpeechEntry{{Text: "spoken slowly", Index: 1, LogPosition: 12}},
			FromIndex: 0,
			ToIndex:   1,
		}, nil
	})
	name := listenSocket(t, fake, "screenreaderMcpSlowTestBridge")

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
		t.Fatalf("a slow command over a real socket: %v", err)
	}
	if len(captured.Entries) != 1 || captured.Entries[0].Text != "spoken slowly" {
		t.Errorf("entries = %+v, want the slow answer", captured.Entries)
	}
}

func TestTheProbeSeesARealListeningSocket(t *testing.T) {
	runtimeDir(t)
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	name := listenSocket(t, fake, "screenreaderMcpProbeTestBridge")

	probe := discovery.NewLocalProbe(discovery.NewLocalDirectory())
	listening := testsupport.Endpoint(t, "local:"+name)
	absent := testsupport.Endpoint(t, "local:screenreaderMcpNoSuchBridge")

	live := probe.Live([]entities.Endpoint{listening, absent})

	if len(live) != 1 || live[0] != listening {
		t.Errorf("live = %v, want exactly the socket that is listening", live)
	}
}

// A TCP endpoint cannot be probed without taking the bridge's one session slot, so it reports unknown.
func TestTheListingReportsARealSocketAsListening(t *testing.T) {
	runtimeDir(t)
	fake := testsupport.NewFakeBridge(testsupport.BridgeOptions{})
	name := listenSocket(t, fake, "screenreaderMcpListingTestBridge")
	reader := testsupport.Reader(t, "nvda", "local:"+name, "tcp:127.0.0.1:8765")

	probe := discovery.NewLocalProbe(discovery.NewLocalDirectory())
	listing := entities.BuildListing([]entities.ConfiguredReader{reader}, probe.Live(reader.Endpoints))

	endpoints := listing.Readers[0].Endpoints
	if endpoints[0].Liveness != entities.Listening {
		t.Errorf("local endpoint liveness = %q, want %q", endpoints[0].Liveness, entities.Listening)
	}
	if endpoints[1].Liveness != entities.LivenessUnknown {
		t.Errorf("tcp endpoint liveness = %q, want %q", endpoints[1].Liveness, entities.LivenessUnknown)
	}
}
