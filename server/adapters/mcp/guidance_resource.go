// screenreader-mcp adapters -- the screenreader://guidance resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter serving the static, reader-agnostic `screenreader://guidance` resource.
// BUILT BY: sdk_server.go's Bind.
//
// Nothing here may name a keystroke: the reader's own guidance document supplies the vocabulary.
package mcp

import (
	"context"
	_ "embed"
	"fmt"
	"strings"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

const GuidanceURI = "screenreader://guidance"

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

// guidanceDocument composes the persona profiles from the domain between the two embedded halves.
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

//go:embed documents/guidance-preamble.md
var guidancePreamble string

//go:embed documents/guidance-method.md
var guidanceMethod string
