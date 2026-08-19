// screenreader-mcp domain -- the get_next_speech_index tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `speech`.
// USES: ports.SpeechReader, through ToolContext.Speech().
// LISTED BY: registry.go.
//
// This is the tool that makes speech assertions precise rather than hopeful:
// note "now", act, then read only what the action produced. Without it a caller
// has to guess how much of the log predates its own gesture.
package tools

import (
	"encoding/json"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// GetNextSpeechIndex reports where the next utterance will land.
type GetNextSpeechIndex struct{}

var _ Tool = (*GetNextSpeechIndex)(nil)

func (t *GetNextSpeechIndex) Name() string { return "get_next_speech_index" }

func (t *GetNextSpeechIndex) Capability() entities.Capability { return entities.CapabilitySpeech }

func (t *GetNextSpeechIndex) Description() string {
	return "Get the index the NEXT captured utterance will take -- a bookmark for " +
		"\"now\". You no longer need this when YOU are the one acting: press_gesture " +
		"and type_text take their own bookmarks and hand back the window they " +
		"covered. What it is still for is marking a moment when the agent is NOT " +
		"acting -- a human at the keyboard driving while you watch, or a bug you have " +
		"been told is about to appear. Bookmark now, let them act, then pass the " +
		"value as get_speech's since_index (or wait_for_speech's after_index) to read " +
		"only what happened after your mark. Takes no parameters."
}

func (t *GetNextSpeechIndex) InputSchema() json.RawMessage {
	return json.RawMessage(`{"type":"object","properties":{},"additionalProperties":false}`)
}

func (t *GetNextSpeechIndex) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"index": {
			"type": "integer",
			"description": "The index the NEXT captured utterance will take -- a bookmark for \"now\". Pass it to get_speech as since_index, or to wait_for_speech as after_index, to read only what happened after this moment."
		}
	},
	"required": ["index"]
}`)
}

type nextIndexResult struct {
	Index int `json:"index"`
}

func (t *GetNextSpeechIndex) Execute(ctx ToolContext, _ json.RawMessage) (any, error) {
	speech, err := ctx.Speech()
	if err != nil {
		return nil, err
	}

	index, err := speech.NextSpeechIndex()
	if err != nil {
		return nil, err
	}
	return nextIndexResult{Index: index}, nil
}
