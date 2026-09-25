// screenreader-mcp adapters -- the screenreader://session-record resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter serving `screenreader://session-record`, what the agent asked and was told, from the dispatcher's record.
// BUILT BY: sdk_server.go's Bind.

package mcp

import (
	"context"
	"encoding/json"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

const SessionRecordURI = "screenreader://session-record"

type RecordSource interface {
	Calls() []entities.RecordedCall
	Dropped() int
}

type sessionRecord struct {
	// Persona is read from the live session because the bounded record may have evicted the connect_reader call; empty when disconnected.
	Persona string                  `json:"persona,omitempty"`
	Calls   []entities.RecordedCall `json:"calls"`
	// Dropped is how many older calls aged out; non-zero means this is a tail.
	Dropped int    `json:"dropped,omitempty"`
	Note    string `json:"note"`
}

const recordNote = "This is what THIS server saw: the tool calls you made and the answers you " +
	"got. It is not the screen reader's own session transcript, which is written on the " +
	"reader's machine at capture time (see logPath in screenreader://info) and contains " +
	"every utterance, including speech you never fetched. For a complete record of what " +
	"was said, call get_speech with since_index 0 before disconnecting."

// addSessionRecordResource registers the resource even before any call, so the agent finds an empty list.
func (s *Server) addSessionRecordResource(record RecordSource, sessions SessionSource) {
	s.sdk.AddResource(
		&sdk.Resource{
			URI:      SessionRecordURI,
			Name:     "session record",
			MIMEType: "application/json",
			Description: "Every tool call this server has dispatched in this session, with " +
				"what you asked and what came back. Read it to reconstruct what you have " +
				"already tried, or to summarise a debugging session without replaying it.",
		},
		func(_ context.Context, _ *sdk.ReadResourceRequest) (*sdk.ReadResourceResult, error) {
			document, err := json.MarshalIndent(describeRecord(record, sessions), "", "  ")
			if err != nil {
				return nil, err
			}
			return &sdk.ReadResourceResult{Contents: []*sdk.ResourceContents{{
				URI:      SessionRecordURI,
				MIMEType: "application/json",
				Text:     string(document),
			}}}, nil
		},
	)
}

func describeRecord(record RecordSource, sessions SessionSource) sessionRecord {
	calls := record.Calls()
	if calls == nil {
		// Never null, so an agent finds an empty list before it has done anything.
		calls = []entities.RecordedCall{}
	}

	document := sessionRecord{Calls: calls, Dropped: record.Dropped(), Note: recordNote}
	if connection := sessions.Current(); connection != nil {
		document.Persona = connection.Session.Persona.String()
	}
	return document
}
