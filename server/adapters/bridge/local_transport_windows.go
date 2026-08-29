//go:build windows

// screenreader-mcp adapters -- the local endpoint on Windows: a named pipe.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: LEAF adapter. Resolves the local endpoint to this host's spelling -- a
// named pipe -- and IMPLEMENTS the Transport seam over it. Its POSIX sibling is
// local_transport_posix.go.
// BUILT BY: adapters/bridge/endpoint.go, which owns every decision about which
// endpoint is dialed at all.
// USED BY: adapters/bridge/json_lines_client.go, through the seam.
//
// Windows keeps named pipes even though Windows 10 1803+ has AF_UNIX: the
// shipped NVDA add-on listens on a pipe, and moving it would break every
// installed copy for no gain (spec 0044).
//
// go-winio rather than os.OpenFile: a pipe handle opened the plain way is not
// overlapped, so it cannot carry a read deadline, and the seam's poll contract
// is exactly a read deadline. go-winio is pure Go, so CGO_ENABLED=0 and the
// single statically linked artifact survive.
//
// No test file beside it, and nothing here to test: the decisions are one layer
// up, and what remains is the OS.
package bridge

import (
	"errors"
	"net"
	"os"
	"time"

	winio "github.com/Microsoft/go-winio"
	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// pipePrefix is the OS spelling of the pipe namespace. It lives in the leaf
// because it is a constant prefix and decides nothing: a domain Endpoint
// carries the bare name a user configured (`nvdaMcpBridge`), and this is the
// only place that knows what Windows requires in front of it. (The POSIX
// sibling's location is a derivation rather than a prefix, which is why THAT
// one is in the domain -- see local_socket.go.)
const pipePrefix = `\\.\pipe\`

// pipeTransport is one connected named pipe.
type pipeTransport struct {
	conn net.Conn
}

var _ adapterports.Transport = (*pipeTransport)(nil)

// localDialer returns a Dialer for one local endpoint address.
//
// A bare name is prefixed with the namespace; an address that is already a path
// is used verbatim, which is the override spec 0044 keeps on both platforms.
func localDialer(address string) (adapterports.Dialer, error) {
	path := address
	if entities.IsBareName(address) {
		path = pipePrefix + address
	}
	return func() (adapterports.Transport, error) {
		timeout := DefaultConnectTimeout
		conn, err := winio.DialPipe(path, &timeout)
		if err != nil {
			return nil, err
		}
		return &pipeTransport{conn: conn}, nil
	}, nil
}

// Read applies the seam's poll deadline, so an idle read surfaces as
// os.ErrDeadlineExceeded rather than blocking forever.
//
// The translation is not a decision, it is this leaf honouring the seam: go-winio
// reports an expired deadline as its OWN winio.ErrTimeout, while the seam (and
// every other leaf, which gets it from net) spells that os.ErrDeadlineExceeded.
// Untranslated, the client reads "idle" as "the connection died", so every
// command that takes longer than one poll interval -- any wait, any gesture that
// makes the reader speak -- would fail over the pipe, which is the transport the
// NVDA bridge ships listening on. It is the analogue of the bridge's own
// SocketTransport reporting an abrupt reset as EOF.
func (t *pipeTransport) Read(p []byte) (int, error) {
	if err := t.conn.SetReadDeadline(time.Now().Add(adapterports.PollInterval)); err != nil {
		return 0, err
	}
	n, err := t.conn.Read(p)
	if errors.Is(err, winio.ErrTimeout) {
		return n, os.ErrDeadlineExceeded
	}
	return n, err
}

func (t *pipeTransport) Write(p []byte) (int, error) { return t.conn.Write(p) }

func (t *pipeTransport) Close() error { return t.conn.Close() }
