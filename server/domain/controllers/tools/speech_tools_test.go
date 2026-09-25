// screenreader-mcp domain -- the five speech tools' tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// One test file for five tools, because they are one capability group over one port.
package tools_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/controllers/tools"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/testsupport"
)

func speechCall(t *testing.T, tool tools.Tool) (*testsupport.ToolCall, *testsupport.Connection) {
	t.Helper()
	built := testsupport.NewConnection("nvda", entities.CapabilitySpeech)
	return testsupport.NewToolCall(tool).WithConnection(built.Connection), built
}

func decode(t *testing.T, value any, into any) {
	t.Helper()
	encoded, err := json.Marshal(value)
	if err != nil {
		t.Fatalf("marshalling the result: %v", err)
	}
	if err := json.Unmarshal(encoded, into); err != nil {
		t.Fatalf("decoding %s: %v", encoded, err)
	}
}

type capturedWindow struct {
	Entries []struct {
		Text        string `json:"text"`
		Index       int    `json:"index"`
		LogPosition int    `json:"logPosition"`
		EmittedAt   string `json:"emittedAt"`
	} `json:"entries"`
	FromIndex int `json:"fromIndex"`
	ToIndex   int `json:"toIndex"`
}

func (w capturedWindow) texts() []string {
	said := make([]string, 0, len(w.Entries))
	for _, entry := range w.Entries {
		said = append(said, entry.Text)
	}
	return said
}

func TestGetSpeechReturnsAHalfOpenWindowThatChainsCleanly(t *testing.T) {
	call, built := speechCall(t, &tools.GetSpeech{})
	built.Speech.Speak("Edit  blank", "Documents  list")

	var first capturedWindow
	result, err := call.Run(`{"since_index":0}`)
	if err != nil {
		t.Fatalf("get_speech: %v", err)
	}
	decode(t, result, &first)

	if first.FromIndex != 0 || first.ToIndex != 2 {
		t.Errorf("range = [%d,%d), want [0,2)", first.FromIndex, first.ToIndex)
	}
	said := strings.Join(first.texts(), "|")
	if !strings.Contains(said, "Edit") || !strings.Contains(said, "Documents") {
		t.Errorf("entries = %q, want both utterances", said)
	}

	// Continuing from toIndex sees only what happened since.
	built.Speech.Speak("Button")
	var second capturedWindow
	result, err = call.Run(`{"since_index":2}`)
	if err != nil {
		t.Fatalf("get_speech: %v", err)
	}
	decode(t, result, &second)

	if len(second.Entries) != 1 || second.Entries[0].Text != "Button" {
		t.Errorf("entries = %q, want only what was said after the first read", second.texts())
	}
	if second.FromIndex != 2 || second.ToIndex != 3 {
		t.Errorf("range = [%d,%d), want [2,3)", second.FromIndex, second.ToIndex)
	}
}

// Empty renders are dropped bridge-side, so entry i is not at index fromIndex + i.
func TestEachSpokenEntryCarriesItsOwnIndexAndJournalPosition(t *testing.T) {
	call, built := speechCall(t, &tools.GetSpeech{})
	built.Speech.Speak("Edit  blank")
	// Records land between the two utterances, as they do live.
	built.Speech.AdvanceJournal(4)
	built.Speech.Speak("Documents  list")

	var window capturedWindow
	result, err := call.Run(`{"since_index":0}`)
	if err != nil {
		t.Fatalf("get_speech: %v", err)
	}
	decode(t, result, &window)

	if len(window.Entries) != 2 {
		t.Fatalf("entries = %q, want two", window.texts())
	}
	if window.Entries[0].Index != 0 || window.Entries[1].Index != 1 {
		t.Errorf("indices = %d,%d, want each entry's own place in the ring",
			window.Entries[0].Index, window.Entries[1].Index)
	}
	if window.Entries[0].LogPosition >= window.Entries[1].LogPosition {
		t.Errorf("logPositions = %d,%d, want the second to be later",
			window.Entries[0].LogPosition, window.Entries[1].LogPosition)
	}
}

