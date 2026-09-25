// screenreader-mcp adapters -- the screenreader://info resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter serving `screenreader://info` from the current session.
// BUILT BY: sdk_server.go's Bind.
package mcp

import (
	"context"
	"encoding/json"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

const InfoURI = "screenreader://info"

// SessionSource is satisfied by the connection controller.
type SessionSource interface {
	Current() *ports.ReaderConnection
	Status() entities.ConnectionStatus
}

type info struct {
	State  string `json:"state"`
	Reason string `json:"reason,omitempty"`

	Reader        string   `json:"reader,omitempty"`
	ReaderVersion string   `json:"readerVersion,omitempty"`
	Endpoint      string   `json:"endpoint,omitempty"`
	Capabilities  []string `json:"capabilities,omitempty"`
	Mode          string   `json:"mode,omitempty"`
	Persona       string   `json:"persona,omitempty"`
	Synth         string   `json:"synth,omitempty"`

	Attendance string `json:"attendance,omitempty"`

	// LogPath is the reader-side transcript, which for a remote bridge names a file the agent cannot open.
	LogPath       string `json:"logPath,omitempty"`
	BridgeVersion string `json:"bridgeVersion,omitempty"`

	ProtocolVersion int `json:"protocolVersion,omitempty"`
}

// addInfoResource registers the resource even with no session, so the agent learns why nothing is connected.
func (s *Server) addInfoResource(sessions SessionSource) {
	s.sdk.AddResource(
		&sdk.Resource{
			URI:      InfoURI,
			Name:     "screen reader session",
			MIMEType: "application/json",
			Description: "Which screen reader is connected, what it announced it can do, " +
				"the capture mode in effect, whether a human is expected at that machine, " +
				"and where this session's two log files are. " +
				"Read this to learn which reader you are driving, then apply what you " +
				"already know about that reader. READ IT AGAIN IF YOU HAVE LOST TRACK OF " +
				"THE SESSION -- everything here was true at connect and is still true now, " +
				"including whether anyone is listening, which you must know before " +
				"deciding whether to narrate.",
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
	document.Attendance = session.SilenceCap.Sentence(session.Attended)
	document.LogPath = session.LogPath
	document.BridgeVersion = session.BridgeVersion
	document.ProtocolVersion = session.ProtocolVersion
	return document
}
