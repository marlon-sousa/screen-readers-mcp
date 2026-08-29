// screenreader-mcp adapters -- LocalProbe: the EndpointProbe.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. IMPLEMENTS the domain's EndpointProbe port: of the endpoints it
// is handed, which have a bridge listening.
// DEPENDS ON: the LocalDirectory seam (adapters/discovery/ports), never the OS
// directly.
// BUILT BY: wiring/wiring.go.
// USED BY: 10b's connection controller, for list_readers.
//
// The decision this file holds is small and important: it walks the CANDIDATES
// and asks the listing about each, never the other way round. An endpoint that
// is listening but belongs to no configured reader is therefore invisible here
// and cannot be connected to -- spec 0013's determinism rule, and the reason the
// method takes candidates instead of returning discoveries.
//
// It is platform-free, and that is what the seam buys: Windows answers from the
// named-pipe namespace and POSIX from a directory of socket files, both in bare
// endpoint names, so this file never learns which host it is on.
//
// It never dials. The bridge accepts one session at a time, so a probe that
// connected would occupy the slot the agent is about to ask for.
package discovery

import (
	"strings"

	discoveryports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/discovery/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/ports"
)

// LocalProbe answers liveness for local endpoints by reading the host's
// namespace.
type LocalProbe struct {
	directory discoveryports.LocalDirectory
}

var _ ports.EndpointProbe = (*LocalProbe)(nil)

// NewLocalProbe builds the probe over a directory listing.
func NewLocalProbe(directory discoveryports.LocalDirectory) *LocalProbe {
	return &LocalProbe{directory: directory}
}

// Live returns the candidates that have a bridge listening.
//
// Only local endpoints addressed by NAME can appear. A TCP endpoint cannot be
// tested without connecting, so it is simply absent and the caller reports it
// as unknown; so is a local endpoint addressed by a path, which the listing
// does not cover and must not be called not-listening on that account. The
// listing is read ONCE per call, so every candidate is judged against the same
// snapshot rather than against a namespace that may change between two of them.
func (p *LocalProbe) Live(candidates []entities.Endpoint) []entities.Endpoint {
	present := map[string]struct{}{}
	for _, name := range p.directory.Names() {
		// Windows pipe names are case-insensitive, so the comparison is
		// too -- otherwise a user who wrote `NvdaMcpBridge` in a config file
		// would be told nothing is listening while their bridge is running.
		// It stays folded on POSIX as well: macOS is case-insensitive by
		// default, and splitting the rule per host would put a platform
		// decision back into the one file that has none. The cost of a wrong
		// match on a case-sensitive filesystem is a dial that then fails, not
		// a connection to something else.
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
