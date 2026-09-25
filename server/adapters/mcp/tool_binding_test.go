// screenreader-mcp adapters -- the binding's own tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
package mcp_test

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	mcpadapter "github.com/marlon-sousa/screen-readers-mcp/server/adapters/mcp"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
)

func TestTheOutputSchemaReachesTheClient(t *testing.T) {
	h := newHarness(t, &stubTool{
		name: "ungated_tool",
		output: `{"type":"object","properties":{"pressed":{"type":"array",` +
			`"items":{"type":"string"}}},"required":["pressed"]}`,
	})

	listing, err := h.session.ListTools(context.Background(), nil)
	if err != nil {
		t.Fatalf("tools/list: %v", err)
	}
	if listing.Tools[0].OutputSchema == nil {
		t.Fatal("the tool reached the client with no output schema")
	}
	encoded, err := json.Marshal(listing.Tools[0].OutputSchema)
	if err != nil {
		t.Fatalf("marshalling the schema: %v", err)
	}
	for _, want := range []string{`"required"`, `"pressed"`, `"array"`} {
		if !strings.Contains(string(encoded), want) {
			t.Errorf("output schema = %s, want it to still contain %s", encoded, want)
		}
	}
}

func TestAMalformedOutputSchemaFailsAtStartupRatherThanMidSession(t *testing.T) {
	log := fakes.NewFakeLog()

	_, err := mcpadapter.NewServer(
		tools.NewRegistry(&stubTool{name: "broken", output: `{"type":"array"}`}), log,
	)
	if err == nil {
		t.Fatal("a non-object output schema was accepted")
	}
	if !strings.Contains(err.Error(), "broken") || !strings.Contains(err.Error(), "output") {
		t.Errorf("error = %q, want the offending tool and the schema named", err)
	}

	_, err = mcpadapter.NewServer(
		tools.NewRegistry(&stubTool{name: "worse", output: `not json`}), log,
	)
	if err == nil {
		t.Fatal("an unparseable output schema was accepted")
	}
}
