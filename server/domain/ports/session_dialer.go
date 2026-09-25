// screenreader-mcp domain -- the SessionDialer port.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, dial one reader's bridge and complete the handshake.
// IMPLEMENTED BY: adapters/bridge/handshake.go.
// USED BY: the connection controller, driven by the connect_reader tool.
//
// The server never dials on its own: no auto-connect, no retry loop, no backoff.
package ports

import (
	"errors"
	"fmt"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// ErrConnectionLost is the connection ending underneath a call: EOF, a reset, or a close.
var ErrConnectionLost = errors.New("bridge connection lost")

// SessionOptions are fixed at `hello` for the session's whole lifetime.
type SessionOptions struct {
	Mode entities.CaptureMode

	Persona entities.Persona

	// LogLevel nil leaves the reader's log level unchanged.
	LogLevel *entities.ReaderLogLevel

	// Normalize nil means the capture mode's default, which differs between
	// silent and live sessions; it is not false.
	Normalize *bool
}

// PingReport is what a ping answered beyond "it answered".
type PingReport struct {
	// Suppressing nil means the bridge did not say, which is an older build.
	Suppressing *bool
}

type SessionLifecycle interface {
	// Ping resets the bridge's heartbeat watchdog but not its command-inactivity
	// watchdog, so a keepalive cannot mask an abandoned session. Its report is
	// meaningful only when the error is nil.
	Ping() (PingReport, error)

	Bye() error

	// Close must be safe after Bye and after a loss.
	Close() error
}

// ReaderConnection capability ports are nil exactly when the reader did not
// announce the matching capability.
type ReaderConnection struct {
	Session entities.ReaderSession

	Endpoint entities.Endpoint

	Lifecycle SessionLifecycle

	Speech   SpeechReader
	Braille  BrailleReader
	Gestures GestureSender
	Focus    FocusInspector
	State    StateInspector
	// StateWrite is handed out on the same `state` capability as State.
	StateWrite StateWriter
	Config     ConfigAccessor
	Interact   Interact
	Text       TextTyper
	ReaderLog  LogReader
	Document   DocumentReader

	// Guidance is nil unless announced, and is reached only when the handshake
	// carried no GuidanceDocument.
	Guidance GuidanceReader

	// GuidanceDocument nil means the bridge sent none: it publishes no guidance,
	// or it predates the field and must be asked through Guidance.
	GuidanceDocument *entities.ReaderGuidanceDocument
}

type SessionDialer interface {
	// Dial tries the reader's endpoints in declared order and never retries.
	Dial(reader entities.ConfiguredReader, opts SessionOptions) (*ReaderConnection, error)
}

// ProtocolMismatchError is the one connection failure whose remedy is updating
// a component, not trying again.
type ProtocolMismatchError struct {
	BridgeVersion int

	ServerVersions []int
}

func (e *ProtocolMismatchError) Error() string {
	return fmt.Sprintf(
		"bridge speaks wire protocol version %d; this server supports %v",
		e.BridgeVersion, e.ServerVersions,
	)
}
