// screenreader-mcp testsupport -- builders for a live ReaderConnection.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: test scaffolding, not a port double.
// USED BY: the connection and tool controllers' tests, which need a session with given capabilities and no bridge.
package testsupport

import (
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/fakes"
)

// Capability ports are set only for the capabilities named and left nil otherwise, as the real handshake does.
type Connection struct {
	Connection *ports.ReaderConnection

	// Each fake is nil unless its capability was announced.
	Lifecycle  *fakes.FakeSessionLifecycle
	Speech     *fakes.FakeSpeechReader
	Braille    *fakes.FakeBrailleReader
	Gestures   *fakes.FakeGestureSender
	Focus      *fakes.FakeFocusInspector
	State      *fakes.FakeStateInspector
	StateWrite *fakes.FakeStateWriter
	Config     *fakes.FakeConfigAccessor
	Interact   *fakes.FakeInteractPort
	Text       *fakes.FakeTextTyper
	LogReader  *fakes.FakeLogReader
	Guidance   *fakes.FakeGuidanceReader
}

func NewConnection(reader string, announced ...entities.Capability) *Connection {
	names := make([]string, len(announced))
	for i, capability := range announced {
		names[i] = string(capability)
	}
	set := entities.NewSet(names)

	built := &Connection{Lifecycle: fakes.NewFakeSessionLifecycle()}
	built.Connection = &ports.ReaderConnection{
		Session: entities.ReaderSession{
			Reader:          entities.ReaderIdentity{Name: reader, Version: "1.0"},
			Capabilities:    set,
			Mode:            entities.CaptureSilent,
			Synth:           "fakesynth",
			LogPath:         `C:\logs\session.log`,
			ProtocolVersion: 1,
		},
		Endpoint:  entities.Endpoint{Kind: entities.TransportLocal, Address: reader + "McpBridge"},
		Lifecycle: built.Lifecycle,
	}

	if set.Has(entities.CapabilitySpeech) {
		built.Speech = fakes.NewFakeSpeechReader()
		built.Connection.Speech = built.Speech
	}
	if set.Has(entities.CapabilityBraille) {
		built.Braille = fakes.NewFakeBrailleReader()
		built.Connection.Braille = built.Braille
	}
	if set.Has(entities.CapabilityGestures) {
		built.Gestures = fakes.NewFakeGestureSender()
		built.Connection.Gestures = built.Gestures
	}
	if set.Has(entities.CapabilityFocus) {
		built.Focus = fakes.NewFakeFocusInspector()
		built.Connection.Focus = built.Focus
	}
	if set.Has(entities.CapabilityState) {
		built.State = fakes.NewFakeStateInspector()
		built.Connection.State = built.State
		built.StateWrite = fakes.NewFakeStateWriter()
		built.Connection.StateWrite = built.StateWrite
	}
	if set.Has(entities.CapabilityConfig) {
		built.Config = fakes.NewFakeConfigAccessor()
		built.Connection.Config = built.Config
	}
	if set.Has(entities.CapabilityInteract) {
		built.Interact = fakes.NewFakeInteractPort()
		built.Connection.Interact = built.Interact
	}
	if set.Has(entities.CapabilityTyping) {
		built.Text = fakes.NewFakeTextTyper()
		built.Connection.Text = built.Text
	}
	if set.Has(entities.CapabilityLog) {
		built.LogReader = fakes.NewFakeLogReader()
		built.Connection.ReaderLog = built.LogReader
	}
	if set.Has(entities.CapabilityGuidance) {
		built.Guidance = fakes.NewFakeGuidanceReader()
		built.Connection.Guidance = built.Guidance
	}
	return built
}

func EveryCapability() []entities.Capability {
	return []entities.Capability{
		entities.CapabilitySpeech, entities.CapabilityBraille, entities.CapabilityGestures,
		entities.CapabilityFocus, entities.CapabilityState, entities.CapabilityConfig,
		entities.CapabilityInteract, entities.CapabilityTyping,
		entities.CapabilityLog, entities.CapabilityGuidance,
		entities.CapabilityDocument,
	}
}
