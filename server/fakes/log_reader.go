// screenreader-mcp fakes -- FakeLogReader: the LogReader port double.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: test double. MIRRORS domain/ports/log_reader.go.
// USED BY: the get_log and set_log_level tool controller tests.

package fakes

import (
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// FakeLogReader records what it was asked for and returns scripted responses.
type FakeLogReader struct {
	LastParams  ports.GetLogParams
	SliceResult ports.LogSliceResult
	LevelResult ports.LogLevelResult
	Err         error
}

var _ ports.LogReader = (*FakeLogReader)(nil)

// NewFakeLogReader builds a log reader that returns empty slices.
func NewFakeLogReader() *FakeLogReader {
	return &FakeLogReader{
		SliceResult: ports.LogSliceResult{
			Text:            "",
			Entries:         0,
			Matched:         0,
			Truncated:       false,
			FromCommandID:   1,
			ToCommandID:     1,
			CapturedAtLevel: "info",
		},
		LevelResult: ports.LogLevelResult{
			Level:    "info",
			Previous: "info",
		},
	}
}

func (f *FakeLogReader) GetLog(params ports.GetLogParams) (ports.LogSliceResult, error) {
	f.LastParams = params
	if f.Err != nil {
		return ports.LogSliceResult{}, f.Err
	}
	return f.SliceResult, nil
}

func (f *FakeLogReader) SetLogLevel(level string) (ports.LogLevelResult, error) {
	if f.Err != nil {
		return ports.LogLevelResult{}, f.Err
	}
	return f.LevelResult, nil
}
