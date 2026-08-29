//go:build integration && !windows

// screenreader-mcp tests -- connecting to a bridge over a real Unix socket.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario, POSIX only -- the real-transport tier for the
// LOCAL endpoint as POSIX spells it. Its Windows sibling is
// connect_over_named_pipe_windows_test.go, and the pair is the point: one
// endpoint kind, two mechanisms, the same scenarios either side.
//
// This is where the derivation in domain/entities/local_socket.go meets a real
// kernel: the bridge binds where the rule says a bridge binds, the server dials
// a BARE NAME and finds it, and the probe reads the same directory and reports
// it listening. Nothing in it names a path -- if it did, it would be testing the
// override rather than the rendezvous.
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

// runtimeDir points XDG_RUNTIME_DIR at a directory of this test's own, so the
// derivation resolves somewhere disposable instead of into the developer's home.
//
// NOT t.TempDir(), and the reason is the constraint this whole file is about: a
// unix socket path is capped at 103 usable bytes, macOS's $TMPDIR is 49 of them
// before anything else, and t.TempDir() then adds the test's name. The budget is
// gone before the socket is. /tmp is short, present on every POSIX host, and
// this is a test.
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

// listenSocket starts the fake bridge where a bridge of that name belongs, and
// returns the bare name -- exactly what a configured endpoint carries.
//
// It creates the directory 0700 and unlinks before binding, which are the
// LISTENER's obligations under specs/wire/v1 §1: a socket file outlives the
// process that made it, unlike a pipe.
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

// The POSIX half of the regression the pipe leaf carries: a command that takes
// longer than one poll interval must still succeed. net.Conn reports a passed
// deadline as os.ErrDeadlineExceeded, which is the seam's contract, so this
// should fall out for free -- and asserting it is how we know the unix leaf
// really is the shared net leaf and not a second implementation of it.
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

// The probe against a real directory. Until spec 0044 this could not be written
// at all off Windows: the non-Windows listing was empty by construction, so
// every endpoint reported liveness unknown and `list_readers`'s liveness column
// was a constant on the host lane 3 is built on.
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

// The whole listing, end to end: a configured reader whose local endpoint is up
// reports LISTENING, and its TCP endpoint -- which cannot be probed without
// taking the bridge's one session slot -- reports unknown.
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
