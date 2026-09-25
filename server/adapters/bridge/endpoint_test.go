// screenreader-mcp adapters -- tests for endpoint.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
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

func TestDialerForResolvesTheLocalEndpointOnEveryPlatform(t *testing.T) {
	dial, err := bridge.DialerFor(testsupport.Endpoint(t, "local:nvdaMcpBridge"))
	if err != nil {
		t.Fatalf("DialerFor(local): %v", err)
	}
	if dial == nil {
		t.Error("no dialer returned for a local endpoint")
	}
}

// `pipe:` is an alias kept because it appears in shipped defaults and existing config files.
func TestDialerForAcceptsThePipeAlias(t *testing.T) {
	dial, err := bridge.DialerFor(testsupport.Endpoint(t, "pipe:nvdaMcpBridge"))
	if err != nil {
		t.Fatalf("DialerFor(pipe alias): %v", err)
	}
	if dial == nil {
		t.Error("no dialer returned for the alias of an endpoint we do dial")
	}
}

// Windows has no sockaddr_un length limit, so the case is POSIX-only.
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
