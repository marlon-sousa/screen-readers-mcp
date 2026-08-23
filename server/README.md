# screenreader-mcp — the server

The program your MCP client launches. It speaks **MCP over stdio** to the client
and **JSON lines** to one screen-reader bridge over a local endpoint — a Windows
named pipe or loopback TCP.

For what the tools do, see the [project README](../README.md). This document is
about running and configuring the server itself.

The server contains **no knowledge of any particular reader**. There is no NVDA
branch in it. Which reader answered, what version it is, and what it can do all
arrive in the `hello` handshake, and the tool list is built from that answer. A
second reader ships as a bridge, not as a change here.

## Build

```sh
uv run poe build-server
```

or directly:

```sh
go -C server build -o screenreader-mcp.exe ./cmd/screenreader-mcp
```

Statically linked (`CGO_ENABLED=0`, no cgo dependencies), so the artifact is one
file that runs with no runtime installed.

## Register it with a client

For Claude Code, user-wide:

```sh
claude mcp add --scope user screenreader -- C:\path\to\screen-readers-mcp\server\screenreader-mcp.exe
```

Any MCP client works the same way: it launches this executable and talks to it
over stdio. **No arguments are needed** — the binary ships knowing where our
bridges listen.

## The tools appear in two stages

This is the single most confusing thing about the server if you do not expect
it, so it is worth stating plainly.

Before a session, exactly **four** tools exist: `list_readers`,
`connect_reader`, `disconnect_reader` and `status`.

The server **never connects on its own**. When the agent calls `connect_reader`,
the bridge announces what it can serve, and the server publishes exactly the
tools those capabilities allow — speech tools if the reader captures speech, log
tools if it has a log, and so on. `disconnect_reader` withdraws them again.

So an agent is never offered a tool that would fail on the reader in front of
it, and the tool list changing under it is normal, not a fault.

The capture mode and the reader's log level are **fixed for the session** at
`connect_reader` and cannot be changed without reconnecting. That is why there
is deliberately no `--capture-mode` and no `--reader-log-level` flag: those are
decisions belonging to the agent that knows what a given session is for, not to
whoever installed the binary.

## Resources

Alongside the tools, the server publishes three documents a client can read:

| Resource | What it holds |
|---|---|
| `screenreader://guidance` | How to drive a screen reader: the loop, and what a successful call does and does not prove. Static, so it can be read **before** connecting. |
| `screenreader://info` | The connected reader, its version, the capture mode, its capabilities, and whether a human is expected at that machine. Re-readable at any time, which is the point: everything here was true at connect and is still true, so an agent that has lost its context recovers it here instead of reconnecting. |
| `screenreader://session-record` | What this session has done, from the server's own traffic. |

## Flags

| Flag | Meaning |
|---|---|
| `--reader name=spec` | Repeatable, highest precedence. One endpoint for a reader, e.g. `nvda=pipe:nvdaMcpBridge` or `talkback=tcp:127.0.0.1:9010`. Repeating a name adds an endpoint to that reader, in order. |
| `--config <path>` | A JSON file replacing or extending the embedded defaults, per reader. |
| `--print-default-config` | Print the embedded defaults and exit — redirect it to a file and edit it. |
| `--version` | Print the version and exit. |
| `--verbose` | Log debug detail to stderr. |

## The shipped endpoints

No arguments are needed because the binary ships knowing where our bridges
listen. This is `config/defaults.json`, embedded at build time and reproduced
here:

```json
{
  "readers": [
    {
      "name": "nvda",
      "endpoints": [
        "pipe:nvdaMcpBridge",
        "tcp:127.0.0.1:8765"
      ]
    }
  ]
}
```

Two endpoints per reader is not redundancy. The NVDA bridge's own dialog lets
the user switch between named pipe and loopback TCP, so `connect_reader` takes a
**reader**, tries that reader's endpoints in the declared order, and reports
which one answered. You do not have to tell it which mode the user picked.

A listening pipe belonging to no configured reader is never reported and cannot
be connected to. The reader set is known before the process starts; nothing is
invented at runtime.

## When something does not work

**The client shows only four tools.** That is the correct state before
connecting. Ask the agent to call `connect_reader`.

**The client shows no tools at all.** Most clients load MCP servers at startup
and ask you to approve them — restart the client and approve this one. Check the
path you registered actually exists.

**`list_readers` says nothing is listening.** The bridge is not started. In
NVDA: **NVDA+n → Tools → NVDA MCP Bridge…** and press **Start**. TCP endpoints
report `unknown` rather than `listening`, because liveness cannot be tested
without connecting.

**`connect_reader` reports a protocol mismatch.** The bridge and the server
speak different wire protocol versions. Their own version numbers are unrelated
and need not match; the protocol version must. Rebuild or reinstall whichever
half is older.

**Calls start failing after a quiet spell.** The bridge drops an idle session on
its own inactivity watchdog. `status` makes a real round trip to the reader when
a session is live, so it tells you what is true now rather than what was true
when you connected; `connect_reader` again to start fresh.

**You rebuilt the binary and the tools went stale.** stdio MCP gives every
client its own process, so a running client keeps the old one. Reconnect the
server in your client, or restart it.

## Developing the server

Layout, the test tiers, the wire binding generator, and the release process are
in [CONTRIBUTING.md](../CONTRIBUTING.md), [AGENTS.md](AGENTS.md) (this package's
manual) and the root [AGENTS.md](../AGENTS.md).
