// screenreader-mcp domain -- tests for endpoint.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// The spelling tested here is the one that appears in defaults.json, in a
// --config file and in a --reader flag, so these cases are the contract with
// whoever writes a configuration by hand.
package entities_test

import (
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func TestParseEndpointAcceptsTheTwoTransports(t *testing.T) {
	cases := []struct {
		spec string
		want entities.Endpoint
	}{
		{"local:nvdaMcpBridge", entities.Endpoint{Kind: entities.TransportLocal, Address: "nvdaMcpBridge"}},
		{"tcp:127.0.0.1:8765", entities.Endpoint{Kind: entities.TransportTCP, Address: "127.0.0.1:8765"}},
	}

	for _, c := range cases {
		t.Run(c.spec, func(t *testing.T) {
			got, err := entities.ParseEndpoint(c.spec)
			if err != nil {
				t.Fatalf("ParseEndpoint(%q): %v", c.spec, err)
			}
			if diff := cmp.Diff(c.want, got); diff != "" {
				t.Errorf("parsed (-want +got):\n%s", diff)
			}
		})
	}
}

// A TCP address carries its own colon, so only the FIRST separates the kind. If
// this regressed, `tcp:127.0.0.1:8765` would silently lose its port.
func TestParseEndpointKeepsTheAddressColon(t *testing.T) {
	got, err := entities.ParseEndpoint("tcp:127.0.0.1:8765")
	if err != nil {
		t.Fatalf("ParseEndpoint: %v", err)
	}
	if got.Address != "127.0.0.1:8765" {
		t.Errorf("address = %q, want the host AND the port", got.Address)
	}
}

func TestParseEndpointRejectsMalformedSpecs(t *testing.T) {
	for _, spec := range []string{"", "nvdaMcpBridge", "local:", "pipe:", "tcp:127.0.0.1", "smoke:signals"} {
		t.Run(spec, func(t *testing.T) {
			if _, err := entities.ParseEndpoint(spec); err == nil {
				t.Errorf("ParseEndpoint(%q) succeeded; want an error naming the spelling", spec)
			}
		})
	}
}

// What an agent is shown must be writable straight back into a --reader flag.
func TestEndpointStringRoundTrips(t *testing.T) {
	for _, spec := range []string{"local:nvdaMcpBridge", "tcp:127.0.0.1:8765"} {
		t.Run(spec, func(t *testing.T) {
			endpoint, err := entities.ParseEndpoint(spec)
			if err != nil {
				t.Fatalf("ParseEndpoint: %v", err)
			}
			if endpoint.String() != spec {
				t.Errorf("String() = %q, want %q", endpoint.String(), spec)
			}
		})
	}
}

// `pipe:` is what `local:` was spelled until spec 0044. It parses forever --
// shipped defaults, --reader help text, the published contract and config files
// people already have all carry it -- and it is NEVER printed: String() emits
// the canonical spelling, so list_readers cannot answer in a vocabulary a
// --reader flag does not use.
func TestParseEndpointAcceptsThePipeAliasAndNormalisesIt(t *testing.T) {
	got, err := entities.ParseEndpoint("pipe:nvdaMcpBridge")
	if err != nil {
		t.Fatalf("ParseEndpoint(pipe alias): %v", err)
	}
	want := entities.Endpoint{Kind: entities.TransportLocal, Address: "nvdaMcpBridge"}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("parsed (-want +got):\n%s", diff)
	}
	if got.String() != "local:nvdaMcpBridge" {
		t.Errorf("String() = %q, want the canonical spelling", got.String())
	}
}

// The predicate two rules read: which addresses are derived into this host's
// spelling, and which can be looked up in a namespace listing at all. The answer
// must not change with the host asking, because the same config file is read on
// both.
func TestIsBareName(t *testing.T) {
	for _, c := range []struct {
		address string
		want    bool
	}{
		{"nvdaMcpBridge", true},
		{"voiceoverMcpBridge", true},
		{"", false},
		{"/tmp/nvdaMcpBridge.sock", false},
		{"/Users/someone/.screenreader-mcp/nvda.sock", false},
		{`\\.\pipe\nvdaMcpBridge`, false},
		{`sub\dir`, false},
	} {
		t.Run(c.address, func(t *testing.T) {
			if got := entities.IsBareName(c.address); got != c.want {
				t.Errorf("IsBareName(%q) = %v, want %v", c.address, got, c.want)
			}
		})
	}
}
