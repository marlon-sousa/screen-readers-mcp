//go:build windows

// screenreader-mcp adapters -- the local endpoint on Windows: a named pipe.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: leaf adapter implementing the Transport seam over a Windows named pipe.
// BUILT BY: adapters/bridge/endpoint.go.
// USED BY: adapters/bridge/json_lines_client.go, through the seam.
//
// go-winio is required because a pipe opened with os.OpenFile is not overlapped and cannot carry a read deadline.
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

const pipePrefix = `\\.\pipe\`

type pipeTransport struct {
	conn net.Conn
}

var _ adapterports.Transport = (*pipeTransport)(nil)

// localDialer prefixes a bare name with the pipe namespace and uses a path verbatim.
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

// Read translates go-winio's ErrTimeout to os.ErrDeadlineExceeded; untranslated, the client reads an idle poll as a lost connection.
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
