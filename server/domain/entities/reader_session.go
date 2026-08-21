// screenreader-mcp domain -- ReaderSession: what `hello` established.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. The immutable description of the one live session: which reader
// answered, what it can do, and where its two log files are.
// BUILT BY: adapters/bridge/handshake.go, mapping the wire's HelloResult into
// domain vocabulary.
// READ BY: 10b's `status` tool and the `screenreader://info` resource, and by
// the tool controllers that need the reader's identity.
//
// This is where spec 0005's principle 2 lands: the server never asks "is this
// NVDA?", it just hands the agent the reader's name and version and lets the
// agent apply what it already knows about that reader.
package entities

import "encoding/json"

// ReaderIdentity is which screen reader answered. Its own type rather than two
// loose strings, because identity travels together everywhere it goes.
type ReaderIdentity struct {
	Name    string
	Version string
}

// ReaderSession is the established session, as `hello` described it.
type ReaderSession struct {
	// Reader is the identity the bridge announced. The sole authority on
	// which reader answered -- never inferred from the endpoint that was
	// dialed.
	Reader ReaderIdentity

	// Capabilities is what this bridge announced it can serve.
	Capabilities Set

	// Mode is the capture mode now in effect, which the bridge confirmed.
	// Fixed for the session's lifetime.
	Mode CaptureMode

	// Persona is what this session is standing in for (spec 0029), and it is
	// the one field here the agent DECLARED rather than the bridge announced.
	// It is recorded on the session because everything that describes a
	// session afterwards -- status, screenreader://info, the session record --
	// has to carry it: the same observation is a pass from one stance and a
	// finding from another, and a reader of the evidence cannot tell which
	// claim was made without it.
	//
	// The bridge is TOLD the persona at `hello` and records it in its own
	// transcript, but it does not echo it back: an echo would carry no
	// information, since a bridge cannot confirm or refuse a stance the way it
	// confirms a capture mode.
	Persona Persona

	// Synth is the reader's current speech synthesizer.
	Synth string

	// LogPath is this session's human-readable transcript, written by the
	// bridge.
	LogPath string

	// BridgeVersion is the BRIDGE's own version -- the add-on's, not the
	// reader's (that is Reader.Version). Worth carrying because the bridge is
	// installed separately from the code under test: a live run talks to
	// whatever build was last installed, and a stale one otherwise shows up as
	// an inexplicable capability mismatch rather than as "old build". Empty or
	// "unknown" when the bridge could not determine it.
	BridgeVersion string

	// ProtocolVersion is the wire version the bridge answered with. Recorded
	// rather than assumed, so a mismatch can be reported naming both sides.
	ProtocolVersion int

	// SilenceCap is whether the READER'S MACHINE bounds how long a silent
	// session may keep its human unable to hear (spec 0032), as announced at
	// `hello`.
	//
	// Nil is a third answer and not a default: this bridge did not say, which
	// is an older build rather than an uncapped machine. Recorded on the
	// session because it is fixed for the session's lifetime, like Mode -- and
	// like Mode, it is the BRIDGE's answer rather than anything the agent
	// asked for. Nothing in this server can change it.
	SilenceCap *SilenceCap

	// Normalized is every reader setting this SESSION moved from one output
	// channel to another at `hello` (spec 0024) -- on NVDA, turning the
	// browse/focus earcon into spoken words so a capture that reads only
	// speech can see a mode change at all.
	//
	// EMPTY MEANS THE SESSION IS DRIVING THE USER'S OWN CONFIGURATION, which
	// is what an agent needs to know before it reports a finding: a finding
	// made under settings we imposed carries an asterisk, and this is where
	// the asterisk is written down rather than implied. Recorded on the
	// session because it is fixed for its lifetime, and restored by the
	// bridge at teardown either way.
	Normalized []NormalizedSetting
}

// NormalizedSetting is one setting the session moved between channels, and why.
//
// The reason is the bridge's own fixed string rather than anything this server
// composes: the server does not know what the key means on that reader, and a
// reason invented here could disagree with the one in the reader's transcript.
type NormalizedSetting struct {
	// KeyPath is the reader's own config path, outermost key first.
	KeyPath []string

	// Previous and Current are the reader's own values, opaque here.
	Previous json.RawMessage
	Current  json.RawMessage

	// Why is one line, written by the bridge, for the human reading the record.
	Why string
}
