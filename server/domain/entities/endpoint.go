// screenreader-mcp domain -- Endpoint: one place a bridge may listen.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. An immutable value, plus the parsing of the `local:<name>` /
// `tcp:<host>:<port>` spelling used in defaults.json, --config and --reader.
// BUILT BY: config/loader.go (from the layered sources), via wiring.
// READ BY: adapters/bridge/endpoint.go (which turns one into a Dialer),
// adapters/discovery/local_probe.go (liveness), reader_listing.go.
//
// Parsing lives here and not in the adapter because it is pure syntax, and the
// same string spelling appears in three places (embedded defaults, config file,
// flag) that must agree. What the adapter keeps is the part that needs to know
// about the OS: whether a host is acceptable to dial, and how this platform
// spells a local endpoint.
//
// There are exactly TWO transports, and the local one is a REQUIREMENT rather
// than a mechanism (spec 0044): a caller asks for the local endpoint, and
// whether that is a Windows named pipe or a POSIX Unix domain socket is the
// leaf's business. That is what keeps config/defaults.json host-independent --
// one shipped entry per reader that works on every host.
package entities

import (
	"fmt"
	"strings"
)

// TransportKind is how a bridge is reached.
type TransportKind string

const (
	// TransportLocal is the endpoint that is not the network: a named pipe on
	// Windows, an AF_UNIX socket on POSIX. Addressed by a bare NAME
	// (`nvdaMcpBridge`) which each platform resolves its own way -- never the
	// `\\.\pipe\` prefix and never a socket path, unless one is written
	// deliberately as an override.
	TransportLocal TransportKind = "local"

	// TransportTCP is a loopback socket, addressed as `host:port`.
	TransportTCP TransportKind = "tcp"

	// transportPipeAlias is `local` as it was spelled until spec 0044, kept
	// because it appears in config files people already have, in shipped
	// defaults, in --reader help text and in the published contract. It PARSES
	// and is never printed: String() emits the canonical spelling, so
	// list_readers cannot answer in a vocabulary a --reader flag does not use.
	transportPipeAlias = "pipe"
)

// Endpoint is one place a bridge is known to listen. Immutable value.
type Endpoint struct {
	Kind    TransportKind
	Address string
}

// ParseEndpoint reads the `<kind>:<address>` spelling.
//
// Cut rather than Split on purpose: a TCP address contains its own colon, so
// only the FIRST one separates the kind from the address.
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

// String is the round-trip of ParseEndpoint, so what an agent is shown is
// exactly what may be written back into a --reader flag.
func (e Endpoint) String() string { return string(e.Kind) + ":" + e.Address }

// IsBareName reports whether an address is a NAME the platform resolves, rather
// than a path written out in full.
//
// It is the predicate two rules read. Dialing: a bare name is derived into this
// host's spelling, and a path is used verbatim. Liveness: only a bare name can
// be looked up in the host's namespace listing, so an endpoint addressed by
// path reports `unknown` instead of being wrongly called not-listening.
//
// Both separators are rejected on every platform rather than per-host, because
// the answer must not change with where the question is asked: the same config
// file is read on Windows and on macOS, and an endpoint that is a path on one
// of them is a path on both.
func IsBareName(address string) bool {
	return address != "" && !strings.ContainsAny(address, `/\`)
}
