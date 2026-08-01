// screenreader-mcp domain -- the connect_reader tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. UNGATED. The ONLY thing in this server that
// causes a connection attempt: no auto-connect, no retry loop, no backoff, so
// every dial is one an agent asked for (acceptance criterion 9).
// USES: ConnectionControl.Connect, via ToolContext.
// LISTED BY: registry.go.
//
// `mode` and `log_level` are parameters HERE and not CLI flags precisely because
// the wire contract fixes both at `hello` for the session's whole lifetime
// (protocol.md §3, §4). As flags they would be chosen by whoever wrote the MCP
// host configuration, before anyone knew what the session was for; as parameters
// they are chosen per session by the party that knows what it is about to do.
package tools

import (
	"encoding/json"
	"fmt"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// ConnectReader opens the one session.
type ConnectReader struct{}

var _ Tool = (*ConnectReader)(nil)

func (t *ConnectReader) Name() string { return "connect_reader" }

func (t *ConnectReader) Capability() entities.Capability { return "" }

func (t *ConnectReader) Description() string {
	return "Open a session with one screen reader, then advertise the tools that " +
		"reader's announced capabilities allow. Tries the reader's endpoints in " +
		"the order list_readers shows and reports which one answered. " +
		"Errors if a session is already live -- disconnect_reader first. " +
		"The capture mode and log level are fixed for the whole session and " +
		"cannot be changed without reconnecting."
}

func (t *ConnectReader) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"reader": {
			"type": "string",
			"description": "Which reader to connect to, as named by list_readers (for example \"nvda\"). Required."
		},
		"mode": {
			"type": "string",
			"enum": ["silent", "live"],
			"description": "How speech is captured for this whole session. \"silent\" captures speech deterministically while the user hears nothing; \"live\" leaves the real synthesizer speaking and captures by observation, so ordering and timing are best-effort. THE TRADE-OFF: silent buys deterministic capture and COSTS LOG FIDELITY, because suppressing speech before the synthesizer also stops the reader reaching its own 'speaking' log line -- a silent session's get_log holds substantially fewer records than the same work done live. Live buys a faithful log and costs determinism. Use \"silent\" for automated testing; consider \"live\" when you are debugging WHY the reader said the wrong thing and need the log to show what surrounded it."
		},
		"log_level": {
			"type": "string",
			"enum": ["debug", "io", "debugwarning", "info"],
			"description": "Optionally raise the READER's own diagnostic log verbosity for this session. This is a real, temporary change to the reader's logging, restored when the session ends. Omit to leave it unchanged."
		}
	},
	"required": ["reader", "mode"],
	"additionalProperties": false
}`)
}

// connectParams is what the agent sent.
type connectParams struct {
	Reader   string `json:"reader"`
	Mode     string `json:"mode"`
	LogLevel string `json:"log_level"`
}

// connectResult is what an agent needs to know a session began: who answered,
// where, what it can do, and under which session-fixed settings.
type connectResult struct {
	Reader        string   `json:"reader"`
	ReaderVersion string   `json:"readerVersion"`
	Endpoint      string   `json:"endpoint"`
	Capabilities  []string `json:"capabilities"`
	Mode          string   `json:"mode"`
	Synth         string   `json:"synth"`
	// LogPath names the READER-SIDE session transcript, and it is a convenience
	// rather than a contract to depend on (spec 0021): the artifact is written
	// for the human at the reader, on the reader's disk, so for a remote bridge
	// it names a file this agent cannot open. An agent wanting its own complete
	// record calls get_speech with since_index 0 -- the ring is unbounded within
	// a session -- or reads screenreader://session-record, which this server
	// keeps from its own traffic.
	LogPath string `json:"logPath"`
	// The BRIDGE build answering, distinct from the reader version above. A
	// live run talks to whatever add-on build is installed, so an agent that
	// sees odd behaviour can check this before blaming the code.
	BridgeVersion string `json:"bridgeVersion,omitempty"`
}

func (t *ConnectReader) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	var request connectParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}

	// `reader` is REQUIRED and never defaulted (spec 0013). Defaulting to the
	// single live reader would make one call mean different things minute to
	// minute; defaulting to the single KNOWN reader is deterministic only
	// until a second bridge ships, at which point every agent habit built on
	// the omitted argument starts failing over a release the agent knows
	// nothing about.
	if request.Reader == "" {
		return nil, fmt.Errorf("reader is required: %s", knownReaders(ctx))
	}

	mode, err := entities.ParseCaptureMode(request.Mode)
	if err != nil {
		return nil, err
	}

	options := ports.SessionOptions{Mode: mode}
	if request.LogLevel != "" {
		level, err := entities.ParseReaderLogLevel(request.LogLevel)
		if err != nil {
			return nil, err
		}
		options.LogLevel = &level
	}

	connection, err := ctx.Control.Connect(request.Reader, options)
	if err != nil {
		return nil, err
	}

	session := connection.Session
	return connectResult{
		Reader:        session.Reader.Name,
		ReaderVersion: session.Reader.Version,
		Endpoint:      connection.Endpoint.String(),
		Capabilities:  session.Capabilities.Strings(),
		// The mode the BRIDGE confirmed, not the one that was asked for.
		// They agree in practice, and reporting the confirmed one is what
		// makes acceptance criterion 5 checkable rather than tautological.
		Mode:          session.Mode.String(),
		Synth:         session.Synth,
		LogPath:       session.LogPath,
		BridgeVersion: session.BridgeVersion,
	}, nil
}

// knownReaders lists what the agent could have asked for, so a wrong guess
// self-corrects in the same turn instead of costing a round trip to list_readers.
func knownReaders(ctx ToolContext) string {
	listing := ctx.Control.List()
	if len(listing.Readers) == 0 {
		return "no readers are configured"
	}
	names := make([]string, 0, len(listing.Readers))
	for _, reader := range listing.Readers {
		names = append(names, reader.Name)
	}
	return fmt.Sprintf("known readers are %v", names)
}
