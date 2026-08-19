// screenreader-mcp domain -- the get_speech tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `speech`.
// USES: ports.SpeechReader, obtained through ToolContext.Speech() -- which is
// the capability check, and the only way to reach the port.
// LISTED BY: registry.go.
package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// GetSpeech reads captured speech since an index.
type GetSpeech struct{}

var _ Tool = (*GetSpeech)(nil)

func (t *GetSpeech) Name() string { return "get_speech" }

func (t *GetSpeech) Capability() entities.Capability { return entities.CapabilitySpeech }

func (t *GetSpeech) Description() string {
	return "Read what the screen reader has spoken since a given index. Returns one " +
		"entry per utterance -- each with its own text, its index in the speech ring, " +
		"and logPosition, the log journal position it was captured at -- plus the " +
		"half-open range [fromIndex, toIndex) the read covers, so toIndex is exactly " +
		"the since_index to pass next: no overlap, no gap. The usual pattern is: call " +
		"get_next_speech_index, do something, then call this with that index to read " +
		"only what your action produced. Utterances that rendered empty are omitted, " +
		"so entries[i] is NOT at index fromIndex + i -- use each entry's own index. " +
		"Pass a logPosition to get_log as since_position to see what the reader was " +
		"doing internally around that utterance; that join matters most in silent " +
		"mode, where suppressed speech leaves no record in the log at all. Each " +
		"entry also carries emittedAt, the wall clock when the reader EMITTED it, " +
		"so two entries subtract to answer \"how long after\" -- which is what most " +
		"timing assertions are. Emitted is not heard: in live mode an utterance " +
		"queued behind a longer one can be seconds from audible, so this is the " +
		"right number for whether the application responded promptly and the wrong " +
		"one for when a person heard it."
}

func (t *GetSpeech) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"since_index": {
			"type": "integer",
			"minimum": 0,
			"description": "Read speech from this index onward. Use 0 for everything captured so far, or the toIndex of a previous call to continue where it left off."
		}
	},
	"required": ["since_index"],
	"additionalProperties": false
}`)
}

func (t *GetSpeech) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"entries": {
			"type": "array",
			"description": "One entry per utterance, oldest first. Empty when nothing was said in the range -- never null. Utterances that rendered empty are omitted, so entries[i] is NOT at index fromIndex + i: use each entry's own index.",
			"items": {
				"type": "object",
				"properties": {
					"text": {"type": "string", "description": "What the reader spoke."},
					"index": {"type": "integer", "description": "This utterance's own place in the speech ring."},
					"logPosition": {"type": "integer", "description": "Where this utterance sits on the reader's log journal. Hand it to get_log as sincePosition to see what the reader was doing around it."},
					"emittedAt": {"type": "string", "description": "When the reader EMITTED this, as \"YYYY-MM-DD HH:MM:SS.mmm\" -- the same shape the reader's own log uses. Two of these subtract to answer \"how long after\". Emitted is not heard: in live mode an utterance queued behind a longer one can be seconds from audible. Absent if the reader supplied none."}
				},
				"required": ["text", "index", "logPosition"]
			}
		},
		"fromIndex": {"type": "integer", "description": "The first index this read covered."},
		"toIndex": {"type": "integer", "description": "One past the last: the half-open range is [fromIndex, toIndex), so toIndex is exactly the since_index to pass next -- no overlap, no gap."}
	},
	"required": ["entries", "fromIndex", "toIndex"]
}`)
}

type speechRangeParams struct {
	SinceIndex int `json:"since_index"`
}

// capturedEntry is one utterance or braille update as the agent sees it.
//
// Shared by get_speech and get_braille because the SHAPE is genuinely the same
// (text at an index, with a journal coordinate) even though the two rings are
// not -- unlike the ports, where separate types stop a braille index being
// handed to a speech call, nothing here consumes an entry.
type capturedEntry struct {
	Text  string `json:"text"`
	Index int    `json:"index"`
	// LogPosition is the coordinate to hand get_log as since_position.
	LogPosition int `json:"logPosition"`
	// EmittedAt is when the reader emitted this, as "YYYY-MM-DD HH:MM:SS.mmm" --
	// the same shape the reader's own log uses, so it can be pasted into a
	// search of it. Two of these subtract to answer "how long after". Empty if
	// the reader did not supply one (spec 0028).
	EmittedAt string `json:"emittedAt,omitempty"`
}

type speechRangeResult struct {
	Entries   []capturedEntry `json:"entries"`
	FromIndex int             `json:"fromIndex"`
	ToIndex   int             `json:"toIndex"`
}

func (t *GetSpeech) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	speech, err := ctx.Speech()
	if err != nil {
		return nil, err
	}
	var request speechRangeParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}

	captured, err := speech.SpeechSince(request.SinceIndex)
	if err != nil {
		return nil, err
	}
	// Never nil: an agent reading `entries` should find an empty list when
	// nothing was said, not JSON null.
	entries := make([]capturedEntry, 0, len(captured.Entries))
	for _, entry := range captured.Entries {
		entries = append(entries, capturedEntry{
			Text:        entry.Text,
			Index:       entry.Index,
			LogPosition: entry.LogPosition,
			EmittedAt:   entry.EmittedAt,
		})
	}
	return speechRangeResult{
		Entries:   entries,
		FromIndex: captured.FromIndex,
		ToIndex:   captured.ToIndex,
	}, nil
}
