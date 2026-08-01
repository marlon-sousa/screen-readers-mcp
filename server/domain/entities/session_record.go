// screenreader-mcp domain -- SessionRecord: the server's own record of a session.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. A bounded, append-only record of every tool call this server
// dispatched: when, what was asked, and what came back.
// WRITTEN BY: domain/controllers/tools/dispatcher.go, which is the single route
// from an MCP request to a tool and therefore sees all of it.
// READ BY: adapters/mcp's screenreader://session-record resource.
//
// WHY THE SERVER KEEPS ITS OWN (spec 0021). The bridge already writes a session
// transcript, and it is NOT this: they are two artifacts with two audiences, and
// conflating them was the mistake this entry corrected.
//
//	the transcript  -> the human at the reader. Written bridge-side at CAPTURE
//	                   time, so it is complete even for speech the agent never
//	                   fetched, and stamped with adjacency a server could not
//	                   reproduce. Lives on the reader's disk, reachable by
//	                   logPath, which for a remote bridge is a file the agent
//	                   cannot open at all.
//	this record     -> the AGENT. Built from traffic that already passes through
//	                   this process, so it costs no wire surface, no new command,
//	                   and no ordering constraint on teardown -- and it survives a
//	                   bridge that dies abruptly, where a bridge-side file is
//	                   stranded on a machine nothing can reach any more.
//
// It deliberately does NOT try to be the transcript. It records what the agent
// asked and what it was told, which is exactly the half the agent could not
// otherwise reconstruct after the fact -- not what the reader said to a human.
//
// BOUNDED, for the same reason the log journal is: a session can run for hours,
// and an unbounded list in a long-lived process is a leak with a good excuse.
// Oldest calls age out and the record says how many, so a reader of it is never
// quietly shown a partial history as if it were whole.

package entities

import (
	"sync"
	"time"
)

// MaxRecordedCalls is how many tool calls the record keeps.
//
// Deep enough to cover an ordinary debugging session end to end, shallow enough
// that the whole thing is still readable in one go.
const MaxRecordedCalls = 1000

// MaxRecordedText caps one field's stored length.
//
// A type_text payload or a get_speech answer can be arbitrarily large, and this
// record exists to say WHAT HAPPENED, not to be a second copy of the data. Text
// beyond the cap is replaced by an explicit marker rather than silently cut, so
// nobody reads a truncated value as the real one.
const MaxRecordedText = 500

// RecordedCall is one tool call as this server saw it.
type RecordedCall struct {
	At     time.Time `json:"at"`
	Tool   string    `json:"tool"`
	Params string    `json:"params,omitempty"`
	// Result is the answer, capped; empty when the call failed.
	Result string `json:"result,omitempty"`
	// Error is the failure message; empty when the call succeeded. Exactly one
	// of Result and Error is meaningful, and Failed says which without a caller
	// having to infer it from an empty string.
	Error  string `json:"error,omitempty"`
	Failed bool   `json:"failed"`
}

// SessionRecord holds the calls, newest last.
//
// Guarded, and it has to be: tool calls arrive on the MCP server's goroutines
// while the connection controller's heartbeat runs on its own, and the resource
// that reads this is served on a third.
type SessionRecord struct {
	mu      sync.Mutex
	calls   []RecordedCall
	dropped int
}

// NewSessionRecord builds an empty record.
func NewSessionRecord() *SessionRecord { return &SessionRecord{} }

// Add appends one call, evicting the oldest once the cap is reached.
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

// Calls is a copy of what is held, oldest first.
func (r *SessionRecord) Calls() []RecordedCall {
	r.mu.Lock()
	defer r.mu.Unlock()
	return append([]RecordedCall(nil), r.calls...)
}

// Dropped is how many calls aged out. Non-zero means the record is a tail, not
// a whole history, and whatever renders it should say so.
func (r *SessionRecord) Dropped() int {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.dropped
}

// capText shortens a field to MaxRecordedText, marking that it did.
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

// isRuneStart reports whether b begins a UTF-8 rune (i.e. is not a continuation
// byte). Continuation bytes are 10xxxxxx.
func isRuneStart(b byte) bool { return b&0xC0 != 0x80 }
