# nvda-mcp

An MCP server that lets an AI agent **drive NVDA**: send keyboard gestures,
read back what NVDA speaks (and brailles), and introspect its state. The first
use case is **functional testing of NVDA add-ons** — replacing manual testing —
but the same primitives support a wider range of agent-driven NVDA workflows.

See [specs/0001-agent-driven-nvda-over-mcp.md](specs/0001-agent-driven-nvda-over-mcp.md)
for the full design, decisions and milestones. Design specs live in
[specs/](specs/), numbered RFC-style (`NNNN-title.md`); new features add a new
spec alongside.

## Architecture

The chain, top to bottom — each item talks only to the next:

1. An MCP client (Claude Code, …) speaks MCP over stdio to the server.
2. `screenreader-mcp` — a statically linked Go binary ([server/](server/)) on
   the official MCP Go SDK — speaks JSON lines to the bridge over a local
   endpoint: a named pipe by default, or loopback TCP
   ([spec 0010](specs/0010-named-pipe-transport.md), [0011](specs/0011-bridge-control-ui.md)).
   It never dials on its own — the agent asks it to connect, and the tools it
   then advertises are exactly the ones the connected reader announced it can
   serve ([spec 0013](specs/0013-mcp-server.md)).
3. `nvdaMcpBridge` — an NVDA add-on ([bridges/nvda/](bridges/nvda/)): a global
   plugin that captures speech through a `filter_speechSequence` filter, leaving
   the user's real synthesizer loaded
   ([spec 0008](specs/0008-transparent-silent-capture.md)) — drives NVDA itself.

The server survives NVDA restarts (restarting NVDA is itself a test operation),
and NVDA's embedded Python is a poor host for an MCP stdio server, so the two
halves are split and meet only at that local endpoint. They share no code: the
contract between them is [specs/wire/v1/](specs/wire/v1/) — a JSON Schema and a
prose document — and each side binds it in its own language.

What must match between them is the **wire protocol version**, not their version
numbers: `hello` compares `PROTOCOL_VERSION` and never the components' own
versions, so each releases on its own cadence.

## Repository layout

| Path | What |
|---|---|
| [shared/](shared/) | The **stdlib-only** Python binding of the wire protocol (`nvda-mcp-wire`), copied verbatim into the add-on and unit-tested once. |
| [specs/wire/v1/](specs/wire/v1/) | The published wire contract itself: JSON Schema plus prose. What the two halves actually share. |
| [server/](server/) | The MCP server (`screenreader-mcp`), in Go: MCP tool call → bridge command → result. |
| [bridges/nvda/](bridges/nvda/) | The NVDA add-on (`nvdaMcpBridge`), built with scons. Its build copies `shared/`'s protocol module in, so bridge and server can never drift. |
| [specs/](specs/) | Numbered design specs (RFC-style). |

## Development

Requires [uv](https://docs.astral.sh/uv/). No NVDA checkout is needed for any
of it: the bridge's domain is pure Python and its NVDA edge is exempt from the
type check (see [AGENTS.md](AGENTS.md)).

```sh
# Shared wire contract
uv run --directory shared pytest
uv run --directory shared pyright

# Server (Go; tests use a fake bridge)
go -C server test ./...
go -C server vet ./...

# Bridge add-on: sync the shared wire module in, then headless tests + type check
py -3.13 bridges/nvda/sync_shared.py
uv run --directory bridges/nvda pytest
uv run --directory bridges/nvda pyright   # or: cd bridges/nvda && scons   to build the .nvda-addon
```

Wire the server into Claude Code from source:

```sh
go -C server build -o screenreader-mcp.exe ./cmd/screenreader-mcp
claude mcp add --scope user screenreader -- C:\projects\screen-readers-mcp\server\screenreader-mcp.exe
```

No arguments needed: the binary ships knowing where our bridges listen. Ask the
agent to list readers, then to connect to one.

## Releasing

Each component is released by its own **prefixed tag**, so one tag selects one
component and one set of release assets:

| Tag | Releases |
|---|---|
| `nvda-bridge-v0.2.0` | `nvdaMcpBridge-0.2.0.nvda-addon` |
| `server-v0.3.1` | `screenreader-mcp-0.3.1-windows-amd64.exe` |

The two are independent on purpose: what has to match between the halves is the
**wire protocol version**, never their own version numbers, so each releases on
its own cadence and every release states the protocol it speaks.

The version is **never written in the tag alone**: it lives in the component's
own manifest — `bridges/nvda/buildVars.py` for the add-on,
`server/version/version.go` for the server — and the release workflow fails if
the tag disagrees. For the server it checks by **running the binary it just
built** (`--version`), which also proves the artifact starts before it is
published. Add-on release notes come from `addon_changelog` in that same file.
Tag only commits that are merged to `main`:

```sh
git tag -a nvda-bridge-v0.2.0 -m "Version 0.2.0"
git push origin nvda-bridge-v0.2.0
```

Each workflow publishes a **draft** release — review it, then publish; for the
add-on, then use the `submit-nvda-addon` skill for the store. Pull requests
touching `bridges/nvda/` or `shared/` get the packaged add-on built and linked in
a PR comment automatically.

Full rationale, including why the tag uses a dash rather than a slash and why
the merge gates are not path-filtered:
[spec 0012](specs/0012-packaging-and-release.md).

## Status

[ROADMAP.md](ROADMAP.md) is the status board and the single source of truth
for what is done, in review, and next — kept current by each implementing PR.
The larger arcs (sessions A–F) are described in
[the spec's Milestones](specs/0001-agent-driven-nvda-over-mcp.md).

## License

GPL v2. See [LICENSE](LICENSE) / COPYING.txt.
