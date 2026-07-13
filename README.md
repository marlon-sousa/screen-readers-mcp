# nvda-mcp

An MCP server that lets an AI agent **functionally test NVDA add-ons**: drive
NVDA with keyboard gestures, read back what NVDA speaks (and brailles), and
introspect focus state — replacing manual functional testing.

See [PLAN.md](PLAN.md) for the full design, decisions and milestones.

## Architecture

```
MCP client (Claude Code, ...)
   │  MCP over stdio
   ▼
nvda-mcp server            — Python package (server/), official mcp SDK / FastMCP
   │  JSON lines over TCP, 127.0.0.1 only
   ▼
nvdaMcpBridge              — NVDA add-on (bridge/): global plugin + spy synth
```

The server survives NVDA restarts (restarting NVDA is itself a test operation),
and NVDA's embedded Python is a poor host for an asyncio MCP stdio server, so
the two halves are split and meet only at the loopback socket.

## Repository layout

| Path | What |
|---|---|
| [shared/](shared/) | Canonical **stdlib-only** JSON-lines wire protocol (`nvda-mcp-wire`), shared verbatim by both halves and unit-tested once. |
| [server/](server/) | The MCP server (`nvda-mcp`): MCP tool call → bridge command → result. |
| [bridge/](bridge/) | The NVDA add-on (`nvdaMcpBridge`), built with scons. Its build copies `shared/`'s protocol module in, so bridge and server can never drift. |

## Development

Requires [uv](https://docs.astral.sh/uv/) and (for the bridge type-check) a
sibling NVDA 2026.1 source checkout at `../nvda`.

```sh
# Shared wire contract (no NVDA needed)
uv run --directory shared pytest
uv run --directory shared pyright

# Server (no NVDA needed; tests use a fake bridge)
uv run --directory server pytest
uv run --directory server pyright

# Bridge (type-checks against the NVDA source checkout)
python bridge/sync_shared.py
uv run --directory bridge pyright   # or: cd bridge && scons   to build the .nvda-addon
```

Wire the server into Claude Code from source:

```sh
claude mcp add --scope user nvda -- uv run --directory C:\projects\nvda-mcp\server nvda-mcp
```

## Status

Implemented per milestone (see [PLAN.md](PLAN.md)):

- [x] **Session A — foundation**: repo layout, shared wire protocol + tests, tooling/CI.
- [ ] Session B — bridge core logic (buffer, session state machine, framing, transcript).
- [ ] Session C — bridge ↔ NVDA adapters, spy synth, live validation (milestones 1–3).
- [ ] Session D — MCP server + v1 tools (milestone 4).
- [ ] Session E — introspection + real-world validation (milestones 5–6).
- [ ] Session F — packaging & release (milestone 7).

## License

GPL v2. See [LICENSE](LICENSE) / COPYING.txt. The bridge's spy synth driver is
adapted from NVDA's own GPL-2 system-test suite.
