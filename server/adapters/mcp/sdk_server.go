// screenreader-mcp adapters -- Server: the go-sdk stdio server.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. The process's MCP endpoint: it serves stdio in production and
// an in-memory transport in the headless tests, and it registers every tool once.
// DEPENDS ON: the go-sdk, the tool registry, the dispatcher, and a SessionSource
// for the info resource.
// BUILT BY: wiring/wiring.go.
//
// THE TOOL LIST IS A CONSTANT (spec 0022, option (c), agreed 2026-08-19). Every
// tool goes on at Bind and nothing is ever added or removed, so this server
// never emits `tools/list_changed` and there is no notification a client can
// miss. A client that caches `tools/list` for the life of the process is holding
// a correct list -- which is the whole point, and what closes board entry 11.6
// for BOTH of the failures wearing its symptom: our own `poe redeploy` freezing
// a client's list, and an external client that simply never re-listed.
//
// The ToolPublisher port this used to implement is GONE, along with the
// connection controller's publish/retract calls: with nothing to publish there
// was nothing for the port to abstract.
//
// WIRING ORDER, and why Bind is separate from New: the dispatcher needs the
// connection controller, and the tools need the dispatcher. Rather than break
// that ring with a setter nobody can see, the server is CONSTRUCTED with the
// registry alone (which is enough to validate every schema and to know every
// name), and BOUND once the dispatcher exists.
//
// This type holds NO MUTABLE STATE, and that is a consequence of the tool list
// being a constant: the dispatcher used to be stored so that a later Publish
// could reach it, and with publication gone there is no later. Bind registers
// everything with the dispatcher it is handed, once, and keeps nothing.
//
// STDOUT DISCIPLINE: stdout carries MCP frames and nothing else. The SDK's own
// logger defaults to discarding, and this file hands it nothing else; every word
// this adapter says goes through the Log port to stderr.
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

// Server is the MCP endpoint and the tool publisher.
type Server struct {
	sdk      *sdk.Server
	registry *tools.Registry
	log      ports.Log
}

// NewServer builds the SDK server and validates every tool's schema.
//
// Nothing is registered yet -- every tool goes on at Bind, once.
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

// Bind registers every tool and every resource, and makes the server ready to
// serve.
//
// EVERY tool, including the ones a reader must announce a capability for. What
// stops an agent driving a reader that cannot be driven is not this list: it is
// ToolContext, whose accessors answer a CapabilityError when there is no session
// or the capability was never announced. That check runs per call, on every
// path, and it ran before this change too -- the list was only ever the shorter
// of the two answers, and the one that could go stale.
//
// What the agent reads INSTEAD of an absence: each gated tool's description
// opens by naming the session and capability it needs, and
// `screenreader://tools` records the gating capability for every tool. Both are
// static, so both are readable before connecting -- which is when they help.
func (s *Server) Bind(dispatch *tools.Dispatcher, sessions SessionSource, guidance GuidanceSource) {
	for _, name := range s.registry.Catalog().All() {
		s.add(name, dispatch)
	}

	s.addInfoResource(sessions)
	// The server's own account of the session (spec 0021), taken from the
	// dispatcher because that is where the traffic already passes.
	s.addSessionRecordResource(dispatch.Record(), sessions)
	// How to drive a reader at all (spec 0023). Takes no source: it is static,
	// so it can be read before anything is connected -- which is when it helps.
	s.addGuidanceResource()
	// And WHAT there is to drive it with (spec 0031): every tool, gated or not,
	// with the capability that gates it and both of its schemas. Static for the
	// same reason and one more -- being complete is what it is for, so it must
	// not narrow to the session.
	s.addToolsResource()
	// And what the CONNECTED reader says about the stance this session declared
	// (spec 0029). The one resource of the four that needs a round trip, which
	// is why it takes a controller rather than reading a value.
	s.addReaderGuidanceResource(guidance)
}

// Run serves MCP over stdio until the host closes it.
//
// Only stdin EOF ends the process (spec 0013): a bridge problem never does, so a
// reader that died is something the agent is told about and can reconnect to,
// not something that takes the MCP host's server down with it.
//
// EOF IS SUCCESS. The SDK reports the host closing stdin as an error, because in
// general a session ending is one; here it is the single expected end of life,
// and reporting it as a failure would leave every ordinary shutdown looking like
// a crash in the host's log.
func (s *Server) Run(ctx context.Context) error {
	err := s.sdk.Run(ctx, &sdk.StdioTransport{})
	if err == nil || errors.Is(err, io.EOF) {
		return nil
	}
	return err
}

// Connect serves one client over an already-made transport.
//
// The seam the headless integration tier drives: a real MCP client and this real
// server, in one process, over the SDK's in-memory transports -- no stdio, no
// sockets, and what the tests assert on is what an MCP client SEES.
func (s *Server) Connect(ctx context.Context, transport sdk.Transport) (*sdk.ServerSession, error) {
	return s.sdk.Connect(ctx, transport, nil)
}

// add registers one tool by name.
func (s *Server) add(name string, dispatch *tools.Dispatcher) {
	tool, known := s.registry.Lookup(name)
	if !known {
		// Only reachable if the catalog and the registry disagreed, which
		// Registry.Catalog makes impossible by deriving one from the other.
		s.log.Errorf("cannot register unknown tool %q", name)
		return
	}
	s.sdk.AddTool(declare(tool), handlerFor(dispatch, name))
}
