// screenreader-mcp -- the version constant.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: constant. The SINGLE source of this component's version.
// READ BY: cmd/screenreader-mcp's --version flag, and by the release workflow,
// which builds the binary and runs --version to check it against the pushed
// `server-v*` tag (spec 0012).
//
// Go has no buildVars.py, so this const is the equivalent: spec 0012 requires
// the version to live in the component's own manifest and NOWHERE else, so that
// a tag and an artifact can never disagree. Checking it by running the binary
// also proves the artifact starts before it is published.
//
// The server's version is deliberately unrelated to the add-on's: what has to
// match between the two halves is the WIRE protocol version, never their own.
package version

// Version is this server's version, without a leading `v`. The release tag is
// `server-v<Version>`.
const Version = "0.1.0"
