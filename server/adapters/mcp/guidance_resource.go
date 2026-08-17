// screenreader-mcp adapters -- the screenreader://guidance resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. Serves `screenreader://guidance`: what a screen reader is, how
// this MCP is meant to be used, and what the personas are.
// BUILT BY: sdk_server.go's Bind, beside the info and session-record resources.
// DEPENDS ON: entities.AllPersonas, for the profiles. Nothing else -- see below.
//
// Spec 0023, amended by spec 0029, which added the persona profiles and the
// opening section. THE PROFILES ARE COMPOSED FROM THE DOMAIN rather than written
// into the text below: a persona therefore cannot be added without one, and the
// stance an agent is handed at connect_reader cannot drift from the profile it
// read here, because both come from entities.Persona.
//
// 0029 also considered giving each persona its own static resource, and withdrew
// it: a server-owned document holding a persona's VOCABULARY can only be written
// for one platform, and TalkBack has neither the keyboard nor the operating
// system such a document would assume. So this file states the RULE and the
// bridge's own document (board entry 11.20) enumerates the instances -- which is
// why nothing here names a keystroke, and nothing here ever should.
//
// The other two resources describe a session; this one describes a METHOD, so it
// is deliberately different in two ways:
//
//   - STATIC, therefore readable BEFORE connecting -- which is when an agent
//     should read it. A session-shaped guidance document could only be fetched
//     after the moment it was most needed.
//   - READER-AGNOSTIC. It says "your reader's report-focus command", never
//     "NVDA+Tab". Spec 0005 principle 2 forbids this server learning one
//     reader's key map; the agent already knows NVDA's and JAWS's from its
//     training, and screenreader://info tells it which one is connected. This
//     document supplies the method, the agent supplies the vocabulary.
//
// Why it exists at all: `press_gesture` returning ok means the reader ACCEPTED
// the input, not that anything happened -- the reader does the work afterwards
// on its own thread (spec 0021 measured a millisecond). An agent that reads ok
// as "the dialog is open" then types into whatever was already focused, and the
// symptom surfaces later as an unrelated check failing. Three live failures in
// 11.5's run had exactly that shape.
package mcp

import (
	"context"
	_ "embed"
	"fmt"
	"strings"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// GuidanceURI is the resource's address.
const GuidanceURI = "screenreader://guidance"

// addGuidanceResource registers the resource. Always present, and unlike the
// other two it does not even consult a session: there is nothing to be connected
// to in order to learn how to drive.
func (s *Server) addGuidanceResource() {
	s.sdk.AddResource(
		&sdk.Resource{
			URI:      GuidanceURI,
			Name:     "how to drive a screen reader",
			MIMEType: "text/markdown",
			Description: "Read this BEFORE connecting. What a screen reader is; WHO YOU CAN " +
				"CONNECT AS and what each stance means, which you must choose before " +
				"connect_reader and may want to confirm with the human first; how to get " +
				"the application under test in front of you, act, confirm that what you " +
				"intended actually happened, and orient yourself when it did not -- the way " +
				"a screen reader user does, by pressing keys and listening, rather than by " +
				"inspecting internals. Also what a successful press_gesture result does and " +
				"does not mean.",
		},
		func(_ context.Context, _ *sdk.ReadResourceRequest) (*sdk.ReadResourceResult, error) {
			return &sdk.ReadResourceResult{Contents: []*sdk.ResourceContents{{
				URI:      GuidanceURI,
				MIMEType: "text/markdown",
				Text:     guidanceDocument(),
			}}}, nil
		},
	)
}

// guidanceDocument assembles the served text: the static prose with the persona
// profiles composed into it.
//
// Built per read rather than once at init, because it is cheap, and because a
// package-level variable built from another package's function is a start-order
// dependency nobody can see.
func guidanceDocument() string {
	var document strings.Builder
	document.WriteString(guidancePreamble)
	for _, persona := range entities.AllPersonas() {
		fmt.Fprintf(
			&document,
			"\n### `%s` — *%s*\n\n%s\n",
			persona, persona.Question(), persona.Profile(),
		)
	}
	document.WriteString(guidanceMethod)
	return document.String()
}

// The document's two halves, as MARKDOWN FILES rather than Go string literals.
//
// This one had TWENTY-NINE places where the raw string had to be closed,
// concatenated with a quoted backtick, and reopened -- purely to emit a code
// span, in a document whose entire readership is a model reading markdown.
// //go:embed removes every one of them: the file is the document, backticks and
// all, and a reworded sentence now produces a diff somebody can read.
//
// SPLIT IN TWO because the persona profiles are composed between them by
// guidanceDocument above, from the domain rather than from this text.

//go:embed documents/guidance-preamble.md
var guidancePreamble string

//go:embed documents/guidance-method.md
var guidanceMethod string
