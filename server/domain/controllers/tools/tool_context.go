// screenreader-mcp domain -- ToolContext and ConnectionControl.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: parameter object (ToolContext) plus the narrow interface to the connection lifecycle (ConnectionControl); it does no IO.
// BUILT BY: dispatcher.go, freshly per call.
// USED BY: every tool in this directory.
package tools

import (
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// ConnectionControl is satisfied by domain/controllers/connection.go.
type ConnectionControl interface {
	// List learns what it can about each endpoint without dialing anything.
	List() entities.ReaderListing

	// Connect tries the named reader's endpoints in declared order, never retrying or falling back to another reader.
	Connect(readerName string, opts ports.SessionOptions) (*ports.ReaderConnection, error)

	Disconnect() error

	Status() entities.ConnectionStatus

	// Current is the live connection, or nil when there is none.
	Current() *ports.ReaderConnection

	// Verify pings and records any loss it finds; it also returns nil when there is no session to verify.
	Verify() (ports.PingReport, error)
}

// Capability ports are reachable only through the accessor methods, so a gated tool cannot skip the capability check.
type ToolContext struct {
	Tool string

	Control ConnectionControl

	// Connection is nil when no session is live.
	Connection *ports.ReaderConnection

	Clock ports.Clock
	Log   ports.Log
}

func (c ToolContext) Session() (entities.ReaderSession, error) {
	if c.Connection == nil {
		return entities.ReaderSession{}, c.missing("")
	}
	return c.Connection.Session, nil
}

func (c ToolContext) Speech() (ports.SpeechReader, error) {
	if c.Connection == nil || c.Connection.Speech == nil {
		return nil, c.missing(entities.CapabilitySpeech)
	}
	return c.Connection.Speech, nil
}

func (c ToolContext) Braille() (ports.BrailleReader, error) {
	if c.Connection == nil || c.Connection.Braille == nil {
		return nil, c.missing(entities.CapabilityBraille)
	}
	return c.Connection.Braille, nil
}

func (c ToolContext) Gestures() (ports.GestureSender, error) {
	if c.Connection == nil || c.Connection.Gestures == nil {
		return nil, c.missing(entities.CapabilityGestures)
	}
	return c.Connection.Gestures, nil
}

func (c ToolContext) Focus() (ports.FocusInspector, error) {
	if c.Connection == nil || c.Connection.Focus == nil {
		return nil, c.missing(entities.CapabilityFocus)
	}
	return c.Connection.Focus, nil
}

func (c ToolContext) State() (ports.StateInspector, error) {
	if c.Connection == nil || c.Connection.State == nil {
		return nil, c.missing(entities.CapabilityState)
	}
	return c.Connection.State, nil
}

func (c ToolContext) Document() (ports.DocumentReader, error) {
	if c.Connection == nil || c.Connection.Document == nil {
		return nil, c.missing(entities.CapabilityDocument)
	}
	return c.Connection.Document, nil
}

// StateWriter shares the state capability; what may be set is limited per field at the bridge.
func (c ToolContext) StateWriter() (ports.StateWriter, error) {
	if c.Connection == nil || c.Connection.StateWrite == nil {
		return nil, c.missing(entities.CapabilityState)
	}
	return c.Connection.StateWrite, nil
}

func (c ToolContext) Config() (ports.ConfigAccessor, error) {
	if c.Connection == nil || c.Connection.Config == nil {
		return nil, c.missing(entities.CapabilityConfig)
	}
	return c.Connection.Config, nil
}

func (c ToolContext) Interact() (ports.Interact, error) {
	if c.Connection == nil || c.Connection.Interact == nil {
		return nil, c.missing(entities.CapabilityInteract)
	}
	return c.Connection.Interact, nil
}

func (c ToolContext) Text() (ports.TextTyper, error) {
	if c.Connection == nil || c.Connection.Text == nil {
		return nil, c.missing(entities.CapabilityTyping)
	}
	return c.Connection.Text, nil
}

func (c ToolContext) ReaderLog() (ports.LogReader, error) {
	if c.Connection == nil || c.Connection.ReaderLog == nil {
		return nil, c.missing(entities.CapabilityLog)
	}
	return c.Connection.ReaderLog, nil
}

func (c ToolContext) missing(capability entities.Capability) *CapabilityError {
	failure := &CapabilityError{Tool: c.Tool, Capability: capability}
	if c.Connection != nil {
		failure.Reader = c.Connection.Session.Reader.Name
	}
	return failure
}
