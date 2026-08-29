# screenreader-mcp — the server

The program your MCP client launches. It speaks **MCP over stdio** to the client
and **JSON lines** to one screen-reader bridge over a **local endpoint** — a
named pipe on Windows, a Unix domain socket on macOS and Linux — or over
loopback TCP.

For what the tools do, see the [project README](../README.md). This document is
about running and configuring the server itself.

The server contains **no knowledge of any particular reader**. There is no NVDA
branch in it. Which reader answered, what version it is, and what it can do all
arrive in the `hello` handshake. A second reader ships as a bridge, not as a
change here.

## Build

```sh
uv run poe build-server
```

or directly:

```sh
go -C server build -o screenreader-mcp ./cmd/screenreader-mcp      # macOS, Linux
go -C server build -o screenreader-mcp.exe ./cmd/screenreader-mcp  # Windows
```

The `poe` task computes that suffix from the host, which is why it is a script
rather than a one-liner (`scripts/build_server.py`, spec 0042).

Statically linked (`CGO_ENABLED=0`, no cgo dependencies), so the artifact is one
file that runs with no runtime installed.

## Register it with a client

For Claude Code, user-wide:

```sh
# Windows
claude mcp add --scope user screenreader -- C:\path\to\screen-readers-mcp\server\screenreader-mcp.exe
# macOS / Linux
claude mcp add --scope user screenreader -- /path/to/screen-readers-mcp/server/screenreader-mcp
```

Any MCP client works the same way: it launches this executable and talks to it
over stdio. **No arguments are needed** — the binary ships knowing where our
bridges listen.

## The tool list is a constant; what the tools can DO is not

This is the thing to get right about the server, and it is the opposite of what
it used to be, so it is worth stating plainly.

**Every tool is advertised from the moment the process starts.** Twenty-six of
them, the same twenty-six before a session, during one and after it. Connecting
publishes nothing new and disconnecting withdraws nothing. There is no
`tools/list_changed` notification, because nothing changes.

What a session changes is what those tools can **do**. Four of them —
`list_readers`, `connect_reader`, `disconnect_reader` and `status` — work with
no reader at all. The rest are **gated**: each declares one capability, and it
refuses until a reader is connected *and* announced that capability. The refusal
says which of the two is missing, so "no session yet" and "this reader cannot do
that" are different answers rather than the same silence. Every gated tool's
description opens with the precondition, so an agent reading the list learns
what a tool needs before it calls it.

This replaced a design (spec 0013) in which a gated tool was simply **absent**
until its capability arrived, and the absence was the message. Spec 0022 retired
that, because a surface that depends on a notification is a surface that breaks
whenever a client misses one — and a client that had cached the ungated four
went on calling `connect_reader` successfully while every other tool answered
"No such tool available", with nothing in the failure pointing at the cause.

A constant list is correct across a session; what it cannot do is stay correct
across a **rebuild**. The names do not change, but a tool's **schema** can, and a
client holding yesterday's copy will not send a parameter it does not know about
— which fails typed, or does not fail at all. When you suspect that, read
`screenreader://tools`: a resource is served live and is never cached, so it
describes the build actually running.

The capture mode, the persona and the reader's log level are **fixed for the
session** at `connect_reader` and cannot be changed without reconnecting. That
is why there is deliberately no `--capture-mode`, `--persona` or
`--reader-log-level` flag: those are decisions belonging to the agent that knows
what a given session is for, not to whoever installed the binary.

## Resources

Alongside the tools, the server publishes five documents a client can read.
Three are static or server-owned and readable at any time; two need a live
session, because the reader is what fills them in.

| Resource | What it holds |
|---|---|
| `screenreader://guidance` | How to drive a screen reader: the personas and their full profiles, the loop, and what a successful call does and does not prove. Static, so it can be read **before** connecting. |
| `screenreader://tools` | Every tool in this build, with the capability that gates it and the shape of its input and result. Served live and never cached, which is what makes it the answer to "is my client's copy of the surface current?". |
| `screenreader://info` | The connected reader, its version, the capture mode, the persona, its capabilities, and whether a human is expected at that machine. Re-readable at any time, which is the point: everything here was true at connect and is still true, so an agent that has lost its context recovers it here instead of reconnecting. |
| `screenreader://reader-guidance` | The connected reader's own account of the stance you declared — which of *its* commands the stance may use, and which reach past focus and are out of bounds. Needs a session, and needs the reader to have announced the `guidance` capability; a bridge with no reader-specific instruction to give simply leaves it out. |
| `screenreader://session-record` | What this session has done, from the server's own traffic. |

