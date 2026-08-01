// screenreader-mcp adapters -- the screenreader://session-record resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. Serves `screenreader://session-record` from the dispatcher's
// own account of the session.
// BUILT BY: sdk_server.go's Bind, beside the info resource.
// DEPENDS ON: a RecordSource, satisfied by domain/entities.SessionRecord.
//
// Spec 0021's server-side record. A RESOURCE rather than a file on disk, for the
// same reason the info document is one: it is read when the agent wants it,
// needs no filesystem agreement with anybody, and cannot be half-written. The
// server already runs on the agent's side, so nothing is transmitted that was
// not already here.
//
// It is NOT the bridge's session transcript and must not be confused with it --
// see domain/entities/session_record.go for the two audiences and why neither
// artifact can replace the other. In one line: the transcript records what the
// READER said to a human, at capture time; this records what the AGENT asked and
// was told.

package mcp

import (
	"context"
	"encoding/json"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// SessionRecordURI is the resource's address.
const SessionRecordURI = "screenreader://session-record"

// RecordSource is what the resource reads.
//
// Declared here, in the consumer, and narrow -- this adapter may read the record
// and may not add to it.
type RecordSource interface {
	Calls() []entities.RecordedCall
	Dropped() int
}

// sessionRecord is the resource's document.
type sessionRecord struct {
	// Calls is every tool call this server dispatched, oldest first.
	Calls []entities.RecordedCall `json:"calls"`
	// Dropped is how many older calls aged out of the bounded record. Non-zero
	// means this is a tail rather than the whole session, said out loud so it is
	// never mistaken for a complete history.
	Dropped int `json:"dropped,omitempty"`
	// Note explains, in the document itself, what this record is not -- because
	// an agent reading it has no other way to learn that the reader-side
	// transcript exists and holds different things.
	Note string `json:"note"`
}

const recordNote = "This is what THIS server saw: the tool calls you made and the answers you " +
	"got. It is not the screen reader's own session transcript, which is written on the " +
	"reader's machine at capture time (see logPath in screenreader://info) and contains " +
	"every utterance, including speech you never fetched. For a complete record of what " +
	"was said, call get_speech with since_index 0 before disconnecting."

// addSessionRecordResource registers the resource. Always present, like the info
// resource: an agent asking what it has done so far deserves an empty list
// rather than a missing resource.
func (s *Server) addSessionRecordResource(record RecordSource) {
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
			document, err := json.MarshalIndent(describeRecord(record), "", "  ")
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

// describeRecord builds the document from whatever has been recorded so far.
func describeRecord(record RecordSource) sessionRecord {
	calls := record.Calls()
	if calls == nil {
		// Never null: an agent reading `calls` should find an empty list before
		// it has done anything, not JSON null.
		calls = []entities.RecordedCall{}
	}
	return sessionRecord{Calls: calls, Dropped: record.Dropped(), Note: recordNote}
}
