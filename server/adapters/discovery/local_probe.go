// screenreader-mcp adapters -- LocalProbe: the EndpointProbe.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter implementing the EndpointProbe port: which of the given endpoints have a bridge listening.
// BUILT BY: wiring/wiring.go.
// USED BY: the connection controller, for list_readers.
//
// It never dials: the bridge accepts one session at a time, so a probe that connected would occupy the agent's slot.
package discovery

import (
	"strings"

	discoveryports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

type LocalProbe struct {
	directory discoveryports.LocalDirectory
}

var _ ports.EndpointProbe = (*LocalProbe)(nil)

func NewLocalProbe(directory discoveryports.LocalDirectory) *LocalProbe {
	return &LocalProbe{directory: directory}
}

// Live reports only local endpoints addressed by name; TCP and path endpoints are absent, and the caller reports them as unknown.
func (p *LocalProbe) Live(candidates []entities.Endpoint) []entities.Endpoint {
	present := map[string]struct{}{}
	for _, name := range p.directory.Names() {
		// Folded on every host because Windows pipe names are case-insensitive; a wrong match costs only a failed dial.
		present[strings.ToLower(name)] = struct{}{}
	}

	var live []entities.Endpoint
	for _, candidate := range candidates {
		if candidate.Kind != entities.TransportLocal || !entities.IsBareName(candidate.Address) {
			continue
		}
		if _, ok := present[strings.ToLower(candidate.Address)]; ok {
			live = append(live, candidate)
		}
	}
	return live
}
