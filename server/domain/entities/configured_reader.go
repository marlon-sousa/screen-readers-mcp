// screenreader-mcp domain -- ConfiguredReader: one reader we know how to reach.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
// ROLE: entity; a reader name plus every endpoint its bridge listens on, tried in declared order.
// BUILT BY: config/loader.go, never the namespace scanner, because only a configured endpoint may be connected to.
// READ BY: adapters/bridge/handshake.go and reader_listing.go.
package entities

type ConfiguredReader struct {
	Name      string
	Endpoints []Endpoint
}
