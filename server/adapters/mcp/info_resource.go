// screenreader-mcp adapters -- the screenreader://info resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. Serves `screenreader://info` from the current session.
// BUILT BY: sdk_server.go's Bind. DEPENDS ON: a SessionSource, satisfied by
// domain/controllers/connection.go.
//
// This is spec 0013's second capability mechanism, and spec 0005's principle 2:
// SURFACE THE READER. The agent already knows NVDA's browse and focus modes and
// JAWS's forms mode from its training -- so hand it the reader's name and
// version and let it apply what it knows, rather than teaching this server to
// have opinions about particular readers.
//
// A RESOURCE rather than `initialize.instructions`, which was considered and
// rejected: instructions are frozen at handshake time, and the bridge usually
// connects long afterwards. A resource is read when the agent wants it and
// always describes the session that exists now.
package mcp

import (
	"context"
	"encoding/json"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// InfoURI is the resource's address.
const InfoURI = "screenreader://info"

// SessionSource is what the resource reads.
//
// Declared here, in the consumer, and narrow: this adapter may look at the
// current session and the connection state, and at nothing else. Satisfied by
// the connection controller.
type SessionSource interface {
	Current() *ports.ReaderConnection
	Status() entities.ConnectionStatus
}

// info is the resource's document. Its own shape, because it is agent-facing
// text and should change when we mean it to rather than when a domain field is
// renamed.
type info struct {
	State  string `json:"state"`
	Reason string `json:"reason,omitempty"`

	Reader        string   `json:"reader,omitempty"`
	ReaderVersion string   `json:"readerVersion,omitempty"`
	Endpoint      string   `json:"endpoint,omitempty"`
	Capabilities  []string `json:"capabilities,omitempty"`
	Mode          string   `json:"mode,omitempty"`
	// Persona is what this session declared it stands for (spec 0029). Here for
	// the same reason the reader's name is: an agent that reads this document to
	// find out what it is driving also needs to know what it is standing in for,
	// and the two together are what make a finding interpretable afterwards.
	Persona string `json:"persona,omitempty"`
	Synth   string `json:"synth,omitempty"`

	// LogPath is the READER-SIDE transcript, as a path, and deliberately not as
	// a resource. That conversation happened (spec 0021) and came out against
	// transmitting it: the file is written for the human at the reader, with
	// capture-time stamps only the bridge can produce, and for a remote bridge
	// it names a file the agent cannot open at all. The agent's own record is
	// screenreader://session-record, which this server keeps from its own
	// traffic; the agent's own copy of what was said is get_speech from index 0.
	LogPath       string `json:"logPath,omitempty"`
	BridgeVersion string `json:"bridgeVersion,omitempty"`

	ProtocolVersion int `json:"protocolVersion,omitempty"`
}

// addInfoResource registers the resource. It is always present, whether or not a
// session is: an agent asking "what am I connected to?" deserves the answer
// "nothing, and here is why" rather than a missing resource.
func (s *Server) addInfoResource(sessions SessionSource) {
	s.sdk.AddResource(
		&sdk.Resource{
			URI:      InfoURI,
			Name:     "screen reader session",
			MIMEType: "application/json",
			Description: "Which screen reader is connected, what it announced it can do, " +
				"the capture mode in effect, and where this session's two log files are. " +
				"Read this to learn which reader you are driving, then apply what you " +
				"already know about that reader.",
		},
		func(_ context.Context, _ *sdk.ReadResourceRequest) (*sdk.ReadResourceResult, error) {
			document, err := json.MarshalIndent(describe(sessions), "", "  ")
			if err != nil {
				return nil, err
			}
			return &sdk.ReadResourceResult{Contents: []*sdk.ResourceContents{{
				URI:      InfoURI,
				MIMEType: "application/json",
				Text:     string(document),
			}}}, nil
		},
	)
}

// describe builds the document from whatever is currently true.
func describe(sessions SessionSource) info {
	status := sessions.Status()
	document := info{State: status.State.String(), Reason: status.Reason}

	connection := sessions.Current()
	if connection == nil {
		return document
	}

	session := connection.Session
	document.Reader = session.Reader.Name
	document.ReaderVersion = session.Reader.Version
	document.Endpoint = connection.Endpoint.String()
	document.Capabilities = session.Capabilities.Strings()
	document.Mode = session.Mode.String()
	document.Persona = session.Persona.String()
	document.Synth = session.Synth
	document.LogPath = session.LogPath
	// There is no reader-log PATH to report: spec 0020 replaced 0009's capture
	// file with the in-memory journal, read through the get_log tool instead.
	document.BridgeVersion = session.BridgeVersion
	document.ProtocolVersion = session.ProtocolVersion
	return document
}
