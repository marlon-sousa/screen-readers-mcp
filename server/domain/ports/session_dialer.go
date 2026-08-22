// screenreader-mcp domain -- the SessionDialer port.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port. Dial one reader's bridge and complete the handshake.
// IMPLEMENTED BY: adapters/bridge/handshake.go.
// USED BY: 10b's connection controller, driven by the connect_reader tool. The
// server NEVER dials on its own -- no auto-connect, no retry loop, no backoff --
// so every call to Dial is one the agent asked for.
//
// SPEC AMENDMENT (rides in 10a, per the workflow rule): spec 0013's deliverable
// 2 describes this port as returning "a ReaderSession value". Delivery needs one
// thing more -- the caller must also be handed the live collaborators to serve
// tool calls with, and something to end the session with -- so Dial returns a
// ReaderConnection: the session description, which endpoint answered, the
// capability ports, and a SessionLifecycle. The capability ports being FIELDS
// that are nil when unannounced is what makes the capability gate structural,
// which was the reason for splitting the ports in the first place.
// SessionLifecycle lives in this file rather than in an eighth port file because
// it is the dialer's own signalling type -- what Dial hands back -- exactly as
// AGENTS.md places a port's DTOs with the port.
package ports

import (
	"errors"
	"fmt"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// ErrConnectionLost is the connection ending underneath a call: EOF, a reset, or
// a close.
//
// SPEC AMENDMENT (rides in 10b): 10a declared this sentinel in adapters/bridge,
// where it was raised. It belongs here, because the party that must RECOGNISE a
// loss is the connection controller -- it records the loss and why -- and the
// domain may not import an adapter. bridge.ErrConnectionLost is
// now an alias of this, so no 10a call site changed.
//
// A sentinel rather than a type because the response is the same whatever the
// cause: record it, and let the agent connect again when it chooses.
var ErrConnectionLost = errors.New("bridge connection lost")

// SessionOptions are what the AGENT chose for this session, all of which the
// wire fixes at `hello` for the session's whole lifetime (protocol.md §3, §4).
//
// They are parameters and not CLI flags precisely because of that: under
// auto-connect they would have to be chosen by whoever wrote the MCP host
// config, before anyone knew what the session was for. As connect_reader
// parameters they are chosen per session by the party that knows what it is
// about to do.
type SessionOptions struct {
	// Mode fixes how speech is captured for the session.
	Mode entities.CaptureMode

	// Persona is what the agent is standing in for (spec 0029): it decides
	// what a finding from this session MEANS, so it cannot be retrofitted
	// onto a session that already ran.
	Persona entities.Persona

	// LogLevel optionally raises the READER's own diagnostic verbosity for
	// the session. Nil leaves it unchanged.
	LogLevel *entities.ReaderLogLevel

	// Normalize asks the reader to move signals a session cannot capture --
	// a mode change answered with a sound rather than words -- into the
	// speech channel it can (spec 0024).
	//
	// NIL IS NOT FALSE: it means "whatever this capture mode's default is",
	// and the two modes differ on purpose. A silent session normalises,
	// because the human hears no speech anyway and nothing is taken from
	// them; a live session does not, because the person would hear words
	// instead of the tone they chose, which is theirs to decide. Only the
	// caller's SILENCE is ambiguous, so only the caller's silence defers.
	Normalize *bool
}

// SessionLifecycle is what a live session can be asked beyond its capabilities:
// the lifecycle and diagnostic commands, which belong to no capability group and
// are always available once the handshake has completed (protocol.md §4).
// PingReport is what a ping answered BEYOND "it answered".
//
// SPEC AMENDMENT (rides in 11.10, per the workflow rule): spec 0032 Part 8 says
// `status` reports whether suppression is currently in force, and a lift happens
// on the READER, asynchronously, with nothing pushed (spec 0021 stands). So the
// only honest way to answer is to ask -- and `status` already makes a real `ping`
// round trip precisely so its answer is proof rather than memory. The fact rides
// on the probe that was being sent anyway; the alternatives were a second round
// trip, or a cached value that could be wrong at exactly the moment it mattered.
//
// Its own struct rather than a second return value, so "and what else did the
// probe learn" stays a field rather than a signature change at six call sites.
type PingReport struct {
	// Suppressing is whether the reader is withholding speech from its human
	// right now. Nil from a bridge that does not say -- which is an older
	// build, not an answer.
	Suppressing *bool
}

type SessionLifecycle interface {
	// Ping proves the connection is real right now. It resets the bridge's
	// heartbeat watchdog but deliberately NOT its command-inactivity
	// watchdog, so a keepalive cannot mask an abandoned session -- which is
	// why an idle agent still loses its session, by design.
	//
	// Its report is meaningful only when the error is nil.
	Ping() (PingReport, error)

	// Bye asks the bridge to end the session cleanly. Sent by
	// disconnect_reader; the bridge restores speech on this path as on every
	// other.
	Bye() error

	// Close drops the connection without asking. Safe to call after Bye, and
	// after a loss, so teardown paths need no bookkeeping to avoid a double
	// close.
	Close() error
}

// ReaderConnection is one live session: what was established, and what may be
// asked of it.
//
// The capability ports are nil exactly when the reader did not announce the
// matching capability. That is deliberate and load-bearing: "this reader has no
// braille" is a collaborator that was never handed over, not a boolean somebody
// must remember to check.
type ReaderConnection struct {
	// Session is what `hello` established, including which reader answered.
	Session entities.ReaderSession

	// Endpoint is the one that actually answered, out of the reader's
	// declared endpoints. Reported back to the agent, because with a bridge
	// that can be toggled between pipe and TCP, "which one answered" is a
	// real answer and not an implementation detail.
	Endpoint entities.Endpoint

	// Lifecycle is always present.
	Lifecycle SessionLifecycle

	// The capability ports. Nil unless announced.
	Speech   SpeechReader
	Braille  BrailleReader
	Gestures GestureSender
	Focus    FocusInspector
	State    StateInspector
	// StateWrite is handed out on the SAME capability as State -- `state`
	// covers reading modes and arriving at them, the way `config` covers
	// reading and writing config (spec 0033).
	StateWrite StateWriter
	Config     ConfigAccessor
	Interact   Interact
	Text       TextTyper
	ReaderLog  LogReader
	// Document is the `document` capability: the reader's flat document
	// rendering, handed over whole (spec 0026).
	Document DocumentReader

	// Guidance is the odd one out and is worth saying so: every other port
	// here backs a TOOL, and this one backs a RESOURCE
	// (screenreader://reader-guidance). The gate is the same structural one --
	// nil unless the reader announced `guidance`.
	//
	// It is now the FALLBACK route rather than the usual one: a bridge that
	// speaks spec 0022 A.5 delivers the document in the handshake, and this
	// port is only reached for one that does not.
	Guidance GuidanceReader

	// GuidanceDocument is that document, when the handshake carried it.
	//
	// Nil means the bridge sent none -- either it publishes no guidance at all,
	// or it predates the field and must be asked through Guidance above.
	//
	// Holding it ON THE CONNECTION is what makes "this session's document"
	// structural: a reconnect produces a different *ReaderConnection, so the
	// previous session's text cannot be served to the new one. The controller
	// used to get that property from a cache keyed on this same pointer; now it
	// does not need the cache.
	GuidanceDocument *entities.ReaderGuidanceDocument
}

// SessionDialer opens a session with one configured reader.
type SessionDialer interface {
	// Dial tries the reader's endpoints IN DECLARED ORDER and completes the
	// handshake with the first that answers.
	//
	// It returns an error rather than retrying: a failed connect leaves the
	// caller Disconnected and tells the agent why, and the agent decides
	// whether to try again.
	Dial(reader entities.ConfiguredReader, opts SessionOptions) (*ReaderConnection, error)
}

// ProtocolMismatchError is a bridge answering with a wire version this server
// does not support.
//
// Its own error type, and owned by this port, because it is the one connection
// failure with a different remedy: not "try again" but "update one of the two
// components". The caller reports it, records the Incompatible state, and keeps
// the process alive -- restarting the add-on and connecting again then fixes it
// without restarting the MCP host.
type ProtocolMismatchError struct {
	// BridgeVersion is what the bridge announced.
	BridgeVersion int

	// ServerVersions is every version this server supports. A set, not a
	// single constant, so that accepting more than one later is a change to
	// data rather than to control flow (spec 0013, "The domain never speaks
	// wire types").
	ServerVersions []int
}

func (e *ProtocolMismatchError) Error() string {
	return fmt.Sprintf(
		"bridge speaks wire protocol version %d; this server supports %v",
		e.BridgeVersion, e.ServerVersions,
	)
}
