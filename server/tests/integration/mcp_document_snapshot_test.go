//go:build integration

// screenreader-mcp tests -- reading the whole document, over MCP.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: integration scenario: everything below the client is real except the bridge.
package integration_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

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
	// The bridge omitted truncatedBy; the server must still report "none".
	if answer.TruncatedBy != "none" {
		t.Errorf("truncatedBy is %q, want \"none\" when the bridge omits it", answer.TruncatedBy)
	}
}

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
