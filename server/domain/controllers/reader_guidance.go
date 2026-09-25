// screenreader-mcp domain -- ReaderGuidance: the reader's own persona document.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller serving the connected bridge's guidance for the session's persona, from the handshake or fetched once per session.
// BUILT BY: wiring/wiring.go.
// USED BY: adapters/mcp's reader-guidance resource.
//
// The fallback cache is keyed on the live *ReaderConnection, so a reconnect can never be served the previous session's text.
package controllers

import (
	"errors"
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// ErrNoSession means nothing is connected; the resource still answers.
var ErrNoSession = errors.New("no reader is connected")

// ErrNoReaderGuidance means the bridge did not announce `guidance`, a supported configuration.
var ErrNoReaderGuidance = errors.New("this bridge publishes no guidance of its own")

type GuidanceSessionSource interface {
	Current() *ports.ReaderConnection
}

// ReaderGuidanceDocument aliases the entity, because ReaderConnection carries one and a port may not import a controller.
type ReaderGuidanceDocument = entities.ReaderGuidanceDocument

type ReaderGuidance struct {
	sessions GuidanceSessionSource

	// Two resource reads can arrive concurrently; the mutex stops both making the round trip.
	mu      sync.Mutex
	forConn *ports.ReaderConnection
	cached  ReaderGuidanceDocument
}

func NewReaderGuidance(sessions GuidanceSessionSource) *ReaderGuidance {
	return &ReaderGuidance{sessions: sessions}
}

// Document surfaces a bridge that announced `guidance` and then refused as that error, not as a degraded document.
func (g *ReaderGuidance) Document() (ReaderGuidanceDocument, error) {
	connection := g.sessions.Current()
	if connection == nil {
		return ReaderGuidanceDocument{}, ErrNoSession
	}
	if connection.GuidanceDocument != nil {
		return *connection.GuidanceDocument, nil
	}
	if connection.Guidance == nil {
		return ReaderGuidanceDocument{}, ErrNoReaderGuidance
	}

	g.mu.Lock()
	defer g.mu.Unlock()
	if g.forConn == connection {
		return g.cached, nil
	}

	guidance, err := connection.Guidance.Guidance()
	if err != nil {
		// Nothing is cached on a failure, so the next read tries again.
		return ReaderGuidanceDocument{}, err
	}

	g.cached = ReaderGuidanceDocument{
		Reader: connection.Session.Reader.Name,
		// From the bridge's echo, so the document reports what the bridge answered for.
		Persona:    entities.Persona(guidance.Persona),
		Recognised: guidance.Recognised,
		Text:       guidance.Text,
	}
	g.forConn = connection
	return g.cached, nil
}
