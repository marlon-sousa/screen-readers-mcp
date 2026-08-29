// screenreader-mcp adapters -- tests for endpoint.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Nothing here dials: DialerFor decides WHETHER an endpoint may be reached and
// returns how, so the decisions are testable with no OS involved. That the leaf
// underneath then works is the real-transport tier's job, not this one's.
package bridge_test

import (
	"runtime"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/bridge"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestDialerForAcceptsLoopbackTCP(t *testing.T) {
	for _, spec := range []string{"tcp:127.0.0.1:8765", "tcp:localhost:8765", "tcp:[::1]:8765"} {
		t.Run(spec, func(t *testing.T) {
			dial, err := bridge.DialerFor(testsupport.Endpoint(t, spec))
			if err != nil {
				t.Fatalf("DialerFor(%s): %v", spec, err)
			}
			if dial == nil {
				t.Error("no dialer returned for an acceptable endpoint")
			}
		})
	}
}

// The wire contract says the connection is always local-machine-only, and remote
// TCP is deferred behind its own security spec. Enforcing it here means a config
// file cannot quietly turn this server into something that reaches across a
// network.
func TestDialerForRefusesNonLoopbackTCP(t *testing.T) {
	for _, spec := range []string{"tcp:192.168.1.10:8765", "tcp:example.com:8765", "tcp:0.0.0.0:8765"} {
		t.Run(spec, func(t *testing.T) {
			_, err := bridge.DialerFor(testsupport.Endpoint(t, spec))
			if err == nil {
				t.Fatalf("DialerFor(%s) succeeded; only loopback endpoints may be dialed", spec)
			}
			if !strings.Contains(err.Error(), spec[len("tcp:"):]) {
				t.Errorf("error %q does not name the endpoint that was refused", err)
			}
		})
	}
}

// The local endpoint resolves on EVERY platform now (spec 0044): a named pipe on
// Windows, a Unix domain socket on POSIX. Until then this test asserted the
// opposite -- that a non-Windows host refused and pointed at TCP -- which is
// what a bridge for a reader that does not run on Windows would have hit.
func TestDialerForResolvesTheLocalEndpointOnEveryPlatform(t *testing.T) {
	dial, err := bridge.DialerFor(testsupport.Endpoint(t, "local:nvdaMcpBridge"))
	if err != nil {
		t.Fatalf("DialerFor(local): %v", err)
	}
	if dial == nil {
		t.Error("no dialer returned for a local endpoint")
	}
}

// `pipe:` is the spelling the local endpoint had until spec 0044, and it is
// kept forever because it is in shipped defaults, in help text, in the published
// contract and in config files people already have.
func TestDialerForAcceptsThePipeAlias(t *testing.T) {
	dial, err := bridge.DialerFor(testsupport.Endpoint(t, "pipe:nvdaMcpBridge"))
	if err != nil {
		t.Fatalf("DialerFor(pipe alias): %v", err)
	}
	if dial == nil {
		t.Error("no dialer returned for the alias of an endpoint we do dial")
	}
}

// A socket path that cannot fit in a sockaddr_un is reported where the
// configuration is READ, naming the endpoint the user wrote -- not at the moment
// an agent asks to connect, where the OS answers `connect: invalid argument` and
// names neither the limit nor the fix.
//
// Windows has no such limit, so the case is POSIX-only. The RULE is tested on
// every host in domain/entities/local_socket_test.go; what this asserts is that
// DialerFor surfaces it at build time rather than swallowing it.
func TestDialerForRefusesAnOverlongSocketPath(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("sockaddr_un has no counterpart in the named-pipe namespace")
	}
	address := "/tmp/" + strings.Repeat("a", entities.MaxLocalSocketPath) + ".sock"

	_, err := bridge.DialerFor(testsupport.Endpoint(t, "local:"+address))

	if err == nil {
		t.Fatal("DialerFor succeeded on a path no unix socket can carry")
	}
	if !strings.Contains(err.Error(), "bytes") {
		t.Errorf("error %q does not say what the limit is", err)
	}
}
