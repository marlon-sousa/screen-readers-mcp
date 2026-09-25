// screenreader-mcp domain -- tests for endpoint.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
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
