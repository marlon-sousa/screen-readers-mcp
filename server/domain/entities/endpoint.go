// screenreader-mcp domain -- Endpoint: one place a bridge may listen.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, an immutable endpoint value plus the parsing of its `local:<name>` / `tcp:<host>:<port>` spelling.
// BUILT BY: config/loader.go, via wiring.
// READ BY: adapters/bridge/endpoint.go, adapters/discovery/local_probe.go and reader_listing.go.
package entities

import (
	"fmt"
	"strings"
)

type TransportKind string

const (
	// TransportLocal is a named pipe on Windows and an AF_UNIX socket on POSIX,
	// addressed by a bare name each platform resolves its own way.
	TransportLocal TransportKind = "local"

	TransportTCP TransportKind = "tcp"

	// transportPipeAlias parses as `local` and is never printed, because existing
	// config files still carry it.
	transportPipeAlias = "pipe"
)

type Endpoint struct {
	Kind    TransportKind
	Address string
}

// ParseEndpoint splits on the first colon only, because a TCP address carries its own.
func ParseEndpoint(spec string) (Endpoint, error) {
	kind, address, found := strings.Cut(spec, ":")
	if !found || address == "" {
		return Endpoint{}, fmt.Errorf("endpoint %q: want local:<name> or tcp:<host>:<port>", spec)
	}
	switch kind {
	case string(TransportLocal), transportPipeAlias:
		return Endpoint{Kind: TransportLocal, Address: address}, nil
	case string(TransportTCP):
		if !strings.Contains(address, ":") {
			return Endpoint{}, fmt.Errorf("endpoint %q: tcp needs <host>:<port>", spec)
		}
		return Endpoint{Kind: TransportTCP, Address: address}, nil
	default:
		return Endpoint{}, fmt.Errorf("endpoint %q: unknown transport %q", spec, kind)
	}
}

func (e Endpoint) String() string { return string(e.Kind) + ":" + e.Address }

// IsBareName rejects both path separators on every host, so one config file
// gets the same answer on Windows and on macOS.
func IsBareName(address string) bool {
	return address != "" && !strings.ContainsAny(address, `/\`)
}
