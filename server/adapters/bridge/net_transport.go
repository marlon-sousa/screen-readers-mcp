// screenreader-mcp adapters -- netTransport: the Transport leaf over net.Conn.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: leaf adapter implementing the Transport seam over a net.Conn, for `tcp` and POSIX `unix`.
// BUILT BY: adapters/bridge/endpoint.go and local_transport_posix.go.
// USED BY: adapters/bridge/json_lines_client.go, through the seam.
package bridge

import (
	"net"
	"time"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
)

type netTransport struct {
	conn net.Conn
}

var _ adapterports.Transport = (*netTransport)(nil)

func dialNet(network, address string, connectTimeout time.Duration) (adapterports.Transport, error) {
	conn, err := net.DialTimeout(network, address, connectTimeout)
	if err != nil {
		return nil, err
	}
	return &netTransport{conn: conn}, nil
}

// Read applies the seam's poll deadline; net.Conn already reports it as os.ErrDeadlineExceeded.
func (t *netTransport) Read(p []byte) (int, error) {
	if err := t.conn.SetReadDeadline(time.Now().Add(adapterports.PollInterval)); err != nil {
		return 0, err
	}
	return t.conn.Read(p)
}

func (t *netTransport) Write(p []byte) (int, error) { return t.conn.Write(p) }

func (t *netTransport) Close() error { return t.conn.Close() }
