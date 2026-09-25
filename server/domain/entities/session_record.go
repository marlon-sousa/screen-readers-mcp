// screenreader-mcp domain -- SessionRecord: the server's own record of a session.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, a bounded, append-only record of every tool call this server dispatched.
// WRITTEN BY: domain/controllers/tools/dispatcher.go, the single route from an MCP request to a tool.
// READ BY: adapters/mcp's screenreader://session-record resource.
package entities

import (
	"sync"
	"time"
)

const MaxRecordedCalls = 1000

const MaxRecordedText = 500

type RecordedCall struct {
	At     time.Time `json:"at"`
	Tool   string    `json:"tool"`
	Params string    `json:"params,omitempty"`
	Result string    `json:"result,omitempty"`
	Error  string    `json:"error,omitempty"`
	Failed bool      `json:"failed"`
}

type SessionRecord struct {
	mu      sync.Mutex
	calls   []RecordedCall
	dropped int
}

func NewSessionRecord() *SessionRecord { return &SessionRecord{} }

func (r *SessionRecord) Add(call RecordedCall) {
	call.Params = capText(call.Params)
	call.Result = capText(call.Result)
	call.Error = capText(call.Error)

	r.mu.Lock()
	defer r.mu.Unlock()
	r.calls = append(r.calls, call)
	if len(r.calls) > MaxRecordedCalls {
		r.dropped += len(r.calls) - MaxRecordedCalls
		r.calls = append([]RecordedCall(nil), r.calls[len(r.calls)-MaxRecordedCalls:]...)
	}
}

func (r *SessionRecord) Calls() []RecordedCall {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]RecordedCall(nil), r.calls...)
}

// Dropped non-zero means the record is a tail, not a whole history.
func (r *SessionRecord) Dropped() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.dropped
}

func capText(text string) string {
	if len(text) <= MaxRecordedText {
		return text
	}
	// Cut on a rune boundary, so the marker is not preceded by half a character.
	cut := MaxRecordedText
	for cut > 0 && !isRuneStart(text[cut]) {
		cut--
	}
	return text[:cut] + "… (truncated)"
}

func isRuneStart(b byte) bool { return b&0xC0 != 0x80 }
