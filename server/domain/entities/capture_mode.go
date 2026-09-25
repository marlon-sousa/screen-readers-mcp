// screenreader-mcp domain -- CaptureMode: how speech is captured for a session.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: entity; the domain's spelling of the wire's capture mode, fixed at hello for the whole session.
// BUILT BY: the agent, through the connect_reader parameter, carried into the handshake in ports.SessionOptions.
// READ BY: adapters/bridge/handshake.go and reader_session.go.
package entities

import "fmt"

type CaptureMode string

const (
	CaptureSilent CaptureMode = "silent"

	CaptureLive CaptureMode = "live"
)

func (m CaptureMode) String() string { return string(m) }

func ParseCaptureMode(value string) (CaptureMode, error) {
	switch CaptureMode(value) {
	case CaptureSilent:
		return CaptureSilent, nil
	case CaptureLive:
		return CaptureLive, nil
	default:
		return "", fmt.Errorf("capture mode %q: want %q or %q", value, CaptureSilent, CaptureLive)
	}
}
