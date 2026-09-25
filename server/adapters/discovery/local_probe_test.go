// screenreader-mcp adapters -- tests for local_probe.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package discovery_test

import (
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestLiveReportsAConfiguredEndpointThatIsListening(t *testing.T) {
	probe := discovery.NewLocalProbe(fakes.NewFakeLocalDirectory("nvdaMcpBridge", "chrome.sync"))
	candidates := []entities.Endpoint{testsupport.Endpoint(t, "local:nvdaMcpBridge")}

	got := probe.Live(candidates)

	if diff := cmp.Diff(candidates, got); diff != "" {
		t.Errorf("live endpoints (-want +got):\n%s", diff)
	}
}

func TestLiveOmitsAConfiguredEndpointThatIsAbsent(t *testing.T) {
	probe := discovery.NewLocalProbe(fakes.NewFakeLocalDirectory("chrome.sync"))

	got := probe.Live([]entities.Endpoint{testsupport.Endpoint(t, "local:nvdaMcpBridge")})

	if len(got) != 0 {
		t.Errorf("live = %v, want nothing", got)
	}
}

func TestLiveNeverInventsAnEndpointFromTheNamespace(t *testing.T) {
	probe := discovery.NewLocalProbe(fakes.NewFakeLocalDirectory("jawsMcpBridge", "nvdaMcpBridge"))

	got := probe.Live([]entities.Endpoint{testsupport.Endpoint(t, "local:nvdaMcpBridge")})

	if len(got) != 1 || got[0].Address != "nvdaMcpBridge" {
		t.Errorf("live = %v, want only the endpoint that was asked about", got)
	}
}

func TestLiveMatchesEndpointNamesCaseInsensitively(t *testing.T) {
	probe := discovery.NewLocalProbe(fakes.NewFakeLocalDirectory("nvdaMcpBridge"))

	got := probe.Live([]entities.Endpoint{testsupport.Endpoint(t, "local:NVDAMcpBridge")})

	if len(got) != 1 {
		t.Errorf("live = %v, want the endpoint matched regardless of case", got)
	}
}

func TestLiveIgnoresTCPEndpoints(t *testing.T) {
	probe := discovery.NewLocalProbe(fakes.NewFakeLocalDirectory("nvdaMcpBridge"))

	got := probe.Live([]entities.Endpoint{testsupport.Endpoint(t, "tcp:127.0.0.1:8765")})

	if len(got) != 0 {
		t.Errorf("live = %v, want nothing: a socket cannot be probed", got)
	}
}

func TestLiveIgnoresAnEndpointAddressedByPath(t *testing.T) {
	probe := discovery.NewLocalProbe(fakes.NewFakeLocalDirectory("nvdaMcpBridge"))

	got := probe.Live([]entities.Endpoint{testsupport.Endpoint(t, "local:/tmp/nvdaMcpBridge.sock")})

	if len(got) != 0 {
		t.Errorf("live = %v, want nothing: a listing of names cannot speak for a path", got)
	}
}
