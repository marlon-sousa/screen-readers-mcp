# server/ — the MCP server

The manual for this package. The repo-wide manual is the root
[`AGENTS.md`](../AGENTS.md) — the four-role vocabulary (port / controller / entity
/ adapter), the hard invariants, the workflow and the task list all live there
and are not repeated here. This file is the Go half's rendering of those rules.

`server/` is `screenreader-mcp`: MCP tool → bridge command → result, over stdio,
on the official Go SDK, built as a static binary (`CGO_ENABLED=0`). Its wire
binding is generated from [`specs/wire/v1/schema.json`](../specs/wire/v1/schema.json)
into `server/adapters/wire/` and is private to the server.

## Internal architecture — the Go half

Server (session D, complete; [spec 0013](../specs/0013-mcp-server.md)): same four
roles, no `internal/` segment, so the trees line up
(`nvdaMcpBridge/domain/ports/clock.py` ↔ `server/domain/ports/clock.go`). As
built:

- `domain/ports/` — one interface per file. Seven capability-group ports
  (speech, braille, gestures, focus, state, config, plus `session_dialer.go`)
  rather than one fat `BridgeClient`, so a reader without braille is a *missing
  collaborator* rather than a runtime check: `Dial` returns a `ReaderConnection`
  whose capability ports are **nil when unannounced**. Plus `endpoint_source.go`,
  `endpoint_probe.go`, `tool_publisher.go` (how the domain publishes and retracts
  tools without meeting the SDK), `clock.go` and `log.go`.
- `domain/entities/` — `reader_session.go`, `capability.go`,
  `connection_state.go`, `endpoint.go`, `configured_reader.go`,
  `reader_listing.go`, and `tool_catalog.go`, which **is** the capability gate: a
  pure table of capability in, tool names out, containing no reader's name.
- `domain/controllers/connection.go` — the agent-driven session lifecycle (list,
  connect, disconnect, loss detection, the heartbeat). It holds the only state in
  the process, and it is an ordinary value owned by wiring.
- `domain/controllers/tools/` — one controller per MCP tool (fifteen), mirroring
  the bridge's one-handler-per-command rule, plus `registry.go` (the explicit
  map, which also yields the catalog), `dispatcher.go` (one tool call as a use
  case) and `tool_context.go` (the per-call parameter object, the analogue of the
  bridge's `SessionContext`; its capability accessors are the only way to reach a
  port, so a tool cannot forget to check). `Execute` takes **erased params** and
  each tool declares its own JSON schema, which is what lets the MCP adapter have
  zero per-tool code.
- `adapters/` — `mcp/` (the go-sdk stdio server, the tool binding, the
  `screenreader://info` resource, and the middleware backstop that answers a call
  to a *retracted* tool with a capability error rather than "unknown tool"),
  `bridge/` (the JSON-lines client holding every decision, the handshake, and the
  TCP and named-pipe transport leaves), `discovery/` (the pipe scan), `wire/`
  (generated from the published schema, imported only by `bridge/`), and the
  clock and stderr-log leaves.
- `tests/` — `architecture/` (untagged: the import boundaries, plus the rule that
  the conformance tier may never substitute the fake bridge), `integration/`
  (`//go:build integration`: the whole server against a Go fake bridge over real
  transports) and `conformance/` (`//go:build conformance`, Windows CI: the built
  binary over stdio against the **real Python bridge**).

Go mechanics for the same rules: ports are interfaces with a
`var _ ports.X = (*Impl)(nil)` assertion in each adapter; the domain never
imports `adapters/wire` or the MCP SDK; and there is **no package-level mutable
state anywhere in `server/`**, which is what keeps concurrent sessions a later
map-plus-lookup rather than an unpicking of globals.

## Testing — the Go rules

The root manual's testing rules hold: one test module per source module, doubles
are hand-written stateful fakes rather than mocks, time is injected and never
patched, and a source file with no test file beside it is a deliberate
statement. What differs is where a test lives.

**In Go the mirror is the language's own convention**, so the server renders the
same rule differently ([spec 0013](../specs/0013-mcp-server.md)): `session.go` ↔
`session_test.go` **beside it**, one test file per source file. A parallel tree
is not merely awkward there but counterproductive — a Go test sees unexported
identifiers only from inside its package's directory, so the layout would force
every collaborator public to satisfy a directory. Two Go-only rules come with
it: tests are `package foo_test` by default (a test that needs internals is
first evidence the decomposition is wrong; white-box is allowed where an
unexported helper deserves direct coverage, and the header says why), and the
scenario tiers live in `server/tests/<usecase>/` behind build tags
(`//go:build integration`, `//go:build conformance`) so `go test ./...` stays
fast and the Windows-only conformance run opts in explicitly.

## Rebuilding

`.mcp.json` spawns `server/screenreader-mcp.exe`, so an agent that edits Go code
and then drives the MCP tools is testing the OLD server against the NEW bridge.
`uv run poe dev` rebuilds a stale binary as its first step; a bare `poe doctor`
or `poe bridge` fails on one instead, and `uv run poe redeploy` is the fix. The
full reasoning, and the case that still needs the maintainer to reconnect the
MCP client, is in the root manual's "Notes for agents specifically" and in
[`docs/dev-commands.md`](../docs/dev-commands.md).
