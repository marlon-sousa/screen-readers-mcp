// screenreader-mcp domain -- the observation a mutating tool reports.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: supporting construct; the result half press_gesture and type_text answer identically, plus the mappings that fill it.
package tools

import (
	"errors"
	"strings"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// DefaultGraceMs is a heuristic from one measurement: speech ~124 ms after a keystroke, against a ~2.6 s agent round trip.
const DefaultGraceMs = 100

// DefaultTypeGraceMs is zero: with speak typed characters on, typing emits one utterance per character and none is worth waiting for.
const DefaultTypeGraceMs = 0

// An empty Speech means nothing had arrived by the stated instant, never that nothing more will.
type observation struct {
	Speech []capturedEntry `json:"speech"`
	// [SpeechFrom, SpeechTo) is half-open; SpeechTo is where to read from next.
	SpeechFrom int `json:"speechFrom"`
	SpeechTo   int `json:"speechTo"`
	// State is absent when the reader serves no state capability, which is a different answer from all fields zero.
	State *stateResult `json:"state,omitempty"`
	// Announced is omitted when none was asked for, and says the announcement was made, never that it was heard.
	Announced string `json:"announced,omitempty"`
}

func observed(o ports.Observation, announced string) observation {
	return observation{
		Speech:     capturedEntries(o.Speech),
		SpeechFrom: o.FromIndex,
		SpeechTo:   o.ToIndex,
		State:      stateSnapshot(o.State),
		Announced:  announced,
	}
}

// announcement treats absent and empty as silence, and rejects whitespace-only text.
func announcement(text string) (string, error) {
	if text == "" {
		return "", nil
	}
	if strings.TrimSpace(text) == "" {
		return "", errors.New("announce must not be whitespace only: send no announce at all to stay quiet")
	}
	return text, nil
}

// capturedEntries never returns nil, so an agent finds an empty list rather than JSON null.
func capturedEntries(entries []ports.SpeechEntry) []capturedEntry {
	mapped := make([]capturedEntry, 0, len(entries))
	for _, entry := range entries {
		mapped = append(mapped, capturedEntry{
			Text:        entry.Text,
			Index:       entry.Index,
			LogPosition: entry.LogPosition,
			EmittedAt:   entry.EmittedAt,
		})
	}
	return mapped
}

func stateSnapshot(state *ports.ReaderState) *stateResult {
	if state == nil {
		return nil
	}
	return &stateResult{
		BrowseMode: state.BrowseMode,
		SpeechMode: state.SpeechMode,
		SleepMode:  state.SleepMode,
		InputHelp:  state.InputHelp,
	}
}
