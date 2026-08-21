// screenreader-mcp domain -- the observation a mutating tool reports.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: supporting construct for the tools package -- the result half that
// press_gesture and type_text answer IDENTICALLY (spec 0025), plus the mappings
// that fill it. Not a controller: it serves no tool of its own.
//
// The two tools agreeing is the point rather than an accident. An agent reads
// the same window, the same resume coordinate and the same unhearable modes from
// both, so the shape has to be declared once -- written twice it would drift the
// first time one of them gained a field.
package tools

import (
	"errors"
	"strings"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// DefaultGraceMs is the grace window a mutating tool asks for when the agent did
// not say (protocol.md §7.3, and DEFAULT_GRACE_MS in the wire contract).
//
// A HEURISTIC, not a constant to trust: chosen against a single measurement on
// one machine -- speech produced ~124 ms after a keystroke against a ~2.6 s
// agent round trip -- which is why grace_ms exists as a parameter at all.
const DefaultGraceMs = 100

// DefaultTypeGraceMs is zero, deliberately unlike DefaultGraceMs. Typing with
// "speak typed characters" on emits one utterance per character and none of them
// is worth waiting for; matching the two would be consistency in the wrong
// dimension.
const DefaultTypeGraceMs = 0

// observation is what a call saw within its grace window, as the agent sees it.
//
// THE CONTRACT IS ONE SENTENCE: it says what had arrived by a stated instant and
// where to resume, never that this is all there is. Hence no `complete` and no
// `finished` field -- an empty Speech means "nothing had arrived by then", which
// is a fact, where a completeness flag would be a claim no reader can support.
type observation struct {
	Speech []capturedEntry `json:"speech"`
	// The half-open window [speechFrom, speechTo) this call covered. speechTo is
	// exactly what to read from next -- no overlap, no gap.
	SpeechFrom int `json:"speechFrom"`
	SpeechTo   int `json:"speechTo"`
	// Omitted entirely when the reader serves no `state` capability: absent and
	// "all four fields zero" are different answers.
	State *stateResult `json:"state,omitempty"`
	// The announcement that was spoken to the human before this call acted,
	// echoed back (board entry 11.24(b)). OMITTED when none was asked for, so
	// absent means "you did not narrate" rather than "your narration vanished".
	//
	// It says the announcement was MADE, never that it was HEARD. protocol.md
	// §7.1 measured the gap: emission runs two to three utterances, around five
	// seconds, ahead of audio, so an agent that narrates and then acts at once
	// is acting ahead of its own narration. No field here can close that, and
	// one that implied it had would be worse than none.
	Announced string `json:"announced,omitempty"`
}

// observed maps a port outcome into that shape.
//
// `announced` comes from the REQUEST rather than the outcome: the reader
// acknowledges the whole call, and this server reached it only because the
// announcement went out first. That is the same standard the announce tool
// echoes on, and it is the reason this argument is separate -- the bridge has
// nothing to report about text it was handed.
func observed(o ports.Observation, announced string) observation {
	return observation{
		Speech:     capturedEntries(o.Speech),
		SpeechFrom: o.FromIndex,
		SpeechTo:   o.ToIndex,
		State:      stateSnapshot(o.State),
		Announced:  announced,
	}
}

// announcement validates the narration a mutating tool was asked to speak, and
// returns what will be echoed once the call succeeds.
//
// Absent and "" are the SAME answer -- say nothing -- because an erased param
// cannot tell them apart and the wire contract already spells empty as silence.
// Whitespace-only is neither: it is an agent that meant to narrate, and it is
// rejected exactly as the announce tool rejects it, rather than being dropped on
// the bridge's own `strip()` where nothing would report the loss. That silent
// drop is half of what board entry 11.24(b) is about.
func announcement(text string) (string, error) {
	if text == "" {
		return "", nil
	}
	if strings.TrimSpace(text) == "" {
		return "", errors.New("announce must not be whitespace only: send no announce at all to stay quiet")
	}
	return text, nil
}

// capturedEntries maps utterances to the entry shape get_speech already
// publishes, so the speech on a gesture result reads exactly like the speech
// from a read -- same fields, same coordinates, same joins into the log.
//
// Never nil: an agent reading `speech` should find an empty list when nothing
// was said, not JSON null.
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

// stateSnapshot maps the reader's modes, preserving absence.
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
