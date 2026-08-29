// screenreader-mcp adapters -- netTransport: the Transport leaf over net.Conn.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: LEAF adapter. IMPLEMENTS the Transport seam (adapters/ports) over a real
// stream connection, and does nothing else.
// BUILT BY: adapters/bridge/endpoint.go, which is where the decisions live --
// which host is acceptable, how the address is spelled -- and by
// local_transport_posix.go, which resolves a socket path and then calls this.
// USED BY: adapters/bridge/json_lines_client.go, through the seam.
//
// One wrapper for two networks, because the OS gives the same thing both times:
// `tcp` for loopback, `unix` for a POSIX local endpoint. Windows named pipes
// are the exception and have their own leaf, because go-winio reports a
// deadline its own way.
//
// No test file beside it on purpose (AGENTS.md): there is nothing here that
// net.Conn does not already guarantee. The one line that looks like a decision,
// the read deadline, is the seam's own PollInterval constant applied verbatim.
package bridge

import (
	"net"
	"time"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
)

// netTransport is one connected stream.
type netTransport struct {
	conn net.Conn
}

var _ adapterports.Transport = (*netTransport)(nil)

// dialNet opens a connection to an already-validated address.
func dialNet(network, address string, connectTimeout time.Duration) (adapterports.Transport, error) {
	conn, err := net.DialTimeout(network, address, connectTimeout)
	if err != nil {
		return nil, err
	}
	return &netTransport{conn: conn}, nil
}

// Read applies the seam's poll deadline, so an idle read surfaces as
// os.ErrDeadlineExceeded rather than blocking forever. net.Conn already reports
// a passed deadline that way, so the contract falls out for free.
func (t *netTransport) Read(p []byte) (int, error) {
	if err := t.conn.SetReadDeadline(time.Now().Add(adapterports.PollInterval)); err != nil {
		return 0, err
	}
	return t.conn.Read(p)
}

func (t *netTransport) Write(p []byte) (int, error) { return t.conn.Write(p) }

func (t *netTransport) Close() error { return t.conn.Close() }
