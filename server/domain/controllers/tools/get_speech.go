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
		"mode, where suppressed speech leaves no record in the log at all."
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
		})
	}
	return speechRangeResult{
		Entries:   entries,
		FromIndex: captured.FromIndex,
		ToIndex:   captured.ToIndex,
	}, nil
}
