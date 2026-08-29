// screenreader-mcp domain -- where a POSIX local endpoint lives.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: entity. The pure derivation from an endpoint's bare NAME to the socket
// path a POSIX bridge listens on, and the length limit that path must respect.
// BUILT BY: nobody -- these are functions over values.
// READ BY: adapters/bridge/local_transport_posix.go (to dial) and
// adapters/discovery/local_directory_posix.go (to list), each passing in the
// environment it read. Neither of them decides anything.
//
// WHY THIS IS DOMAIN AND NOT A LEAF, when endpoint.go says the `\\.\pipe\`
// prefix belongs in the leaf: the two are not symmetric. The Windows spelling
// is a constant prefix and decides nothing. This is a DERIVATION -- an
// environment variable with a fallback, a directory, a suffix, an override case
// and a limit -- and it is the RENDEZVOUS: the server and every POSIX bridge
// must compute the same path or never meet, which is why specs/wire/v1's §1
// states it. Contract is what an entity is for.
//
// It touches no OS: the caller passes the values it read. So it compiles and is
// tested on EVERY host, including the Windows leg of CI where the POSIX leaf is
// not compiled at all.
package entities

import (
	"fmt"
	"path/filepath"
	"strings"
)

const (
	// MaxLocalSocketPath is how many bytes of a Unix socket path the kernel
	// will look at, minus the terminating NUL.
	//
	// 104 on darwin, 108 on Linux; the smaller wins, so a path this server
	// accepts is dialable on every POSIX host we target. Measured, and the
	// reason it is checked at all: the kernel's own answer to a longer path is
	// `connect: invalid argument`, which names neither the limit, nor the path,
	// nor the fix.
	MaxLocalSocketPath = 103

	// localSocketDirName is the directory made under the runtime or home
	// directory. It is the product's name, not a reader's: several bridges may
	// listen on one machine.
	localSocketDirName = "screenreader-mcp"

	// localSocketSuffix is what makes a socket file recognisable in a directory
	// that is not otherwise ours to interpret -- it is what the listing leaf
	// matches on, and it is trimmed back off so both platforms answer the probe
	// in bare names.
	localSocketSuffix = ".sock"
)

// LocalSocketDirs is the environment the derivation needs, read by the caller.
//
// A DTO in the file of the rule that owns it: the two POSIX leaves fill it from
// os.Getenv and os.UserHomeDir, and nothing in here knows those exist.
type LocalSocketDirs struct {
	// RuntimeDir is $XDG_RUNTIME_DIR, or empty when it is unset. On the hosts
	// that set it (systemd Linux) it is already per-user, mode 0700 and cleaned
	// at logout -- exactly this, provided. macOS sets it for nobody, so there
	// the home directory is the answer in practice.
	RuntimeDir string

	// Home is the user's home directory, or empty when it cannot be determined.
	Home string
}

// LocalSocketDir is the directory a POSIX bridge's sockets live in.
//
// $XDG_RUNTIME_DIR/screenreader-mcp when that is set, else
// ~/.screenreader-mcp. The directory is mode 0700, which is where the
// filesystem-permission property comes from and is therefore contract -- but it
// is the LISTENER's job to create it that way. This server dials.
//
// $TMPDIR was rejected: on macOS it is a generated per-user path 49 bytes long,
// which spends half the budget below before the first meaningful character.
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

// LocalSocketPath is where the endpoint addressed `address` listens.
//
// A bare NAME is derived; an address that is already a path is used verbatim,
// which is the override spec 0044 keeps -- what would fork the shipped defaults
// per host is a path in the DEFAULTS, not a path being expressible.
//
// Either way the length is checked HERE, at endpoint construction, because that
// is where this server already reports a misconfigured endpoint: before
// anything is attempted, naming what the user actually wrote.
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

// LocalSocketName is the endpoint name a socket file stands for, and whether it
// is one of ours at all.
//
// The inverse of the derivation above, and the reason both platforms can answer
// the probe in the same vocabulary: Windows lists a namespace whose entries are
// already bare names, and POSIX lists a directory whose entries are those names
// plus a suffix.
func LocalSocketName(fileName string) (string, bool) {
	name, found := strings.CutSuffix(fileName, localSocketSuffix)
	if !found || name == "" {
		return "", false
	}
	return name, true
}
