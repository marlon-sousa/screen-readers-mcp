// screenreader-mcp domain -- the connect_reader tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. UNGATED. The ONLY thing in this server that
// causes a connection attempt: no auto-connect, no retry loop, no backoff, so
// every dial is one an agent asked for (acceptance criterion 9).
// USES: ConnectionControl.Connect, via ToolContext.
// LISTED BY: registry.go.
//
// `mode`, `persona` and `log_level` are parameters HERE and not CLI flags
// precisely because the wire contract fixes them at `hello` for the session's
// whole lifetime (protocol.md §3, §4). As flags they would be chosen by whoever
// wrote the MCP host configuration, before anyone knew what the session was for;
// as parameters they are chosen per session by the party that knows what it is
// about to do. `persona` (spec 0029) is the sharpest case of that: it decides
// what a finding from the session MEANS, and a host-level default would attribute
// a stance nobody chose.
package tools

import (
	"encoding/json"
	"fmt"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// readerGuidanceURI is where the connected reader's own persona document is
// served, repeated here because the DOMAIN MAY NOT IMPORT THE ADAPTER that
// publishes it (the architecture test enforces that, and it is the rule that
// keeps a future wire v2 out of the domain).
//
// One integration test asserts this equals adapters/mcp.ReaderGuidanceURI and
// that the URI is really published, which is what keeps the repetition honest --
// a dangling pointer in a connect result is invisible to everything else: the
// call succeeds, and the agent gets resource-not-found at the moment it takes
// our advice.
const readerGuidanceURI = "screenreader://reader-guidance"

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
		"You must say WHO YOU ARE STANDING IN FOR (persona): it decides what a " +
		"finding from this session means, and it is returned with the stance it " +
		"puts you under -- together with screenreader://reader-guidance, where " +
		"that reader says which of ITS OWN commands your stance may and may not " +
		"use. Read that before you drive. The capture mode, persona and log " +
		"level are fixed for the whole session and cannot be changed without " +
		"reconnecting."
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
			"description": "How speech is captured for this whole session. \"silent\" captures speech deterministically while the user hears nothing; \"live\" leaves the real synthesizer speaking and captures by observation, so ordering and timing are best-effort. CAPTURE IS COMPLETE EITHER WAY: silent suppresses each utterance only after copying it, so get_speech returns exactly what would have been spoken, and every entry carries its logPosition, so the speech-to-log join works in both modes. The one thing silent costs is the reader's own 'speaking' log record: the reader writes that AFTER the point where the empty sequence is substituted, so those records are absent from a silent session -- and only at the debug and io log levels, which is the only place they exist at all. Every other record the reader writes is identical in both modes. Use \"silent\" for automated testing. Choose \"live\" when a human needs to hear the run as it happens, or in the narrow case where you specifically need the reader's own record of the text it spoke."
		},
		"persona": {
			"type": "string",
			"enum": ["user", "validator", "expert"],
			"description": "WHAT YOU ARE STANDING IN FOR this session, which decides what a finding from it means. \"user\": an ordinary, NON-EXPERT screen reader user -- your vocabulary is bounded to what this platform's accessibility contract assumes of an ordinary user, plus the reader's ordinary reading commands, and if a task needs anything that reaches past focus (object navigation, a review cursor, a simulated click) THE TASK HAS FAILED rather than being worked around. \"validator\": the same driving vocabulary and the same limits, so that \"reachable\" means the same thing in your report as in theirs, plus introspection to characterise what you find; you may step outside the vocabulary only to characterise a failure you have ALREADY found, never to get past one, and you say so when you do. \"expert\": nothing is off limits -- the reader's own log, configuration and internals are the instruments you came for -- because you are working out how the thing behaves rather than returning a verdict. Read screenreader://guidance for the full profiles before choosing. Fixed for the whole session: a stance cannot be retrofitted onto a run that already happened, so changing it means disconnecting and connecting again."
		},
		"log_level": {
			"type": "string",
			"enum": ["debug", "io", "debugwarning", "info"],
			"description": "Optionally raise the READER's own diagnostic log verbosity for this session. This is a real, temporary change to the reader's logging, restored when the session ends. Omit to leave it unchanged."
		}
	},
	"required": ["reader", "mode", "persona"],
	"additionalProperties": false
}`)
}

func (t *ConnectReader) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"reader": {
			"type": "string",
			"description": "The reader that answered."
		},
		"readerVersion": {
			"type": "string",
			"description": "The reader's own version -- NVDA's, not the bridge's."
		},
		"endpoint": {
			"type": "string",
			"description": "Which of the reader's endpoints answered."
		},
		"capabilities": {
			"type": "array",
			"items": {"type": "string"},
			"description": "What this reader announced it can do, from the vocabulary screenreader://tools groups its tools by. The tools those capabilities allow are advertised from this moment on."
		},
		"mode": {
			"type": "string",
			"enum": ["silent", "live"],
			"description": "The capture mode the BRIDGE confirmed, not the one that was asked for. Fixed for the session."
		},
		"persona": {
			"type": "string",
			"enum": ["user", "validator", "expert"],
			"description": "What this session declared it stands for, echoed so the declaration is recorded beside everything the session produces."
		},
		"stance": {
			"type": "string",
			"description": "The persona's instruction, in full. Read it: it is what your findings will mean."
		},
		"readerGuidance": {
			"type": "string",
			"description": "Where THIS reader's own account of your stance can be read (screenreader://reader-guidance). ABSENT when the bridge announced no 'guidance' capability, which is the honest answer that this reader publishes none."
		},
		"synth": {
			"type": "string",
			"description": "The speech synthesizer the reader is using."
		},
		"logPath": {
			"type": "string",
			"description": "The READER-SIDE session transcript, on the reader's own disk -- a convenience, not a contract: for a remote bridge it names a file you cannot open. For your own complete record read screenreader://session-record."
		},
		"bridgeVersion": {
			"type": "string",
			"description": "The bridge build that answered, distinct from the reader version. Absent when the bridge did not say."
		}
	},
	"required": ["reader", "readerVersion", "endpoint", "capabilities", "mode", "persona", "stance", "synth", "logPath"]
}`)
}

