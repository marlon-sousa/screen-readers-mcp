// screenreader-mcp adapters -- Server: the go-sdk stdio server.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter serving MCP over stdio, or an in-memory transport in tests, with every tool registered once.
// BUILT BY: wiring/wiring.go.
//
// The tool list is constant: every tool goes on at Bind and none is ever added or removed.
// Stdout carries MCP frames and nothing else; everything this adapter says goes through the Log port to stderr.
package mcp

import (
	"context"
	"errors"
	"io"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/version"
)

type Server struct {
	sdk      *sdk.Server
	registry *tools.Registry
	log      ports.Log
}

// NewServer validates every tool's schema; nothing is registered until Bind.
func NewServer(registry *tools.Registry, log ports.Log) (*Server, error) {
	for _, tool := range registry.All() {
		if err := validateSchema(tool); err != nil {
			return nil, err
		}
	}

	return &Server{
		sdk: sdk.NewServer(&sdk.Implementation{
			Name:    "screenreader-mcp",
			Version: version.Version,
		}, nil),
		registry: registry,
		log:      log,
	}, nil
}

// Bind registers every tool, gated or not; ToolContext enforces the capability gate on each call.
func (s *Server) Bind(dispatch *tools.Dispatcher, sessions SessionSource, guidance GuidanceSource) {
	for _, name := range s.registry.Catalog().All() {
		s.add(name, dispatch)
	}

	s.addInfoResource(sessions)
	s.addSessionRecordResource(dispatch.Record(), sessions)
	s.addGuidanceResource()
	s.addToolsResource()
	s.addReaderGuidanceResource(guidance)
}

// Run treats stdin EOF as success: it is the one expected end of life, and a bridge problem never ends the process.
func (s *Server) Run(ctx context.Context) error {
	err := s.sdk.Run(ctx, &sdk.StdioTransport{})
	if err == nil || errors.Is(err, io.EOF) {
		return nil
	}
	return err
}

// Connect serves one client over an in-memory transport, for the headless integration tier.
func (s *Server) Connect(ctx context.Context, transport sdk.Transport) (*sdk.ServerSession, error) {
	return s.sdk.Connect(ctx, transport, nil)
}

func (s *Server) add(name string, dispatch *tools.Dispatcher) {
	tool, known := s.registry.Lookup(name)
	if !known {
		// Unreachable while Registry.Catalog derives the catalog from the registry.
		s.log.Errorf("cannot register unknown tool %q", name)
		return
	}
	s.sdk.AddTool(declare(tool), handlerFor(dispatch, name))
}
