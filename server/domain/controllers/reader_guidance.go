// screenreader-mcp domain -- ReaderGuidance: the reader's own persona document.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: controller. Fetches the connected bridge's guidance for the session's
// persona, once, and remembers it for as long as that session lasts.
// DEPENDS ON: a SessionSource (the connection controller, narrowed) and the
// GuidanceReader port hanging off the live connection.
// BUILT BY: wiring/wiring.go. USED BY: adapters/mcp's reader-guidance resource.
//
// Spec 0029 Part 4.4. Three properties, and each is a decision:
//
//   - LAZY. Nothing is fetched at connect. The round trip happens on the first
//     READ of the resource, so a session that never asks never pays -- and
//     connect stays one round trip, which spec 0025 cares about.
//   - CACHED FOR THE SESSION. The document is static while a session lives, so a
//     second read costs nothing. The cache is keyed on the LIVE CONNECTION
//     ITSELF rather than on a boolean or a persona name: a disconnect and
//     reconnect produces a different *ReaderConnection, so the previous
//     session's text cannot be served to the new one even if the persona is the
//     same. That is the property a "fetched bool" would silently lose.
//   - OPAQUE. The text is carried and never parsed. The precedence frame is the
//     adapter's business (4.1) and framing is all this server ever does to it.
//
// The two degraded cases -- nothing connected, and a bridge that did not
// announce `guidance` -- are reported as SENTINEL ERRORS rather than as prose,
// so the domain says what is true and the adapter says it in words. That is a
// deliberate departure from the spec's Part 5.4 sketch, which put the degraded
// documents here: no domain caller needs their text (unlike Persona.Stance,
// which connect_reader renders), so keeping them beside the resource that serves
// them puts every agent-facing document under one directory instead of two.
package controllers

import (
	"errors"
	"sync"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// ErrNoSession is the resource being read with nothing connected.
//
// Not a failure of the read: the resource is registered whether or not a session
// exists (like info and the session record), because an agent asking what this
// reader expects of it deserves an answer rather than a missing resource.
var ErrNoSession = errors.New("no reader is connected")

// ErrNoReaderGuidance is a bridge that did not announce `guidance`.
//
// Also not a failure: a bridge with nothing reader-specific to say is a
// supported configuration, and the agent falls back on the server's own
// documents, which still carry the rule.
var ErrNoReaderGuidance = errors.New("this bridge publishes no guidance of its own")

// GuidanceSessionSource is the connection, narrowed to the one thing this needs.
//
// Declared here, in the consumer: this controller may look at the live
// connection and may not open, close or verify one.
type GuidanceSessionSource interface {
	Current() *ports.ReaderConnection
}

// ReaderGuidanceDocument is one session's reader-supplied guidance, with the
// facts a frame around it needs: whose account this is, and what it answers for.
type ReaderGuidanceDocument struct {
	// Reader is the name the bridge announced, so the frame can say whose
	// account the agent is reading.
	Reader string

	// Persona is what the bridge answered for, as it echoed it back.
	Persona entities.Persona

	// Recognised is false when the bridge had no section for that persona.
	Recognised bool

	// Text is the bridge's markdown, untouched.
	Text string
}

// ReaderGuidance serves the connected reader's own guidance, once per session.
type ReaderGuidance struct {
	sessions GuidanceSessionSource

	// The mutex guards the cache, and it is not optional: two resource reads
	// can arrive concurrently over MCP, and without it both would make the
	// round trip the cache exists to avoid.
	mu      sync.Mutex
	forConn *ports.ReaderConnection
	cached  ReaderGuidanceDocument
}

// NewReaderGuidance builds the controller with nothing fetched.
func NewReaderGuidance(sessions GuidanceSessionSource) *ReaderGuidance {
	return &ReaderGuidance{sessions: sessions}
}

// Document returns the live session's reader guidance, fetching it at most once
// per session.
//
// A bridge that REFUSES getGuidance -- announced the capability and then errored
// -- surfaces as that error rather than as a degraded document. The two degraded
// cases above are states this server can see and describe; a refusal is the
// bridge contradicting its own announcement, and dressing it up as "this reader
// has nothing to say" would hide a real fault behind a reassuring sentence.
func (g *ReaderGuidance) Document() (ReaderGuidanceDocument, error) {
	connection := g.sessions.Current()
	if connection == nil {
		return ReaderGuidanceDocument{}, ErrNoSession
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
		// Nothing is cached on a failure, so the next read tries again. A
		// cached error would make one bad moment permanent for the session.
		return ReaderGuidanceDocument{}, err
	}

	g.cached = ReaderGuidanceDocument{
		Reader: connection.Session.Reader.Name,
		// From the bridge's echo rather than from the session, so the document
		// reports what the bridge actually answered for. They agree; reporting
		// the echo is what makes that checkable rather than assumed.
		Persona:    entities.Persona(guidance.Persona),
		Recognised: guidance.Recognised,
		Text:       guidance.Text,
	}
	g.forConn = connection
	return g.cached, nil
}
