// screenreader-mcp adapters -- the screenreader://reader-guidance resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. Serves `screenreader://reader-guidance`: the CONNECTED READER's
// own account of the stance this session declared.
// BUILT BY: sdk_server.go's Bind, beside the other three resources.
// DEPENDS ON: domain/controllers.ReaderGuidance, narrowed to Document().
//
// Spec 0029 Part 4. This is the other half of `screenreader://guidance`, and the
// division between them is the design rather than a convenience: the server's
// document states the RULE ("a command that re-reads what is already there is
// in; a command that reaches what focus cannot is out"), which survives every
// platform, and this one carries the INSTANCES, which survive none -- they are
// keystrokes on NVDA and touch gestures on TalkBack, and this server does not
// learn which reader it is driving until `hello` answers.
//
// TWO THINGS THIS ADAPTER DOES, AND NOTHING ELSE:
//
//   - It FRAMES the text (4.1). The precedence rule -- the stance is normative,
//     the bridge instantiates it, the stance wins on a disagreement -- is stated
//     in the wire contract, and stated again here, because this server never
//     parses the bridge's text and so can never check it. Framing enforces
//     precedence where precedence is actually decided: in the agent's reading.
//   - It says, in words, what the domain reports as a sentinel: no session, or a
//     bridge that publishes nothing. Both are ANSWERS, so both are documents,
//     and neither is a missing resource.
//
// It never parses the bridge's markdown. That is what lets a bridge author write
// for their own reader without negotiating a schema with anybody.
package mcp

import (
	"context"
	_ "embed"
	"errors"
	"strings"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers"
)

// ReaderGuidanceURI is the resource's address.
//
// connect_reader repeats this string in its result (spec 0029 3.4), because the
// domain may not import this package. An integration test asserts the two agree,
// which is the guard that keeps the repetition honest.
const ReaderGuidanceURI = "screenreader://reader-guidance"

// GuidanceSource is what the resource reads.
//
// Declared here, in the consumer, and as narrow as it gets: this adapter may ask
// for the document and may do nothing else to a session.
type GuidanceSource interface {
	Document() (controllers.ReaderGuidanceDocument, error)
}

// addReaderGuidanceResource registers the resource.
//
// ALWAYS registered, like the other three. An agent that reads it with no
// session, or against a bridge that announced no `guidance`, gets a document
// saying so and pointing at what to read instead -- never a resource-not-found,
// which tells it nothing and looks like a fault in this server.
func (s *Server) addReaderGuidanceResource(guidance GuidanceSource) {
	s.sdk.AddResource(
		&sdk.Resource{
			URI:      ReaderGuidanceURI,
			Name:     "this reader's guidance for your stance",
			MIMEType: "text/markdown",
			Description: "Read this AFTER connecting. The connected screen reader's OWN " +
				"account of the persona you declared: which of its commands make up the " +
				"ordinary vocabulary you are entitled to, which of them reach past focus " +
				"and are therefore outside it, the desktop keys for getting an " +
				"application in front of you, and what this particular reader cannot do " +
				"for you at all. screenreader://guidance states the rule and cannot state " +
				"the commands, because they differ on every reader and platform; this is " +
				"where they are named.",
		},
		func(_ context.Context, _ *sdk.ReadResourceRequest) (*sdk.ReadResourceResult, error) {
			text, err := readerGuidanceDocument(guidance)
			if err != nil {
				return nil, err
			}
			return &sdk.ReadResourceResult{Contents: []*sdk.ResourceContents{{
				URI:      ReaderGuidanceURI,
				MIMEType: "text/markdown",
				Text:     text,
			}}}, nil
		},
	)
}

// readerGuidanceDocument renders whatever is currently true.
//
// A bridge that ANNOUNCED the capability and then refused the command is the one
// case that surfaces as an error rather than a document: the two sentinels below
// describe states this server can see and explain, while a refusal is a bridge
// contradicting itself, and phrasing that as "this reader has nothing to say"
// would hide a real fault behind a reassuring sentence.
func readerGuidanceDocument(guidance GuidanceSource) (string, error) {
	document, err := guidance.Document()
	switch {
	case errors.Is(err, controllers.ErrNoSession):
		return readerGuidanceNoSession, nil
	case errors.Is(err, controllers.ErrNoReaderGuidance):
		return readerGuidanceUnavailable, nil
	case err != nil:
		return "", err
	}

	framed := strings.NewReplacer(
		"{{reader}}", document.Reader,
		"{{persona}}", document.Persona.String(),
	).Replace(readerGuidanceFrame)

	// The unrecognised note goes AFTER the bridge's text, not before it: what
	// the bridge said is still the larger part of what the agent needs, and a
	// caveat at the top reads as "ignore the following".
	if !document.Recognised {
		return framed + document.Text + readerGuidanceUnrecognised, nil
	}
	return framed + document.Text, nil
}

// The four documents this adapter owns, as markdown files (the root AGENTS.md,
// invariant 9). The frame carries `{{reader}}` and `{{persona}}` placeholders rather than
// printf verbs, so that a stray percent sign in prose cannot turn into a
// formatting fault in a document nobody compiles.

//go:embed documents/reader-guidance-frame.md
var readerGuidanceFrame string

//go:embed documents/reader-guidance-unrecognised.md
var readerGuidanceUnrecognised string

//go:embed documents/reader-guidance-no-session.md
var readerGuidanceNoSession string

//go:embed documents/reader-guidance-unavailable.md
var readerGuidanceUnavailable string
