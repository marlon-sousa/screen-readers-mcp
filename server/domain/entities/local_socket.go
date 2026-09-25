// screenreader-mcp domain -- where a POSIX local endpoint lives.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity, the pure derivation from an endpoint's bare name to the POSIX socket path and its length limit.
// BUILT BY: nobody; these are functions over values.
// READ BY: adapters/bridge/local_transport_posix.go and adapters/discovery/local_directory_posix.go.
//
// The server and every POSIX bridge must derive the same path, or they never meet.
package entities

import (
	"fmt"
	"path/filepath"
	"strings"
)

const (
	// MaxLocalSocketPath is the smaller of darwin's 104 and Linux's 108 sun_path
	// bytes, minus the NUL; past it the kernel answers only `connect: invalid argument`.
	MaxLocalSocketPath = 103

	localSocketDirName = "screenreader-mcp"

	localSocketSuffix = ".sock"
)

type LocalSocketDirs struct {
	RuntimeDir string

	Home string
}

// LocalSocketDir does not create the directory; the listener must create it mode 0700.
func LocalSocketDir(dirs LocalSocketDirs) (string, error) {
	if dirs.RuntimeDir != "" {
		return filepath.Join(dirs.RuntimeDir, localSocketDirName), nil
	}
	if dirs.Home != "" {
		return filepath.Join(dirs.Home, "."+localSocketDirName), nil
	}
	return "", fmt.Errorf(
		"local endpoint: neither XDG_RUNTIME_DIR nor a home directory is known, so there is nowhere to look",
	)
}

// LocalSocketPath uses an address that is already a path verbatim, and length-checks either kind.
func LocalSocketPath(address string, dirs LocalSocketDirs) (string, error) {
	path := address
	if IsBareName(address) {
		dir, err := LocalSocketDir(dirs)
		if err != nil {
			return "", err
		}
		path = filepath.Join(dir, address+localSocketSuffix)
	}
	if len(path) > MaxLocalSocketPath {
		return "", fmt.Errorf(
			"local endpoint %q: its socket path %s is %d bytes, over the %d a unix socket allows",
			address, path, len(path), MaxLocalSocketPath,
		)
	}
	return path, nil
}

func LocalSocketName(fileName string) (string, bool) {
	name, found := strings.CutSuffix(fileName, localSocketSuffix)
	if !found || name == "" {
		return "", false
	}
	return name, true
}
