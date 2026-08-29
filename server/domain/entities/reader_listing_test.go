// screenreader-mcp domain -- tests for reader_listing.go.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// The join is where spec 0013's determinism rule actually lives, so these are
// the tests that hold acceptance criterion 4 up.
package entities_test

import (
	"testing"

	"github.com/google/go-cmp/cmp"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func TestBuildListingReportsPipeLivenessAndTCPUnknown(t *testing.T) {
	nvda := testsupport.Reader(t, "nvda", "local:nvdaMcpBridge", "tcp:127.0.0.1:8765")
	live := []entities.Endpoint{testsupport.Endpoint(t, "local:nvdaMcpBridge")}

	got := entities.BuildListing([]entities.ConfiguredReader{nvda}, live)

	want := entities.ReaderListing{Readers: []entities.ReaderStatus{{
		Name: "nvda",
		Endpoints: []entities.EndpointStatus{
			{Endpoint: testsupport.Endpoint(t, "local:nvdaMcpBridge"), Liveness: entities.Listening},
			// A socket cannot be tested without connecting, and connecting
			// would occupy the bridge's single session slot.
			{Endpoint: testsupport.Endpoint(t, "tcp:127.0.0.1:8765"), Liveness: entities.LivenessUnknown},
		},
	}}}
	if diff := cmp.Diff(want, got); diff != "" {
		t.Errorf("listing (-want +got):\n%s", diff)
	}
}

func TestBuildListingReportsAConfiguredEndpointThatIsAbsent(t *testing.T) {
	nvda := testsupport.Reader(t, "nvda", "local:nvdaMcpBridge")

	got := entities.BuildListing([]entities.ConfiguredReader{nvda}, nil)

	if liveness := got.Readers[0].Endpoints[0].Liveness; liveness != entities.NotListening {
		t.Errorf("liveness = %q, want %q", liveness, entities.NotListening)
	}
}

// Acceptance criterion 4, second half: a listening endpoint belonging to no known
// reader is NOT reported and cannot be connected to. The join walks the
// configured readers, so an unconfigured endpoint has no way in even when the
// probe swears it is live.
func TestBuildListingIgnoresLiveEndpointsNobodyConfigured(t *testing.T) {
	nvda := testsupport.Reader(t, "nvda", "local:nvdaMcpBridge")
	live := []entities.Endpoint{
		testsupport.Endpoint(t, "local:nvdaMcpBridge"),
		testsupport.Endpoint(t, "local:somebodyElsesBridge"),
	}

	got := entities.BuildListing([]entities.ConfiguredReader{nvda}, live)

	if len(got.Readers) != 1 {
		t.Fatalf("readers = %d, want only the configured one", len(got.Readers))
	}
	for _, endpoint := range got.Readers[0].Endpoints {
		if endpoint.Endpoint.Address == "somebodyElsesBridge" {
			t.Error("an unconfigured endpoint reached the listing")
		}
	}
}

// The declared order is what connect_reader tries, so the listing must show it
// unchanged -- an agent reading this is reading the plan.
func TestBuildListingKeepsDeclaredOrder(t *testing.T) {
	nvda := testsupport.Reader(t, "nvda", "tcp:127.0.0.1:8765", "local:nvdaMcpBridge")

	got := entities.BuildListing([]entities.ConfiguredReader{nvda}, nil)

	want := []string{"tcp:127.0.0.1:8765", "local:nvdaMcpBridge"}
	var order []string
	for _, endpoint := range got.Readers[0].Endpoints {
		order = append(order, endpoint.Endpoint.String())
	}
	if diff := cmp.Diff(want, order); diff != "" {
		t.Errorf("endpoint order (-want +got):\n%s", diff)
	}
}

// A local endpoint addressed by a PATH is not something the host's listing can
// speak for, so it reports unknown exactly as a TCP endpoint does. Reporting it
// NOT LISTENING would be a confident wrong answer: the bridge may well be
// running on that very socket.
func TestBuildListingCannotAnswerForAnEndpointAddressedByPath(t *testing.T) {
	nvda := testsupport.Reader(t, "nvda", "local:/tmp/nvdaMcpBridge.sock")

	got := entities.BuildListing([]entities.ConfiguredReader{nvda}, nil)

	if liveness := got.Readers[0].Endpoints[0].Liveness; liveness != entities.LivenessUnknown {
		t.Errorf("liveness = %q, want %q", liveness, entities.LivenessUnknown)
	}
}
