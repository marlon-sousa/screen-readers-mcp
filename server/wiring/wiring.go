// screenreader-mcp -- the composition root.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: composition root, the only place that knows both the ports and the adapters.
// BUILT BY: cmd/screenreader-mcp/main.go, from the parsed flags.
package wiring

import (
	"context"

	"github.com/marlon-sousa/screen-readers-mcp/server/adapters"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/bridge"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery"
	mcpadapter "github.com/marlon-sousa/screen-readers-mcp/server/adapters/mcp"
	"github.com/marlon-sousa/screen-readers-mcp/server/config"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type Options struct {
	ConfigPath string

	ReaderFlags []string

	Verbose bool
}

type Server struct {
	MCP *mcpadapter.Server

	Connection *controllers.Connection

	Endpoints ports.EndpointSource

	Probe ports.EndpointProbe

	Dialer ports.SessionDialer

	Clock ports.Clock
	Log   ports.Log
}

func Build(opts Options) (*Server, error) {
	log := adapters.NewStderrLog(opts.Verbose)
	clock := adapters.NewSystemClock()

	endpoints, err := config.Load(config.Options{
		ConfigPath:  opts.ConfigPath,
		ReaderFlags: opts.ReaderFlags,
	})
	if err != nil {
		return nil, err
	}

	probe := discovery.NewLocalProbe(discovery.NewLocalDirectory())

	dialer := bridge.NewHandshake(bridge.DialerFor, clock, log)

	registry := tools.BuildRegistry()

	// Bind comes last because the dispatcher it takes needs the connection controller.
	mcpServer, err := mcpadapter.NewServer(registry, log)
	if err != nil {
		return nil, err
	}

	connection := controllers.NewConnection(endpoints, probe, dialer, clock, log)

	mcpServer.Bind(
		tools.NewDispatcher(registry, connection, clock, log, entities.NewSessionRecord()),
		connection,
		controllers.NewReaderGuidance(connection),
	)

	return &Server{
		MCP:        mcpServer,
		Connection: connection,
		Endpoints:  endpoints,
		Probe:      probe,
		Dialer:     dialer,
		Clock:      clock,
		Log:        log,
	}, nil
}

// Run serves MCP over stdio until the host closes stdin. The heartbeat runs for
// the process's lifetime and is a no-op while nothing is connected.
func (s *Server) Run(ctx context.Context) error {
	heartbeat := make(chan struct{})
	go s.Connection.RunHeartbeat(heartbeat)

	defer func() {
		close(heartbeat)
		s.Connection.Close()
	}()

	s.Log.Infof("serving MCP over stdio; %d reader(s) configured", len(s.Endpoints.Readers()))
	return s.MCP.Run(ctx)
}
