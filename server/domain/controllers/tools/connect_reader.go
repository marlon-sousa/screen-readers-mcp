// screenreader-mcp domain -- the connect_reader tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: controller, ungated; the only thing in this server that causes a connection attempt.
// USES: ConnectionControl.Connect, via ToolContext.
// LISTED BY: registry.go.
package tools

import (
	"encoding/json"
	"fmt"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// readerGuidanceURI repeats adapters/mcp.ReaderGuidanceURI because the domain may not import the adapter; an integration test keeps them equal.
const readerGuidanceURI = "screenreader://reader-guidance"

type ConnectReader struct{}

var _ Tool = (*ConnectReader)(nil)

func (t *ConnectReader) Name() string { return "connect_reader" }

func (t *ConnectReader) Capability() entities.Capability { return "" }

func (t *ConnectReader) Description() string {
	return "Open a session with one screen reader. It does NOT change what tools " +
		"you can see -- every tool is advertised from startup -- it changes what " +
		"they can DO: a gated tool refuses until the reader it needs is connected " +
		"and announced the capability. Tries the reader's endpoints in " +
		"the order list_readers shows and reports which one answered. " +
		"Errors if a session is already live -- disconnect_reader first. " +
		"It also tells you whether a HUMAN IS EXPECTED at that machine and what " +
		"the reader does about long silences -- read silenceCap before you go " +
		"quiet. " +
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
			"description": "Which reader to connect to, spelled exactly as list_readers names it. Call that first if you do not know; the set is configuration, so it differs between installations. Required."
		},
		"mode": {
			"type": "string",
			"enum": ["silent", "live"],
			"description": "How speech is captured for this whole session, fixed once and not changeable without reconnecting. \"silent\" captures speech while the human hears nothing; \"live\" leaves the real synthesizer speaking and captures by observation, so ordering and timing are best-effort. CAPTURE IS COMPLETE EITHER WAY: get_speech returns what would have been spoken, and every entry carries its logPosition, so the speech-to-log join works in both modes. PREFER \"silent\" -- it is the right choice for almost every session, and \"live\" is the exception you should be able to name a reason for. Two things decide it, and neither is how much you learn: a live run means everything you do is spoken aloud at somebody's machine for as long as you work, and a live session is paced by AUDIO, so anything the reader reads aloud takes as long to produce as it takes to say, where a silent one has no sound to wait for and can answer far faster. So a wait you tuned in one mode may be badly wrong in the other -- never carry one across without checking it. Choose \"live\" only when a human needs to hear the run as it happens, or when how something SOUNDS is itself what you are testing. Silent carries one obligation: the human hears NOTHING except what you deliberately say to them, so read silenceCap below to learn whether anyone is there, and narrate with announce if they are. WHAT SILENT COSTS IS READER-SPECIFIC -- a reader may be unable to record its own account of text it never actually spoke -- and the connected reader's guidance says what it costs there; connect_reader returns that document in full. A reader that cannot honour the mode you ask for refuses the handshake and says so, so an unsupported mode is an error you see immediately rather than a silent downgrade."
		},
		"persona": {
			"type": "string",
			"enum": ["user", "validator", "expert"],
			"description": "WHAT YOU ARE STANDING IN FOR this session, which decides what a finding from it means. \"user\": an ordinary, NON-EXPERT screen reader user -- your vocabulary is bounded to what this platform's accessibility contract assumes of an ordinary user, plus the reader's ordinary reading commands, and if a task needs anything that reaches past focus (object navigation, a review cursor, a simulated click) THE TASK HAS FAILED rather than being worked around. \"validator\": the same driving vocabulary and the same limits, so that \"reachable\" means the same thing in your report as in theirs, plus introspection to characterise what you find; you may step outside the vocabulary only to characterise a failure you have ALREADY found, never to get past one, and you say so when you do. \"expert\": nothing is off limits -- the reader's own log, configuration and internals are the instruments you came for -- because you are working out how the thing behaves rather than returning a verdict. Read screenreader://guidance for the full profiles before choosing. Fixed for the whole session: a stance cannot be retrofitted onto a run that already happened, so changing it means disconnecting and connecting again."
		},
		"normalize": {
			"type": "boolean",
			"description": "Ask the reader to move signals this session could not otherwise capture into speech, where the reader offers the same information both ways -- a mode change answered with a SOUND becomes words you can read back. OMIT THIS unless you have a reason: the default differs by capture mode and is the right one in each. A silent session normalises, because the human hears nothing anyway and so loses nothing; a live session does not, because the person at the reader would hear words in place of the sound they chose, and that is theirs to decide. Pass true in a live session when the human has agreed to it, or false in a silent one when the sound behaviour is itself what you are testing. Whatever is actually changed comes back in the normalized field of the result, and every key is restored when the session ends."
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
			"description": "The reader's own version -- the screen reader's, not the bridge add-on's (that is bridgeVersion)."
		},
		"endpoint": {
			"type": "string",
			"description": "Which of the reader's endpoints answered."
		},
		"capabilities": {
			"type": "array",
			"items": {"type": "string"},
			"description": "What this reader announced it can do, from the vocabulary screenreader://tools groups its tools by. This does not change the tool LIST, which is the same before and after connecting; it decides which of those tools will actually run. A tool gated on a capability absent from this list answers an error naming it."
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
			"description": "Where THIS reader's own account of your stance can be read (screenreader://reader-guidance), for a re-read later. ABSENT when the bridge announced no 'guidance' capability, which is the honest answer that this reader publishes none."
		},
		"readerGuidanceText": {
			"type": "string",
			"description": "That account IN FULL, delivered here so you do not have to fetch it: which of THIS reader's own commands your stance may use, and which reach past focus and are therefore outside it. READ IT BEFORE YOU DRIVE -- every tool this server has is advertised from startup, so the tool list does not tell you what this reader can do, and this does. ABSENT when the bridge publishes no guidance, or is an older build that serves it only on request; then read the resource named above."
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
		},
		"silenceCap": {
			"type": "string",
			"description": "WHETHER A HUMAN IS EXPECTED AT THIS MACHINE, and what the reader does about long silences. In a silent session the person at the reader hears nothing except what you deliberately say to them with the announce tool, so a reader may bound how long that can go on: warn them, then restore speech. Read this and act on it -- announce before any stretch of work that does not drive the reader, and you will never meet the cap. You cannot change it: it is set on that machine, deliberately out of your reach."
		},
		"normalized": {
			"type": "array",
			"description": "Reader settings THIS SESSION CHANGED so that signals it could not otherwise capture arrive as speech instead. A reader may answer some actions with a sound rather than words, and a sound is not something a capture can read; where the reader offers the same information as speech, the session may ask for it that way. ABSENT MEANS NOTHING WAS CHANGED and you are driving the reader exactly as its user left it. When it is present, say so in any finding you report: the reader was not in its own configuration. Each entry carries the reader's own key path and its own reason, and every one is restored when the session ends.",
			"items": {
				"type": "object",
				"properties": {
					"keyPath": {"type": "array", "items": {"type": "string"}, "description": "The reader's own config path, outermost key first."},
					"previous": {"description": "What the setting was before this session touched it."},
					"current": {"description": "What it is now, for this session only."},
					"why": {"type": "string", "description": "The reader's own one-line reason this key is one a session may move."}
				},
				"required": ["keyPath", "previous", "current", "why"]
			}
		}
	},
	"required": ["reader", "readerVersion", "endpoint", "capabilities", "mode", "persona", "stance", "synth", "logPath", "silenceCap"]
}`)
}

type connectParams struct {
	Reader   string `json:"reader"`
	Mode     string `json:"mode"`
	Persona  string `json:"persona"`
	LogLevel string `json:"log_level"`
	// Normalize is a pointer so that absent means the reader's default, which differs by capture mode.
	Normalize *bool `json:"normalize"`
}

type connectResult struct {
	Reader        string   `json:"reader"`
	ReaderVersion string   `json:"readerVersion"`
	Endpoint      string   `json:"endpoint"`
	Capabilities  []string `json:"capabilities"`
	Mode          string   `json:"mode"`
	Persona       string   `json:"persona"`
	Stance        string   `json:"stance"`
	// ReaderGuidance is present only when the bridge announced guidance.
	ReaderGuidance string `json:"readerGuidance,omitempty"`
	// ReaderGuidanceText is absent when the bridge publishes no guidance or predates the handshake field.
	ReaderGuidanceText string `json:"readerGuidanceText,omitempty"`
	Synth              string `json:"synth"`
	// LogPath is on the reader's disk, so for a remote bridge it names a file this agent cannot open.
	LogPath       string `json:"logPath"`
	BridgeVersion string `json:"bridgeVersion,omitempty"`
	SilenceCap    string `json:"silenceCap"`
	// Normalized is every reader setting this session moved between output channels; omitted when nothing was moved.
	Normalized []normalizedSetting `json:"normalized,omitempty"`
}

func (t *ConnectReader) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	var request connectParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}

	if request.Reader == "" {
		return nil, fmt.Errorf("reader is required: %s", knownReaders(ctx))
	}

	mode, err := entities.ParseCaptureMode(request.Mode)
	if err != nil {
		return nil, err
	}

	persona, err := entities.ParsePersona(request.Persona)
	if err != nil {
		return nil, err
	}

	options := ports.SessionOptions{Mode: mode, Persona: persona, Normalize: request.Normalize}
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
	// The port is nil exactly when the bridge did not announce guidance.
	readerGuidance := ""
	if connection.Guidance != nil {
		readerGuidance = readerGuidanceURI
	}
	readerGuidanceText := ""
	if connection.GuidanceDocument != nil {
		readerGuidanceText = connection.GuidanceDocument.Text
		if readerGuidance == "" {
			readerGuidance = readerGuidanceURI
		}
	}
	return connectResult{
		Reader:        session.Reader.Name,
		ReaderVersion: session.Reader.Version,
		Endpoint:      connection.Endpoint.String(),
		Capabilities:  session.Capabilities.Strings(),
		// The mode the bridge confirmed, not the one that was asked for.
		Mode:               session.Mode.String(),
		Persona:            session.Persona.String(),
		Stance:             session.Persona.Stance(),
		ReaderGuidance:     readerGuidance,
		ReaderGuidanceText: readerGuidanceText,
		Synth:              session.Synth,
		LogPath:            session.LogPath,
		BridgeVersion:      session.BridgeVersion,
		// A nil in either means this bridge did not say.
		SilenceCap: session.SilenceCap.Sentence(session.Attended),
		Normalized: normalizedFrom(session.Normalized),
	}, nil
}

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

type normalizedSetting struct {
	KeyPath  []string        `json:"keyPath"`
	Previous json.RawMessage `json:"previous"`
	Current  json.RawMessage `json:"current"`
	Why      string          `json:"why"`
}

// normalizedFrom returns nil for an empty list, so the field is omitted rather than sent as [].
func normalizedFrom(settings []entities.NormalizedSetting) []normalizedSetting {
	if len(settings) == 0 {
		return nil
	}
	disclosed := make([]normalizedSetting, 0, len(settings))
	for _, setting := range settings {
		disclosed = append(disclosed, normalizedSetting{
			KeyPath:  setting.KeyPath,
			Previous: setting.Previous,
			Current:  setting.Current,
			Why:      setting.Why,
		})
	}
	return disclosed
}
