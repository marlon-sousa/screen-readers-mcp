// screenreader-mcp adapters -- the screenreader://reader-guidance resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter serving `screenreader://reader-guidance`, the connected reader's own account of the declared stance, framed and never parsed.
// BUILT BY: sdk_server.go's Bind.
package mcp

import (
	"context"
	_ "embed"
	"errors"
	"strings"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers"
)

// ReaderGuidanceURI is repeated in connect_reader's result; an integration test asserts the two agree.
const ReaderGuidanceURI = "screenreader://reader-guidance"

type GuidanceSource interface {
	Document() (controllers.ReaderGuidanceDocument, error)
}

// addReaderGuidanceResource always registers; with no session or no `guidance` capability it serves a document saying so.
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

// readerGuidanceDocument surfaces a bridge that announced `guidance` and then refused as an error, not a document.
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

	if !document.Recognised {
		return framed + document.Text + readerGuidanceUnrecognised, nil
	}
	return framed + document.Text, nil
}

// The frame uses `{{reader}}` and `{{persona}}` placeholders, so a stray percent sign in prose cannot become a formatting fault.

//go:embed documents/reader-guidance-frame.md
var readerGuidanceFrame string

//go:embed documents/reader-guidance-unrecognised.md
var readerGuidanceUnrecognised string

//go:embed documents/reader-guidance-no-session.md
var readerGuidanceNoSession string

//go:embed documents/reader-guidance-unavailable.md
var readerGuidanceUnavailable string
