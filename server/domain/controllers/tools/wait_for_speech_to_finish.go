// screenreader-mcp domain -- the wait_for_speech_to_finish tool.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller, one per tool. GATED on `speech`.
// USES: ports.SpeechReader, through ToolContext.Speech().
// LISTED BY: registry.go.
package tools

import (
	"encoding/json"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// WaitForSpeechToFinish blocks until speech settles.
type WaitForSpeechToFinish struct{}

var _ Tool = (*WaitForSpeechToFinish)(nil)

func (t *WaitForSpeechToFinish) Name() string { return "wait_for_speech_to_finish" }

func (t *WaitForSpeechToFinish) Capability() entities.Capability { return entities.CapabilitySpeech }

func (t *WaitForSpeechToFinish) Description() string {
	return "Wait until the screen reader has stopped speaking, or until the timeout " +
		"elapses. Returns finished=true if speech settled and false if it was still " +
		"going -- neither is an error. THIS IS NOT THE STEP AFTER EVERY ACTION: " +
		"press_gesture and type_text already wait a grace window and return the " +
		"speech they caused, so calling this after them costs a whole round trip and " +
		"observes nothing. It asks \"has speech STOPPED?\", which cannot be answered " +
		"the moment you ask it -- silence before speech starts and silence after it " +
		"ends are the same thing to look at. Use it where that really is the " +
		"question: a long deliberate announcement, or a continuous read of a whole " +
		"document, where you want to know whether it is still going. WHAT IT " +
		"MEASURES: speech ARRIVING, not audio playing, and finished=true means " +
		"nothing more has arrived -- the reader may still be speaking aloud what it " +
		"already produced. Where the reader can tell the server a continuous read is " +
		"part-way through, that counts as still going even while no speech arrives, " +
		"because a read of that kind pauses between chunks; where it cannot, a long " +
		"enough pause by any other producer will read as finished. To learn what a " +
		"key said, read the result of the call that pressed it; to wait for something " +
		"specific, name it with wait_for_speech. See screenreader://guidance."
}

func (t *WaitForSpeechToFinish) InputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"timeout": {
			"type": "number",
			"exclusiveMinimum": 0,
			"description": "How long to wait, in seconds. Omit to use the reader's own default."
		}
	},
	"additionalProperties": false
}`)
}

func (t *WaitForSpeechToFinish) OutputSchema() json.RawMessage {
	return json.RawMessage(`{
	"type": "object",
	"properties": {
		"finished": {
			"type": "boolean",
			"description": "True when speech settled, false when it was still going at the timeout -- neither is an error. It measures speech ARRIVING, not audio playing: true means nothing more has arrived, and the reader may still be speaking aloud what it already produced."
		}
	},
	"required": ["finished"]
}`)
}

type waitToFinishParams struct {
	Timeout float64 `json:"timeout"`
}

type waitToFinishResult struct {
	Finished bool `json:"finished"`
}

func (t *WaitForSpeechToFinish) Execute(ctx ToolContext, params json.RawMessage) (any, error) {
	speech, err := ctx.Speech()
	if err != nil {
		return nil, err
	}
	var request waitToFinishParams
	if err := decodeParams(params, &request); err != nil {
		return nil, err
	}

	// Zero means "the reader's own default": the contract owns that value, so
	// this server does not duplicate it into the request.
	var timeout time.Duration
	if request.Timeout > 0 {
		timeout = time.Duration(request.Timeout * float64(time.Second))
	}

	finished, err := speech.WaitForSpeechToFinish(timeout)
	if err != nil {
		return nil, err
	}
	return waitToFinishResult{Finished: finished}, nil
}
