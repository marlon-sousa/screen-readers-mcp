//go:build !windows

// screenreader-mcp adapters -- the local endpoint on POSIX: a Unix socket.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: LEAF adapter. Resolves the local endpoint to this host's spelling -- an
// AF_UNIX socket path -- and dials it. Its Windows sibling is
// local_transport_windows.go.
// BUILT BY: adapters/bridge/endpoint.go, the same call site as the real leaf.
// USED BY: adapters/bridge/json_lines_client.go, through the seam.
//
// It decides nothing: WHERE the socket is, whether the address was a name or an
// override path, and whether the path fits in a sockaddr_un all live in
// domain/entities/local_socket.go, which is pure and tested on every host. This
// file reads two environment values and calls it.
//
// Until spec 0044 this file was a refusal stub -- "named pipes are Windows-only"
// -- which is what a VoiceOver or TalkBack bridge would have hit. The position
// in the design was already right; only the answer was missing.
package bridge

import (
	"os"

	adapterports "github.com/marlon-sousa/screen-readers-mcp/server/adapters/ports"
	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// localDialer returns a Dialer for one local endpoint address.
//
// The path is resolved HERE, at build time, so a socket path that cannot work
// on this machine is reported when the configuration is read rather than when
// an agent asks to connect.
func localDialer(address string) (adapterports.Dialer, error) {
	path, err := entities.LocalSocketPath(address, localSocketDirs())
	if err != nil {
		return nil, err
	}
	return func() (adapterports.Transport, error) {
		return dialNet("unix", path, DefaultConnectTimeout)
	}, nil
}

// localSocketDirs reads the environment the derivation needs.
//
// A home directory that cannot be determined is passed on as empty rather than
// as an error: whether that matters depends on the address, and the entity is
// where that is decided.
func localSocketDirs() entities.LocalSocketDirs {
	home, err := os.UserHomeDir()
	if err != nil {
		home = ""
	}
	return entities.LocalSocketDirs{RuntimeDir: os.Getenv("XDG_RUNTIME_DIR"), Home: home}
}
