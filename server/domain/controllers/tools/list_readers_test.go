// screenreader-mcp domain -- the list_readers tool's tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package tools_test

import (
	"encoding/json"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

type listed struct {
	Readers []struct {
		Reader    string `json:"reader"`
		Endpoints []struct {
			Endpoint string `json:"endpoint"`
			Liveness string `json:"liveness"`
		} `json:"endpoints"`
	} `json:"readers"`
}

func runListReaders(t *testing.T, listing entities.ReaderListing) listed {
	t.Helper()
	call := testsupport.NewToolCall(&tools.ListReaders{})
	call.Control.SetListing(listing)

	result, err := call.Run("")
	if err != nil {
		t.Fatalf("list_readers: %v", err)
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("marshalling the result: %v", err)
	}
	var decoded listed
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatalf("decoding the result: %v", err)
	}
	return decoded
}

func TestEndpointsAreReportedInDeclaredOrder(t *testing.T) {
	reader := testsupport.Reader(t, "nvda", "local:nvdaMcpBridge", "tcp:127.0.0.1:8765")
	got := runListReaders(t, entities.BuildListing([]entities.ConfiguredReader{reader}, nil))

	if len(got.Readers) != 1 || got.Readers[0].Reader != "nvda" {
		t.Fatalf("readers = %+v, want the one configured reader", got.Readers)
	}
	endpoints := got.Readers[0].Endpoints
	if len(endpoints) != 2 {
		t.Fatalf("endpoints = %+v, want both", endpoints)
	}
	if endpoints[0].Endpoint != "local:nvdaMcpBridge" || endpoints[1].Endpoint != "tcp:127.0.0.1:8765" {
		t.Errorf("endpoints = %+v, want the pipe first as declared", endpoints)
	}
}

func TestLivenessIsReportedPerTransportKind(t *testing.T) {
	pipe := testsupport.Endpoint(t, "local:nvdaMcpBridge")
	reader := testsupport.Reader(t, "nvda", "local:nvdaMcpBridge", "tcp:127.0.0.1:8765")

	live := runListReaders(t, entities.BuildListing(
		[]entities.ConfiguredReader{reader}, []entities.Endpoint{pipe},
	))
	if live.Readers[0].Endpoints[0].Liveness != "listening" {
		t.Errorf("pipe liveness = %q, want listening", live.Readers[0].Endpoints[0].Liveness)
	}
	if live.Readers[0].Endpoints[1].Liveness != "unknown" {
		t.Errorf("tcp liveness = %q, want unknown", live.Readers[0].Endpoints[1].Liveness)
	}

	dead := runListReaders(t, entities.BuildListing([]entities.ConfiguredReader{reader}, nil))
	if dead.Readers[0].Endpoints[0].Liveness != "not listening" {
		t.Errorf("pipe liveness = %q, want not listening", dead.Readers[0].Endpoints[0].Liveness)
	}
}

func TestListReadersTakesNoParameters(t *testing.T) {
	call := testsupport.NewToolCall(&tools.ListReaders{})
	call.Control.SetListing(entities.ReaderListing{})

	if _, err := call.Run(""); err != nil {
		t.Errorf("a call with no arguments failed: %v", err)
	}
}

func TestNoConfiguredReadersIsAnEmptyAnswerNotAFailure(t *testing.T) {
	got := runListReaders(t, entities.BuildListing(nil, nil))

	if len(got.Readers) != 0 {
		t.Errorf("readers = %+v, want none", got.Readers)
	}
}

func TestListReadersConnectsToNothing(t *testing.T) {
	call := testsupport.NewToolCall(&tools.ListReaders{})
	call.Control.SetListing(entities.ReaderListing{})

	if _, err := call.Run(""); err != nil {
		t.Fatalf("list_readers: %v", err)
	}
	if len(call.Control.Connects()) != 0 {
		t.Error("list_readers attempted a connection")
	}
}
