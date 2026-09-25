// screenreader-mcp domain -- SessionRecord's own tests.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

package entities_test

import (
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

func TestARecordKeepsCallsInTheOrderTheyHappened(t *testing.T) {
	record := entities.NewSessionRecord()
	record.Add(entities.RecordedCall{Tool: "connect_reader"})
	record.Add(entities.RecordedCall{Tool: "press_gesture"})
	record.Add(entities.RecordedCall{Tool: "get_speech"})

	var names []string
	for _, call := range record.Calls() {
		names = append(names, call.Tool)
	}
	if strings.Join(names, ",") != "connect_reader,press_gesture,get_speech" {
		t.Errorf("calls = %v, want them oldest first", names)
	}
}

func TestAnEmptyRecordHasNothingAndAdmitsNothingWasDropped(t *testing.T) {
	record := entities.NewSessionRecord()
	if len(record.Calls()) != 0 || record.Dropped() != 0 {
		t.Errorf("a fresh record has %d calls and %d dropped, want 0/0",
			len(record.Calls()), record.Dropped())
	}
}

func TestTheOldestCallsAgeOutOnceTheCapIsReached(t *testing.T) {
	record := entities.NewSessionRecord()
	for i := 0; i < entities.MaxRecordedCalls+50; i++ {
		record.Add(entities.RecordedCall{Tool: "ping"})
	}

	if got := len(record.Calls()); got != entities.MaxRecordedCalls {
		t.Errorf("kept %d calls, want the cap of %d", got, entities.MaxRecordedCalls)
	}
}

func TestAgedOutCallsAreCountedRatherThanForgotten(t *testing.T) {
	record := entities.NewSessionRecord()
	for i := 0; i < entities.MaxRecordedCalls+50; i++ {
		record.Add(entities.RecordedCall{Tool: "ping"})
	}

	if record.Dropped() != 50 {
		t.Errorf("dropped = %d, want the 50 that aged out", record.Dropped())
	}
}

func TestAnOversizedFieldIsCappedAndSaysSo(t *testing.T) {
	record := entities.NewSessionRecord()
	record.Add(entities.RecordedCall{
		Tool:   "type_text",
		Params: strings.Repeat("x", entities.MaxRecordedText*3),
	})

	stored := record.Calls()[0].Params
	if len(stored) > entities.MaxRecordedText+32 {
		t.Errorf("stored %d characters, want it capped near %d",
			len(stored), entities.MaxRecordedText)
	}
	if !strings.Contains(stored, "truncated") {
		t.Errorf("params = %q, want the truncation said out loud", stored)
	}
}

func TestAFieldWithinTheCapIsStoredUntouched(t *testing.T) {
	record := entities.NewSessionRecord()
	record.Add(entities.RecordedCall{Tool: "press_gesture", Params: `{"gestures":["kb:tab"]}`})

	if got := record.Calls()[0].Params; got != `{"gestures":["kb:tab"]}` {
		t.Errorf("params = %q, want them unchanged", got)
	}
}

func TestCappingCutsOnARuneBoundary(t *testing.T) {
	record := entities.NewSessionRecord()
	record.Add(entities.RecordedCall{Tool: "type_text", Params: strings.Repeat("é", entities.MaxRecordedText)})

	if stored := record.Calls()[0].Params; !isValidUTF8(stored) {
		t.Errorf("params = %q, want valid UTF-8 after capping", stored)
	}
}

func isValidUTF8(s string) bool {
	for _, r := range s {
		if r == '�' {
			return false
		}
	}
	return true
}

func TestTheRecordSurvivesConcurrentWritersAndReaders(t *testing.T) {
	record := entities.NewSessionRecord()
	var wait sync.WaitGroup
	for i := 0; i < 8; i++ {
		wait.Add(2)
		go func() {
			defer wait.Done()
			for j := 0; j < 200; j++ {
				record.Add(entities.RecordedCall{At: time.Now(), Tool: "ping"})
			}
		}()
		go func() {
			defer wait.Done()
			for j := 0; j < 200; j++ {
				_ = record.Calls()
				_ = record.Dropped()
			}
		}()
	}
	wait.Wait()

	if len(record.Calls()) != entities.MaxRecordedCalls {
		t.Errorf("kept %d calls after 1600 writes, want the cap", len(record.Calls()))
	}
}

func TestCallsHandsOutACopy(t *testing.T) {
	record := entities.NewSessionRecord()
	record.Add(entities.RecordedCall{Tool: "status"})

	taken := record.Calls()
	taken[0].Tool = "tampered"

	if record.Calls()[0].Tool != "status" {
		t.Error("mutating the returned slice changed the record itself")
	}
}
