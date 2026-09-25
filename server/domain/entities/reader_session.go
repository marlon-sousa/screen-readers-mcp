// screenreader-mcp domain -- ReaderSession: what `hello` established.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, the immutable description of the live session: which reader answered, what it can do, and where its logs are.
// BUILT BY: adapters/bridge/handshake.go, from the wire's HelloResult.
// READ BY: the `status` tool, the `screenreader://info` resource and the tool controllers that need the reader's identity.
package entities

import "encoding/json"

type ReaderIdentity struct {
	Name    string
	Version string
}

type ReaderSession struct {
	// Reader is the identity the bridge announced; never infer it from the
	// endpoint that was dialed.
	Reader ReaderIdentity

	Capabilities Set

	Mode CaptureMode

	Persona Persona

	Synth string

	LogPath string

	// BridgeVersion is empty or "unknown" when the bridge could not determine it.
	BridgeVersion string

	ProtocolVersion int

	// SilenceCap nil means the bridge did not say, which is an older build and
	// not an uncapped machine.
	SilenceCap *SilenceCap

	// Attended nil means the bridge did not say, and attendance is then inferred
	// from SilenceCap. An agent must never be able to set it.
	Attended *bool

	// Normalized empty means the session is driving the user's own configuration.
	Normalized []NormalizedSetting
}

type NormalizedSetting struct {
	KeyPath []string

	Previous json.RawMessage
	Current  json.RawMessage

	Why string
}
