// The MCP server (`screenreader-mcp`). One module, no workspace: spec 0013
// decided that each implementation owns its own binding of the wire contract,
// so nothing here is meant to be imported from outside this directory.
//
// The module path may be renamed if the repo is (spec 0013, "The module path
// may need a rename later"): `go mod edit -module` plus a mechanical import
// rewrite, since nothing imports us externally.
module github.com/marlon-sousa/screen-readers-mcp/server

go 1.24

require github.com/Microsoft/go-winio v0.6.2

require (
	github.com/google/go-cmp v0.7.0 // indirect
	golang.org/x/sys v0.10.0 // indirect
)