## Flags

| Flag | Meaning |
|---|---|
| `--reader name=spec` | Repeatable, highest precedence. One endpoint for a reader, e.g. `nvda=local:nvdaMcpBridge` or `talkback=tcp:127.0.0.1:9010`. Repeating a name adds an endpoint to that reader, in order. |
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
        "local:nvdaMcpBridge",
        "tcp:127.0.0.1:8765"
      ]
    }
  ]
}
```

`local:<name>` is a **name**, not a path, and that is why one shipped default
works on every host: the name resolves to `\\.\pipe\<name>` on Windows and to
`$XDG_RUNTIME_DIR/screenreader-mcp/<name>.sock` — or
`~/.screenreader-mcp/<name>.sock` when `XDG_RUNTIME_DIR` is unset — on macOS and
Linux. A full path is accepted in its place if you want a different location.
`pipe:` is still read as a spelling of `local:`, so an older config file keeps
working; what the server prints back is always `local:`.

Two endpoints per reader is not redundancy. The NVDA bridge's own dialog lets
the user switch between the local endpoint and loopback TCP, so `connect_reader`
takes a **reader**, tries that reader's endpoints in the declared order, and
reports which one answered. You do not have to tell it which mode the user
picked.

A listening endpoint belonging to no configured reader is never reported and
cannot be connected to. The reader set is known before the process starts;
nothing is invented at runtime.

## When something does not work

**A tool answers with a precondition instead of doing anything.** That is the
correct state before connecting, and it is not a fault. The message says whether
what is missing is the session or the capability. Ask the agent to call
`connect_reader`; if a session is already live, that reader did not announce the
capability this tool needs, and no reconnect will change it.

**The client shows no tools at all.** Most clients load MCP servers at startup
and ask you to approve them — restart the client and approve this one. Check the
path you registered actually exists.

**The client shows only a handful of tools.** It is holding a list from an older
build, before every tool was advertised. Reconnect the server in your client.

**`list_readers` says nothing is listening.** The bridge is not started. In
NVDA: **NVDA+n → Tools → NVDA MCP Bridge…** and press **Start**. TCP endpoints
report `unknown` rather than `listening`, because liveness cannot be tested
without connecting.

**`connect_reader` reports a protocol mismatch.** The bridge and the server
speak different wire protocol versions. Their own version numbers are unrelated
and need not match; the protocol version must. Rebuild or reinstall whichever
half is older.

**A call fails with an unmarshalling error about JSON and Go structs.** The
client is sending a schema this build no longer has, or omitting a parameter
this build added — it is holding a cached copy of the surface from before your
last rebuild. Read `screenreader://tools` to see what the running build actually
takes, then reconnect the server in your client so it lists again. The quiet
version of this failure is worse and looks like nothing: a parameter the client
does not know about is simply never sent, and the server applies its default.

**Calls start failing after a quiet spell.** The bridge drops an idle session on
its own inactivity watchdog. `status` makes a real round trip to the reader when
a session is live, so it tells you what is true now rather than what was true
when you connected; `connect_reader` again to start fresh.

**You rebuilt the binary.** stdio MCP gives every client its own process, so a
running client keeps the old one until it respawns it. The tool *names* it
cached are still right — the list is a constant — so this alone is not something
to repair. Reconnect only if this build changed the surface: a tool added or
removed, **or a tool's parameters or result changed**.

## Developing the server

Layout, the test tiers, the wire binding generator, and the release process are
in [CONTRIBUTING.md](../CONTRIBUTING.md), [AGENTS.md](AGENTS.md) (this package's
manual) and the root [AGENTS.md](../AGENTS.md).