func TestGetNextSpeechIndexBookmarksNow(t *testing.T) {
	call, built := speechCall(t, &tools.GetNextSpeechIndex{})
	built.Speech.Speak("before one", "before two")

	var bookmark struct {
		Index int `json:"index"`
	}
	result, err := call.Run("")
	if err != nil {
		t.Fatalf("get_next_speech_index: %v", err)
	}
	decode(t, result, &bookmark)

	if bookmark.Index != 2 {
		t.Errorf("index = %d, want the index the NEXT utterance will take", bookmark.Index)
	}
}

func TestGetLastSpeechReturnsTheMostRecentUtterance(t *testing.T) {
	call, built := speechCall(t, &tools.GetLastSpeech{})
	built.Speech.Speak("first", "second", "third")

	var last struct {
		Text  string `json:"text"`
		Index int    `json:"index"`
	}
	result, err := call.Run("")
	if err != nil {
		t.Fatalf("get_last_speech: %v", err)
	}
	decode(t, result, &last)

	if last.Text != "third" || last.Index != 2 {
		t.Errorf("last = %q at %d, want \"third\" at 2", last.Text, last.Index)
	}
}

func TestWaitForSpeechReportsAMatch(t *testing.T) {
	call, built := speechCall(t, &tools.WaitForSpeech{})
	built.Speech.Speak("Edit  blank", "Save  button")

	var match struct {
		Found bool   `json:"found"`
		Index int    `json:"index"`
		Text  string `json:"text"`
	}
	result, err := call.Run(`{"text":"Save"}`)
	if err != nil {
		t.Fatalf("wait_for_speech: %v", err)
	}
	decode(t, result, &match)

	if !match.Found || match.Index != 1 {
		t.Errorf("match = %+v, want found at index 1", match)
	}
}

func TestWaitForSpeechReportsANonMatchWithoutFailing(t *testing.T) {
	call, built := speechCall(t, &tools.WaitForSpeech{})
	built.Speech.Speak("Edit  blank")

	var match struct {
		Found bool `json:"found"`
	}
	result, err := call.Run(`{"text":"never said"}`)
	if err != nil {
		t.Fatalf("wait_for_speech reported a non-match as a failure: %v", err)
	}
	decode(t, result, &match)

	if match.Found {
		t.Error("found = true for text that was never spoken")
	}
}

func TestWaitForSpeechPassesAfterIndexThroughOnlyWhenGiven(t *testing.T) {
	call, built := speechCall(t, &tools.WaitForSpeech{})
	built.Speech.Speak("Edit  blank")

	if _, err := call.Run(`{"text":"Edit"}`); err != nil {
		t.Fatalf("wait_for_speech: %v", err)
	}
	if waits := built.Speech.Waits(); len(waits) != 1 || waits[0].AfterIndex != nil {
		t.Errorf("afterIndex = %v, want unset when the agent did not ask", waits[0].AfterIndex)
	}

	if _, err := call.Run(`{"text":"Edit","after_index":0}`); err != nil {
		t.Fatalf("wait_for_speech: %v", err)
	}
	waits := built.Speech.Waits()
	if len(waits) != 2 || waits[1].AfterIndex == nil || *waits[1].AfterIndex != 0 {
		t.Errorf("afterIndex = %v, want 0 passed through explicitly", waits[1].AfterIndex)
	}
}

func TestWaitForSpeechRefusesAnEmptyText(t *testing.T) {
	call, _ := speechCall(t, &tools.WaitForSpeech{})

	if _, err := call.Run(`{"text":""}`); err == nil {
		t.Error("waiting for the empty string was accepted")
	}
	if _, err := call.Run(""); err == nil {
		t.Error("waiting with no text at all was accepted")
	}
}

