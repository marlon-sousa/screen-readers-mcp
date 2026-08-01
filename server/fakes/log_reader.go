// screenreader-mcp fakes -- FakeLogReader: the LogReader port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double. MIRRORS domain/ports/log_reader.go.
// USED BY: the get_log, set_log_level, get_log_position and wait_for_log tool
// controller tests.

package fakes

import (
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// FakeLogReader records what it was asked for and returns scripted responses.
type FakeLogReader struct {
	LastParams ports.GetLogParams
	LastLevel  string
	// LastWait is the wait_for_log request, kept because the INTERACTION is the
	// requirement there: a tool that dropped min_level would still return a
	// plausible-looking match.
	LastWait     ports.LogWait
	Calls        int
	SliceResult  ports.LogSliceResult
	LevelResult  ports.LogLevelResult
	MarkResult   ports.LogPosition
	MatchResult  ports.LogMatch
	Err          error
	PositionErr  error
	WaitCalls    int
	PositionCall int
}

var _ ports.LogReader = (*FakeLogReader)(nil)

// commandID is the address of an int, for the nullable command range a slice
// carries when it WAS anchored on a command (spec 0021 makes those absent for a
// position or time anchor, so nil and a value are different answers).
func commandID(id int) *int { return &id }

// NewFakeLogReader builds a log reader that returns empty slices.
func NewFakeLogReader() *FakeLogReader {
	return &FakeLogReader{
		SliceResult: ports.LogSliceResult{
			Text:            "",
			Entries:         0,
			Matched:         0,
			Truncated:       false,
			NextPosition:    0,
			FromCommandID:   commandID(1),
			ToCommandID:     commandID(1),
			CapturedAtLevel: "info",
		},
		LevelResult: ports.LogLevelResult{
			Level:    "info",
			Previous: "info",
		},
		MarkResult: ports.LogPosition{Position: 0, Time: "2026-07-31 12:00:00.000"},
		// Not found is the honest default: a wait only matches records logged
		// after it began, and a fake that reported a match by default would let a
		// tool treat the miss path as unreachable.
		MatchResult: ports.LogMatch{Found: false, Position: 0},
	}
}

func (f *FakeLogReader) GetLog(params ports.GetLogParams) (ports.LogSliceResult, error) {
	f.LastParams = params
	f.Calls++
	if f.Err != nil {
		return ports.LogSliceResult{}, f.Err
	}
	return f.SliceResult, nil
}

func (f *FakeLogReader) SetLogLevel(level string) (ports.LogLevelResult, error) {
	f.LastLevel = level
	f.Calls++
	if f.Err != nil {
		return ports.LogLevelResult{}, f.Err
	}
	return f.LevelResult, nil
}

func (f *FakeLogReader) LogPosition() (ports.LogPosition, error) {
	f.Calls++
	f.PositionCall++
	if f.PositionErr != nil {
		return ports.LogPosition{}, f.PositionErr
	}
	if f.Err != nil {
		return ports.LogPosition{}, f.Err
	}
	return f.MarkResult, nil
}

func (f *FakeLogReader) WaitForLog(wait ports.LogWait) (ports.LogMatch, error) {
	f.LastWait = wait
	f.Calls++
	f.WaitCalls++
	if f.Err != nil {
		return ports.LogMatch{}, f.Err
	}
	return f.MatchResult, nil
}
