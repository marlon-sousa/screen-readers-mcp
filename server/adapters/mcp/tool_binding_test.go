// screenreader-mcp adapters -- the binding's own tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// Spec 0031 listed these as edits to a file that did not exist -- tool_binding.go
// had no test beside it, because everything it did was observed through
// sdk_server_test.go's client. It has one now, for the reason the amendment note
// in the spec gives: the output schema is the first thing this file carries that
// a client can read WITHOUT calling anything, so it is worth asserting where it
// is produced rather than only where it happens to surface.
//
// Shares the harness and the stub tool with sdk_server_test.go, which is the
// same test package -- the split is by subject, not by scope.
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

// The point of spec 0031's 3.3: an agent whose client shows it the tool list
// gets the result shape there, from the same method the document is composed
// from -- so the two cannot disagree.
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

// The same guard the input schema has had, and for the same crash: AddTool
// panics on an output schema that is not an object schema, at the moment the
// tool is added -- which for a gated tool is mid-session, in a goroutine serving
// an agent. A startup error naming the tool is the whole of the difference.
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
