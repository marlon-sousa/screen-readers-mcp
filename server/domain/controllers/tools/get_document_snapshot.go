// screenreader-mcp domain -- the get_document_snapshot tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `document`.
// USES: ports.DocumentReader, through ToolContext.Document().
// LISTED BY: registry.go.
//
// WHY THIS TOOL EXISTS (spec 0026, board entry 11.13). Reading a page by
// arrowing costs one round trip PER LINE, and that is where the 2026-08-03 run
// died: it reached a results page and never got the three titles. This is the
// one thing in the surface that reduces the NUMBER of steps rather than the cost
// of one.
//
// AND WHY IT IS NOT A STRUCTURAL READ, which is the objection it has to answer.
// Browse mode IS a flat text rendering -- NVDA's own translator comment says so
// -- and this returns exactly that text, roles and all, as the user reads it.
// Compare what spec 0023 forbade: querying an object model by role and app
// module, vocabulary a blind user does not have. Nothing here is outside what
// the person at the reader could have read by holding down the down arrow. The
// delivery changes; the substance does not. That is why the description says
// "the flat text a user arrows through" in those words, and why this tool is not
// qualified per persona the way get_focus_info and get_state are.
package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// GetDocumentSnapshot reads the reader's flat document, whole.
type GetDocumentSnapshot struct{}

var _ Tool = (*GetDocumentSnapshot)(nil)

func (t *GetDocumentSnapshot) Name() string { return "get_document_snapshot" }

func (t *GetDocumentSnapshot) Capability() entities.Capability {
	return entities.CapabilityDocument
}

func (t *GetDocumentSnapshot) Description() string {
	return "Read the WHOLE document the reader is showing, as the flat lines a user arrows " +
		"through -- headings with their level, links, radio buttons with their state, in the " +
		"reader's own words. This is not a structural read of an object model: it is the same " +
		"text the person at the reader reads, delivered in one call instead of one round trip " +
		"per line. Call it with NO parameters and you get the whole document, which is the " +
		"ordinary use. " +
		"IT IS A STILL FRAME. `capturedAt` is when it was taken; anything the page did " +
		"afterwards -- a live region updating, content still loading, an infinite scroll -- is " +
		"NOT in it, and nothing here can tell you whether that happened. To see change, take " +
		"another snapshot and compare. " +
		"A VERY LARGE DOCUMENT MAKES A VERY LARGE ANSWER: the render is cheap, but a page of " +
		"a thousand lines is tens of kilobytes of result, and that is the one reason to reach " +
		"for maxLines. Prefer reading the whole thing; bound it when you already know the " +
		"document is huge and you only need the top of it. " +
		"If you bound the read with fromLine/maxLines/maxChars, remember that TWO CALLS ARE " +
		"TWO MOMENTS: a document that changes between them gives you a reading stitched from " +
		"states that never existed together. Only the unbounded call returns a coherent " +
		"picture. " +
		"`hasDocument: false` means the focus is not in a document at all -- a dialog, a " +
		"native application, the desktop. That is an answer, not a failure; there the only " +
		"way to read is still the reader's own navigation commands."
}

func (t *GetDocumentSnapshot) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"fromLine": {
			"type": "integer",
			"minimum": 0,
			"description": "First line to include. Omit for the whole document. Lines keep their ABSOLUTE ordinals, so line 14 is line 14 whatever slice you asked for."
		},
		"maxLines": {
			"type": "integer",
			"minimum": 0,
			"description": "Stop after this many lines; omit or 0 for no limit. Paging with this means two calls are two moments -- a document that changed between them yields a reading that never existed as one state of the page."
		},
		"maxChars": {
			"type": "integer",
			"minimum": 0,
			"description": "Stop once the text reaches this many characters; omit or 0 for no limit. Same two-moments caveat as maxLines. The first line is always returned however small the budget."
		}
	},
	"additionalProperties": false
}`)
}

func (t *GetDocumentSnapshot) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"hasDocument": {
			"type": "boolean",
			"description": "False when the focus is not in a document the reader renders as flat text -- a dialog, a native application, the desktop. A real answer, NOT an empty document: there is nothing here to read line by line either."
		},
		"capturedAt": {
			"type": "string",
			"description": "Wall clock when the picture was taken, in the reader's own log format so it can be joined to speech and to the reader's log. THE SNAPSHOT IS THIS INSTANT AND NO OTHER."
		},
		"title": {"type": "string", "description": "The document's own title; empty when it has none."},
		"lines": {
			"type": "array",
			"description": "The document's lines in order, as the reader presents them -- roles and states included.",
			"items": {
				"type": "object",
				"properties": {
					"line": {"type": "integer", "description": "The document's own line ordinal, absolute."},
					"text": {"type": "string", "description": "The line as the reader would speak it."}
				},
				"required": ["line", "text"]
			}
		},
		"fromLine": {"type": "integer", "description": "First line included."},
		"toLine": {"type": "integer", "description": "One past the last line included: [fromLine, toLine)."},
		"truncatedBy": {
			"type": "string",
			"enum": ["none", "maxLines", "maxChars"],
			"description": "Which bound stopped the read. \"none\" means the document ended -- including when it ended exactly on a bound, which is a coincidence and not a cap. There is no null here, so a falsy check is never how you ask."
		}
	},
	"required": ["hasDocument", "capturedAt", "title", "lines", "fromLine", "toLine", "truncatedBy"]
}`)
}

type snapshotLineResult struct {
	Line int    `json:"line"`
	Text string `json:"text"`
}

// documentSnapshotResult always carries every field, `lines` included as an
// empty array rather than null when there is nothing to report: an agent that
// ranges over the result must not have to nil-check a list whose emptiness is
// already stated by hasDocument and by the span.
type documentSnapshotResult struct {
	HasDocument bool                 `json:"hasDocument"`
	CapturedAt  string               `json:"capturedAt"`
	Title       string               `json:"title"`
	Lines       []snapshotLineResult `json:"lines"`
	FromLine    int                  `json:"fromLine"`
	ToLine      int                  `json:"toLine"`
	TruncatedBy string               `json:"truncatedBy"`
}

type documentSnapshotParams struct {
	FromLine int `json:"fromLine"`
	MaxLines int `json:"maxLines"`
	MaxChars int `json:"maxChars"`
}

func (t *GetDocumentSnapshot) Execute(ctx ToolContext, raw json.RawMessage) (any, error) {
	reader, err := ctx.Document()
	if err != nil {
		return nil, err
	}

	var params documentSnapshotParams
	if err := decodeParams(raw, &params); err != nil {
		return nil, err
	}

	snapshot, err := reader.Snapshot(ports.DocumentBounds{
		FromLine: params.FromLine,
		MaxLines: params.MaxLines,
		MaxChars: params.MaxChars,
	})
	if err != nil {
		return nil, err
	}

	lines := make([]snapshotLineResult, 0, len(snapshot.Lines))
	for _, line := range snapshot.Lines {
		lines = append(lines, snapshotLineResult{Line: line.Line, Text: line.Text})
	}
	return documentSnapshotResult{
		HasDocument: snapshot.HasDocument,
		CapturedAt:  snapshot.CapturedAt,
		Title:       snapshot.Title,
		Lines:       lines,
		FromLine:    snapshot.FromLine,
		ToLine:      snapshot.ToLine,
		TruncatedBy: snapshot.TruncatedBy,
	}, nil
}
