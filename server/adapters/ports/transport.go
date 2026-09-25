// screenreader-mcp adapters -- the Transport seam.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter seam between adapters, invisible to the domain.
// IMPLEMENTED BY: adapters/bridge/net_transport.go, adapters/bridge/local_transport_windows.go, and fakes/transport.go.
// USED BY: adapters/bridge/json_lines_client.go.
package ports

import (
	"io"
	"time"
)

// Transport's Read polls: every leaf applies a short read deadline and reports an idle read as os.ErrDeadlineExceeded; io.EOF means the peer is gone.
type Transport interface {
	io.ReadWriteCloser
}

type Dialer func() (Transport, error)

// PollInterval is how long a leaf lets a Read sit idle before reporting os.ErrDeadlineExceeded.
const PollInterval = 50 * time.Millisecond
