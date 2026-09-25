// screenreader-mcp domain -- ConnectionState: the session lifecycle states.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: entity; the states the one connection moves through, with the reason that goes with each.
// BUILT BY: domain/controllers/connection.go, which owns the transitions.
// READ BY: the `status` tool.
package entities

type ConnectionState string

const (
	Disconnected ConnectionState = "disconnected"

	Connecting ConnectionState = "connecting"

	Connected ConnectionState = "connected"

	// Incompatible means a bridge answered with an unsupported protocol version; the process stays up so status can keep saying so.
	Incompatible ConnectionState = "incompatible"
)

func (s ConnectionState) String() string { return string(s) }

// ConnectionStatus.Reason is empty for the uneventful states and set for the ones an agent must act on.
type ConnectionStatus struct {
	State  ConnectionState
	Reason string
}