// connectParams is what the agent sent.
type connectParams struct {
	Reader   string `json:"reader"`
	Mode     string `json:"mode"`
	Persona  string `json:"persona"`
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
	// Persona is what this session declared it stands for, echoed so the
	// declaration appears in the session record beside everything it produced.
	Persona string `json:"persona"`
	// Stance is the persona's instruction, in full. A persona an agent declares
	// but never reads is a label rather than an instruction, and connect is the
	// one moment an agent is guaranteed to be reading -- the first external run
	// (spec 0027) never read screenreader://guidance at all and dropped to
	// PowerShell for something it would have been told.
	Stance string `json:"stance"`
	// ReaderGuidance is where THIS reader's own account of that stance can be
	// read -- which of its commands make up the ordinary vocabulary, and which
	// reach past focus and are therefore outside it (spec 0029 Part 4).
	//
	// PRESENT ONLY WHEN THE BRIDGE ANNOUNCED `guidance`, so an absent field is
	// the honest answer "this reader publishes none" rather than a pointer at a
	// document that would explain nothing.
	//
	// It is named here because this is the earliest instant it exists: the
	// persona is chosen BEFORE connecting and can only be instantiated on a
	// particular reader AFTER, and an agent left to discover that would not.
	ReaderGuidance string `json:"readerGuidance,omitempty"`
	Synth          string `json:"synth"`
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

	// REQUIRED, and never defaulted (spec 0029). A default would silently
	// attribute a stance nobody chose, and a claim resting on a defaulted
	// `user` session is one nobody can withdraw, because nobody knows it was
	// made. The parse error names all three with the question each asks, so a
	// wrong guess self-corrects in this turn.
	persona, err := entities.ParsePersona(request.Persona)
	if err != nil {
		return nil, err
	}

	options := ports.SessionOptions{Mode: mode, Persona: persona}
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
	// The capability gate, read structurally: the port is nil exactly when the
	// bridge did not announce `guidance`, so there is no boolean anyone has to
	// remember to check.
	readerGuidance := ""
	if connection.Guidance != nil {
		readerGuidance = readerGuidanceURI
	}
	return connectResult{
		Reader:        session.Reader.Name,
		ReaderVersion: session.Reader.Version,
		Endpoint:      connection.Endpoint.String(),
		Capabilities:  session.Capabilities.Strings(),
		// The mode the BRIDGE confirmed, not the one that was asked for.
		// They agree in practice, and reporting the confirmed one is what
		// makes acceptance criterion 5 checkable rather than tautological.
		Mode: session.Mode.String(),
		// From the session rather than from the request, so this reports what
		// was actually recorded against the run.
		Persona:        session.Persona.String(),
		Stance:         session.Persona.Stance(),
		ReaderGuidance: readerGuidance,
		Synth:          session.Synth,
		LogPath:        session.LogPath,
		BridgeVersion:  session.BridgeVersion,
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
