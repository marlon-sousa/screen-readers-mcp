//go:build integration

// screenreader-mcp tests -- reading the whole document, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: integration scenario, named after the USE CASE (spec 0026, entry 11.13).
// Everything below the client is real except the bridge: the tool controller,
// the JSON-lines client, the transport and the MCP binding all run.
//
// What is worth proving HERE rather than in a unit test is the shape SURVIVING
// the round trip -- specifically the two answers this repo has repeatedly
// collapsed by accident. `hasDocument: false` has to arrive as a false and not
// as an error or an absence, and `truncatedBy` has to arrive as "none" and not
// as an empty string, because both are read by an agent that will branch on
// them.
package integration_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

// page is a document with the three renderings the maintainer named: a heading
// carrying its level, a link saying it is one, and a radio button with its
// state. If any of these can be lost between the bridge and the agent, the tool
// does not do the thing it exists for.
var page = []wire.SnapshotLine{
	{Line: 0, Text: "heading level 1 BlindTec"},
	{Line: 1, Text: "link Skip to content"},
	{Line: 2, Text: "radio button checked Portuguese"},
}

type snapshotAnswer struct {
	HasDocument bool   `json:"hasDocument"`
	CapturedAt  string `json:"capturedAt"`
	Title       string `json:"title"`
	Lines       []struct {
		Line int    `json:"line"`
		Text string `json:"text"`
	} `json:"lines"`
	FromLine    int    `json:"fromLine"`
	ToLine      int    `json:"toLine"`
	TruncatedBy string `json:"truncatedBy"`
}

// servingDocument is a bridge that answers getDocumentSnapshot with `page`,
// honouring maxLines so a test can see a bound bite end to end.
func servingDocument(t *testing.T, h *testsupport.MCPHarness) {
	t.Helper()
	h.Bridge.Handle(wire.CommandGetDocumentSnapshot, func(params json.RawMessage) (any, error) {
		var asked wire.DocumentSnapshotParams
		if len(params) > 0 {
			if err := json.Unmarshal(params, &asked); err != nil {
				return nil, err
			}
		}
		lines := page
		truncatedBy := wire.TruncatedByNone
		if asked.MaxLines != nil && *asked.MaxLines < len(lines) {
			lines = lines[:*asked.MaxLines]
			truncatedBy = wire.TruncatedByMaxLines
		}
		from, to := 0, len(lines)
		title := "BlindTec"
		return wire.DocumentSnapshotResult{
			HasDocument: true,
			CapturedAt:  "2026-08-22 14:31:07.412",
			Title:       &title,
			Lines:       lines,
			FromLine:    &from,
			ToLine:      &to,
			TruncatedBy: &truncatedBy,
		}, nil
	})
}

// The whole point of the tool, at the boundary an agent actually sees: one call,
// no arguments, the entire document with its roles intact.
func TestABareCallReturnsTheWholeDocumentWithItsRoles(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilityDocument))
	servingDocument(t, h)
	h.Connect(t)

	var answer snapshotAnswer
	h.Call(t, "get_document_snapshot", nil).Decode(t, &answer)

	if !answer.HasDocument {
		t.Fatal("hasDocument is false for a bridge that served a document")
	}
	if len(answer.Lines) != len(page) {
		t.Fatalf("got %d lines, want %d", len(answer.Lines), len(page))
	}
	for i, line := range answer.Lines {
		if line.Text != page[i].Text || line.Line != page[i].Line {
			t.Errorf("line %d is %+v, want %+v", i, line, page[i])
		}
	}
	if answer.TruncatedBy != "none" {
		t.Errorf("truncatedBy is %q, want \"none\" -- nothing was cut off", answer.TruncatedBy)
	}
	if answer.CapturedAt == "" {
		t.Error("capturedAt is empty; the snapshot must say which instant it is")
	}
	if answer.Title != "BlindTec" {
		t.Errorf("title is %q, want the document's own", answer.Title)
	}
}

// The distinction this repo has had to restore four times, proved across the
// wire: not in a document is a FALSE, not an error and not an absence.
func TestNotBeingInADocumentIsAFalseAndNotAFailure(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilityDocument))
	h.Bridge.Handle(wire.CommandGetDocumentSnapshot, func(json.RawMessage) (any, error) {
		return wire.DocumentSnapshotResult{
			HasDocument: false,
			CapturedAt:  "2026-08-22 14:31:07.412",
		}, nil
	})
	h.Connect(t)

	result := h.Call(t, "get_document_snapshot", nil)
	if result.IsError {
		t.Fatalf("a focus with no document was reported as a failure: %s", result.Text)
	}
	var answer snapshotAnswer
	result.Decode(t, &answer)
	if answer.HasDocument {
		t.Error("hasDocument is true for a bridge that has no document")
	}
	if answer.Lines == nil {
		t.Error("lines is null; it must arrive as an empty array so an agent can range over it")
	}
	// The bridge omitted truncatedBy entirely. It must still reach the agent as
	// a member of the set, never as "" -- an agent branching on a falsy value
	// would read "not truncated" out of a field that said nothing.
	if answer.TruncatedBy != "none" {
		t.Errorf("truncatedBy is %q, want \"none\" when the bridge omits it", answer.TruncatedBy)
	}
}

// A bound the agent chose reaches the bridge and its cause comes back named.
func TestAChosenBoundIsHonouredAndItsCauseIsNamed(t *testing.T) {
	h := testsupport.StartMCP(t, nvda(wire.CapabilityDocument))
	servingDocument(t, h)
	h.Connect(t)

	var answer snapshotAnswer
	h.Call(t, "get_document_snapshot", map[string]any{"maxLines": 2}).Decode(t, &answer)

	if len(answer.Lines) != 2 {
		t.Fatalf("got %d lines, want the 2 asked for", len(answer.Lines))
	}
	if answer.TruncatedBy != "maxLines" {
		t.Errorf("truncatedBy is %q, want \"maxLines\"", answer.TruncatedBy)
	}
}

// The capability gate, asserted the way spec 0022 made it work: the tool is
// advertised to everyone and REFUSES the call, naming what is missing.
func TestAReaderWithNoDocumentCapabilityRefusesTheCall(t *testing.T) {
	h := testsupport.StartMCP(t, nvda())
	h.Connect(t)

	if !h.Advertises(t, "get_document_snapshot") {
		t.Error("the tool is not advertised; since spec 0022 every tool is listed always")
	}
	result := h.Call(t, "get_document_snapshot", nil)
	if !result.IsError {
		t.Fatal("a reader announcing no capabilities served the document tool")
	}
	if !strings.Contains(result.Text, "document") {
		t.Errorf("the error does not name the missing capability: %s", result.Text)
	}
}
