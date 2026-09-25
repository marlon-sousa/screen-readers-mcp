// screenreader-mcp adapters -- Handshake: the SessionDialer.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter implementing the SessionDialer port: tries a reader's endpoints in order and completes `hello` with the first that answers.
// BUILT BY: wiring/wiring.go.
// USED BY: the connection controller, only when an agent asks to connect.
package bridge

import (
	"errors"
	"fmt"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/adapters/wire"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// DialerFactory turns an endpoint into a way to reach it.
type DialerFactory func(entities.Endpoint) (adapterports.Dialer, error)

// Handshake dials and completes `hello`.
type Handshake struct {
	dialerFor DialerFactory
	clock     ports.Clock
	log       ports.Log
}

var _ ports.SessionDialer = (*Handshake)(nil)

func NewHandshake(dialerFor DialerFactory, clock ports.Clock, log ports.Log) *Handshake {
	return &Handshake{dialerFor: dialerFor, clock: clock, log: log}
}

// Dial tries each of the reader's endpoints in declared order.
func (h *Handshake) Dial(reader entities.ConfiguredReader, opts ports.SessionOptions) (*ports.ReaderConnection, error) {
	if opts.Mode == "" {
		return nil, errors.New("capture mode is required")
	}
	if len(reader.Endpoints) == 0 {
		return nil, fmt.Errorf("reader %q has no configured endpoints", reader.Name)
	}

	var failures []error
	for _, endpoint := range reader.Endpoints {
		connection, err := h.dialOne(endpoint, opts)
		if err == nil {
			h.log.Infof("connected to %q over %s", connection.Session.Reader.Name, endpoint)
			return connection, nil
		}

		var mismatch *ports.ProtocolMismatchError
		if errors.As(err, &mismatch) {
			// A bridge answered with a version mismatch; trying its other transport would bury that answer.
			return nil, err
		}
		h.log.Debugf("reader %q: endpoint %s did not answer: %v", reader.Name, endpoint, err)
		failures = append(failures, fmt.Errorf("%s: %w", endpoint, err))
	}
	return nil, fmt.Errorf("reader %q: no endpoint answered: %w", reader.Name, errors.Join(failures...))
}

// dialOne opens one endpoint and completes the handshake over it.
func (h *Handshake) dialOne(endpoint entities.Endpoint, opts ports.SessionOptions) (*ports.ReaderConnection, error) {
	dial, err := h.dialerFor(endpoint)
	if err != nil {
		return nil, err
	}
	transport, err := dial()
	if err != nil {
		return nil, err
	}
	client := NewJSONLinesClient(transport, h.clock, h.log)
	connection, err := h.hello(client, endpoint, opts)
	if err != nil {
		_ = client.Close()
		return nil, err
	}
	return connection, nil
}

// hello sends the handshake and turns its reply into domain vocabulary.
func (h *Handshake) hello(client *JSONLinesClient, endpoint entities.Endpoint, opts ports.SessionOptions) (*ports.ReaderConnection, error) {
	params := wire.HelloParams{
		Mode:            wire.CaptureMode(opts.Mode),
		ProtocolVersion: wire.ProtocolVersion,
	}
	if opts.LogLevel != nil {
		level := wire.LogLevel(*opts.LogLevel)
		params.LogLevel = &level
	}
	// Nil stays off the params so the bridge applies its own per-mode default.
	if opts.Normalize != nil {
		normalize := *opts.Normalize
		params.Normalize = &normalize
	}
	if opts.Persona != "" {
		// A bridge that does not recognise the persona must degrade rather than refuse the handshake.
		persona := opts.Persona.String()
		params.Persona = &persona
	}

	var result wire.HelloResult
	if err := client.call(wire.CommandHello, params, &result, DefaultCallTimeout); err != nil {
		return nil, err
	}

	if !wire.Supports(result.ProtocolVersion) {
		return nil, &ports.ProtocolMismatchError{
			BridgeVersion:  result.ProtocolVersion,
			ServerVersions: wire.SupportedVersions(),
		}
	}

	announced := make([]string, len(result.Capabilities))
	for i, capability := range result.Capabilities {
		// Unknown capability strings are kept so `screenreader://info` describes the reader honestly.
		announced[i] = string(capability)
	}
	capabilities := entities.NewSet(announced)

	session := entities.ReaderSession{
		Reader: entities.ReaderIdentity{
			Name:    result.Reader.Name,
			Version: result.Reader.Version,
		},
		Capabilities: capabilities,
		Mode:         entities.CaptureMode(result.Mode),
		// The persona the agent declared, not one the bridge confirmed.
		Persona:         opts.Persona,
		Synth:           result.Synth,
		LogPath:         result.LogPath,
		BridgeVersion:   derefOr(result.BridgeVersion, ""),
		ProtocolVersion: result.ProtocolVersion,
	}
	// Nil means the bridge did not send the field, which differs from "not capped".
	if result.SilenceCap != nil {
		session.SilenceCap = &entities.SilenceCap{
			Enabled:   result.SilenceCap.Enabled,
			WarnAfter: result.SilenceCap.WarnAfterSeconds,
			LiftAfter: result.SilenceCap.LiftAfterSeconds,
		}
	}

	// Nil is preserved: "this bridge does not say" is a third answer the sentence renderer handles.
	if result.Attended != nil {
		attended := *result.Attended
		session.Attended = &attended
	}

	for _, entry := range result.Normalized {
		session.Normalized = append(session.Normalized, entities.NormalizedSetting{
			KeyPath:  entry.KeyPath,
			Previous: entry.Previous,
			Current:  entry.Current,
			Why:      entry.Why,
		})
	}

	connection := &ports.ReaderConnection{
		Session:   session,
		Endpoint:  endpoint,
		Lifecycle: client,
	}
	// A port is handed over only when the reader announced it, so a missing capability yields a nil collaborator.
	if capabilities.Has(entities.CapabilitySpeech) {
		connection.Speech = client
	}
	if capabilities.Has(entities.CapabilityBraille) {
		connection.Braille = client
	}
	if capabilities.Has(entities.CapabilityGestures) {
		connection.Gestures = client
	}
	if capabilities.Has(entities.CapabilityFocus) {
		connection.Focus = client
	}
	if capabilities.Has(entities.CapabilityState) {
		connection.State = client
		// Both halves ride the one capability; the reader's per-field write limits are enforced at the bridge.
		connection.StateWrite = client
	}
	if capabilities.Has(entities.CapabilityConfig) {
		connection.Config = client
	}
	if capabilities.Has(entities.CapabilityLog) {
		connection.ReaderLog = client
	}
	if capabilities.Has(entities.CapabilityInteract) {
		connection.Interact = client
	}
	if capabilities.Has(entities.CapabilityTyping) {
		connection.Text = client
	}
	if capabilities.Has(entities.CapabilityGuidance) {
		connection.Guidance = client
	}
	if capabilities.Has(entities.CapabilityDocument) {
		connection.Document = client
	}
	// Absent from an older bridge, in which case the controller falls back to a getGuidance round trip.
	if result.Guidance != nil {
		connection.GuidanceDocument = &entities.ReaderGuidanceDocument{
			Reader:     result.Reader.Name,
			Persona:    entities.Persona(result.Guidance.Persona),
			Recognised: result.Guidance.Recognised,
			Text:       result.Guidance.Text,
		}
	}
	return connection, nil
}

// derefOr reads an optional wire field; nil means the bridge did not send it.
func derefOr(value *string, fallback string) string {
	if value == nil {
		return fallback
	}
	return *value
}