func TestWaitTimeoutsAreSecondsAndOptional(t *testing.T) {
	call, built := speechCall(t, &tools.WaitForSpeech{})
	built.Speech.Speak("Edit")

	if _, err := call.Run(`{"text":"Edit","timeout":2.5}`); err != nil {
		t.Fatalf("wait_for_speech: %v", err)
	}
	waits := built.Speech.Waits()
	if waits[0].Timeout.Seconds() != 2.5 {
		t.Errorf("timeout = %s, want 2.5s", waits[0].Timeout)
	}

	if _, err := call.Run(`{"text":"Edit"}`); err != nil {
		t.Fatalf("wait_for_speech: %v", err)
	}
	if got := built.Speech.Waits()[1].Timeout; got != 0 {
		t.Errorf("timeout = %s, want zero so the reader applies its own default", got)
	}
}

func TestWaitForSpeechToFinishReportsWhetherSpeechSettled(t *testing.T) {
	call, built := speechCall(t, &tools.WaitForSpeechToFinish{})

	var answer struct {
		Finished bool `json:"finished"`
	}
	result, err := call.Run("")
	if err != nil {
		t.Fatalf("wait_for_speech_to_finish: %v", err)
	}
	decode(t, result, &answer)
	if !answer.Finished {
		t.Error("finished = false for a reader that has settled")
	}

	// Still speaking is an answer too, not a failure.
	built.Speech.SetFinished(false)
	result, err = call.Run(`{"timeout":1}`)
	if err != nil {
		t.Fatalf("wait_for_speech_to_finish: %v", err)
	}
	decode(t, result, &answer)
	if answer.Finished {
		t.Error("finished = true for a reader that was still speaking")
	}
}

func TestEverySpeechToolRefusesAReaderWithoutSpeech(t *testing.T) {
	built := testsupport.NewConnection("jaws", entities.CapabilityBraille)

	speechTools := []tools.Tool{
		&tools.GetSpeech{}, &tools.GetLastSpeech{}, &tools.GetNextSpeechIndex{},
		&tools.WaitForSpeech{}, &tools.WaitForSpeechToFinish{},
	}
	for _, tool := range speechTools {
		t.Run(tool.Name(), func(t *testing.T) {
			call := testsupport.NewToolCall(tool).WithConnection(built.Connection)

			_, err := call.Run(`{"since_index":0,"text":"anything"}`)
			if err == nil {
				t.Fatal("the tool ran for a reader with no speech capability")
			}
			var capability *tools.CapabilityError
			if !asCapabilityError(err, &capability) {
				t.Fatalf("error = %v, want a *CapabilityError", err)
			}
			if capability.Capability != entities.CapabilitySpeech {
				t.Errorf("capability = %q, want speech", capability.Capability)
			}
		})
	}
}

func TestGetSpeechCarriesTheInstantEachUtteranceWasEmitted(t *testing.T) {
	call, built := speechCall(t, &tools.GetSpeech{})
	built.Speech.Speak("Edit  blank", "Documents  list")

	result, err := call.Run(`{"since_index":0}`)
	if err != nil {
		t.Fatalf("get_speech: %v", err)
	}
	var window capturedWindow
	decode(t, result, &window)

	for i, entry := range window.Entries {
		if entry.EmittedAt == "" {
			t.Errorf("entry %d (%q) carries no emittedAt", i, entry.Text)
		}
	}
}

func TestAnEntryWithoutAStampIsRenderedWithoutOne(t *testing.T) {
	call, built := speechCall(t, &tools.GetSpeech{})
	built.Speech.SpeakWithoutStamp("no stamp here")

	result, err := call.Run(`{"since_index":0}`)
	if err != nil {
		t.Fatalf("get_speech: %v", err)
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		t.Fatalf("re-encoding the result: %v", err)
	}
	if strings.Contains(string(encoded), "emittedAt") {
		t.Errorf("result names emittedAt for an entry that has none: %s", encoded)
	}

	var window capturedWindow
	decode(t, result, &window)
	if len(window.Entries) != 1 || window.Entries[0].Text != "no stamp here" {
		t.Fatalf("the entry itself must still come through: %+v", window.Entries)
	}
}
