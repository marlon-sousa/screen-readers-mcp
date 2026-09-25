// screenreader-mcp adapters -- endpoint dialing decisions.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter that turns a domain Endpoint into a Dialer over the right leaf, refusing non-loopback hosts.
// BUILT BY: wiring.go, which hands DialerFor to the handshake as its dialer factory.
// USED BY: handshake.go, once per endpoint it tries.
package bridge

import (
	"fmt"
	"net"
	"time"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// DefaultConnectTimeout bounds a single dial attempt; short because a listening local bridge answers at once.
const DefaultConnectTimeout = 2 * time.Second

// DialerFor returns how to reach one endpoint, or explains why we will not.
func DialerFor(endpoint entities.Endpoint) (adapterports.Dialer, error) {
	switch endpoint.Kind {
	case entities.TransportLocal:
		return localDialer(endpoint.Address)

	case entities.TransportTCP:
		if err := requireLoopback(endpoint.Address); err != nil {
			return nil, err
		}
		address := endpoint.Address
		return func() (adapterports.Transport, error) {
			return dialNet("tcp", address, DefaultConnectTimeout)
		}, nil

	default:
		return nil, fmt.Errorf("endpoint %s: unknown transport %q", endpoint, endpoint.Kind)
	}
}

// requireLoopback refuses anything but the local machine, so a config file cannot make this server dial across a network.
func requireLoopback(address string) error {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return fmt.Errorf("tcp endpoint %q: want <host>:<port>: %w", address, err)
	}
	if port == "" {
		return fmt.Errorf("tcp endpoint %q: no port", address)
	}
	if host == "localhost" {
		return nil
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return fmt.Errorf("tcp endpoint %q: host must be a loopback address or localhost", address)
	}
	if !ip.IsLoopback() {
		return fmt.Errorf("tcp endpoint %q: only loopback endpoints may be dialed", address)
	}
	return nil
}
