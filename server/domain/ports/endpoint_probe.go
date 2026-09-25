// screenreader-mcp domain -- the EndpointProbe port.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: domain port, liveness of endpoints already configured.
// IMPLEMENTED BY: adapters/discovery/local_probe.go.
// USED BY: the connection controller, via entities.BuildListing.
//
// It must never return an endpoint nobody configured.
package ports

import "github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"

// EndpointProbe must never dial: the bridge's single session slot would be taken.
type EndpointProbe interface {
	// Live omits an endpoint that is either not listening or not knowable; only
	// a local endpoint addressed by name is knowable.
	Live(candidates []entities.Endpoint) []entities.Endpoint
}
