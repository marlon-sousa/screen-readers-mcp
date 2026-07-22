# Spec 0010 — bridge: named-pipe transport leaf

Implementation contract for ROADMAP lane 1, entry 9.1a (split off entry 9.1,
agreed 2026-07-21). Authored on the entry's branch per process; the spec rides
in the implementing PR.

## Goal

Entry 9.1 originally bundled three things behind one PR: the control-UI
dialog, config persistence, and a named-pipe `Listener`/`Transport` leaf. That
coupling is unnecessary — the transport leaf has no UI dependency, and
splitting it out gives the GUI PR a smaller, already-proven seam to wire a
combo box to. This entry delivers **only** the leaf: a `NamedPipeListener`
and `NamedPipeTransport` implementing the exact same `Listener`/`Transport`
seams `TcpListener`/`SocketTransport` already implement (spec 0007, 9a), so
either can be handed to `BridgeServer` interchangeably. `plugin.py` keeps
using `TcpListener` unchanged — choosing between the two transports, and
persisting that choice, stays entry 9.1b's job.

Why a leaf, not a "leaf with no unit tests" the way `tcp_listener.py` /
`socket_transport.py` are: those two are literally decision-free (settimeout
already gives the exact contract). Windows named pipes are not — connecting,
polling, and cancelling require overlapped I/O — so correctness here is
proven by real usage: a headless integration test that runs an actual
Windows named pipe end to end, the same tier of proof 9a's
`test_socket_session_roundtrip.py` gave the TCP leaf. No NVDA import; it runs
in CI (`bridge` job, `windows-latest`) exactly like the socket scenario.

## Design

### Wire-level: `DEFAULT_PIPE_NAME`

`shared/nvda_mcp_wire/protocol.py` gains one constant, next to
`DEFAULT_PORT`:

```python
DEFAULT_PIPE_NAME: Final = r"\\.\pipe\nvdaMcpBridge"
```

Added to `__all__`, unit-tested in `shared/tests/unit/test_protocol.py`
alongside the `DEFAULT_PORT` assertion. `specs/wire/v1/protocol.md` §1
("Transport and framing") is amended to describe the named pipe as a second
listening option a Windows bridge may offer, alongside loopback TCP — both
still local-machine-only, matching the existing "never a routable interface"
decision. No schema change: the transport a bridge listens on is not part of
the JSON-lines wire shapes.

### Security posture — **Decided**

A named pipe is reachable by any local process by name, and by remote
machines via `\\host\pipe\name` unless rejected — the pipe analogue of "never
bind a routable interface." `NamedPipeListener` closes both holes:

- `PIPE_REJECT_REMOTE_CLIENTS` on every pipe instance (the remote-access
  door, closed the same way loopback-only binding closes it for TCP).
- A security descriptor restricting the pipe's DACL to the owner (the SDDL
  string `"D:(A;;GA;;;OW)"` — Generic All to `OWNER RIGHTS` only, no other
  ACE, so every other local account is denied by omission), built once via
  `ConvertStringSecurityDescriptorToSecurityDescriptorW` (`advapi32`) and
  reused for every instance the listener creates. Same reasoning as the
  loopback bind: the bridge can inject keystrokes and read config, so a
  same-machine other-user process must not be able to dial in.

### New files and classes

All under `bridgeAddon/`, ctypes + stdlib only (hard invariant 1 does not
apply here — that invariant is about `protocol.py` specifically — but the
addon as a whole stays free of third-party dependencies by convention, and
ctypes calling `kernel32`/`advapi32` keeps that convention).

| File | Role | Collaborators |
|---|---|---|
| `adapters/named_pipe_listener.py` | leaf adapter (implements the `Listener` seam) | **NamedPipeListener**: `open()` builds the owner-only security descriptor once and arms the first pipe instance (`CreateNamedPipeW` + overlapped `ConnectNamedPipe`); `accept()` waits on the pending instance's event up to the poll window (`WaitForSingleObject`), raises `TimeoutError` on `WAIT_TIMEOUT`, confirms via `GetOverlappedResult`, wraps the connected handle in a `NamedPipeTransport`, and **eagerly arms the next instance** before returning — the pipe analogue of TCP's `listen(1)` backlog letting one client queue while a session runs. `close()` is idempotent: cancels the pending instance (`CancelIoEx`), closes its handle/event, frees the security descriptor. `endpoint` returns the pipe name. |
| `adapters/named_pipe_transport.py` | leaf adapter (implements the `Transport` seam) | **NamedPipeTransport**: wraps one connected pipe `HANDLE` (either side — a listener's accepted instance or a client's dialed handle). `recv()`: overlapped `ReadFile`, waits on its own event up to the poll window, `TimeoutError` on timeout (cancelling the read via `CancelIoEx` first so it does not complete later into a stale buffer), `b""` on `ERROR_BROKEN_PIPE`/`ERROR_PIPE_NOT_CONNECTED`/`ERROR_NO_DATA`/`ERROR_OPERATION_ABORTED` (the pipe analogue of `SocketTransport`'s "peer gone → EOF"). `sendall()`: overlapped `WriteFile`, waits indefinitely (`GetOverlappedResult(..., bWait=True)`) — same blocking-until-sent contract as a real socket's `sendall`. `close()` is idempotent: cancels any pending I/O, disconnects (server side only; a no-op failure on the client side, ignored), closes the handle and both events. Also exports **`dial(pipe_name, timeout) -> NamedPipeTransport`**, the client-side counterpart (`CreateFileW` with `FILE_FLAG_OVERLAPPED`, retrying on `ERROR_PIPE_BUSY` via `WaitNamedPipeW` until `timeout`) — used by the integration test's client end and by anything that later dials the bridge over a pipe, exactly as `socket.create_connection` plays that role for the TCP scenario today. |
| `tests/integration/test_named_pipe_session_roundtrip.py` | headless integration scenario | The real stack over a real named pipe, on a **unique per-test pipe name** (`\\.\pipe\nvdaMcpBridge-test-<uuid>`, the pipe analogue of TCP's ephemeral port 0) — otherwise a line-for-line mirror of `test_socket_session_roundtrip.py`: hello → echo → pressGesture/getSpeech → bye, sequential sessions on one server, an idle server stopping promptly, and an abruptly-closed client not taking the server down. `NamedPipeListener` + `NamedPipeTransport.dial` stand in for `TcpListener` + `socket.create_connection`; everything else (`BridgeServer`, `FakeAdapterFactory`, `JsonLinesChannel`) is identical, proving the seam is truly interchangeable. |

Not touched: `plugin.py`, `wiring.py`, `bridge_server.py`, the GUI (none
exists yet) — entry 9.1b's job is picking one of the two listeners (and,
later, persisting the choice).

## Out of scope

- The control dialog, the connection-mode combo, config persistence,
  auto-start — entry 9.1b, now that this entry has already built and proven
  both `Listener` seams it needs to choose between.
- Switching `plugin.py`'s default listener — stays `TcpListener` until 9.1b.
- The MCP server dialling a pipe (`BridgeClient`, lane 2) — noted on the
  board as a small follow-up once a `BridgeClient` exists at all (entry 10,
  not yet started).
- Any wire schema change.

## Acceptance criteria

1. `DEFAULT_PIPE_NAME` added to `shared/nvda_mcp_wire/protocol.py` and
   asserted in `shared/tests/unit/test_protocol.py`; `specs/wire/v1/protocol.md`
   §1 amended; the schema drift gate stays green (no schema change).
2. `NamedPipeListener`/`NamedPipeTransport` implement the `Listener`/
   `Transport` seams exactly (`adapters/ports/listener.py`,
   `adapters/ports/transport.py`) — pyright strict clean, no new entries on
   the NVDA-edge ignore list (nothing here imports NVDA; ctypes is stdlib).
3. `test_named_pipe_session_roundtrip.py` green on CI (`windows-latest`,
   real named pipe, no NVDA): the same session lifecycle TCP's 9a scenario
   proves — sequential sessions on one server, idle-stop is prompt, an
   abruptly-closed client does not take the server down — plus a poll-timeout
   assertion (`accept()`/`recv()` raise `TimeoutError` when idle, matching
   the TCP leaf's documented contract) that the TCP scenario does not need
   because sockets already guarantee it.
4. No behavior change for an installed addon: `plugin.py` is untouched, so
   this PR changes nothing about what a running NVDA does.
5. Live-NVDA proof of the pipe leaf answering real `hello`/`pressGesture`/
   `getSpeech`/`bye` traffic is **not** part of this PR's automated or manual
   checklist — it needs `plugin.py` to actually listen on the pipe, which is
   9.1b's change. If a live check is done ad hoc against this branch before
   9.1b lands, it is exploratory verification, not a merge gate.

## Definition of done

Merged with green CI (`shared`, `bridge` — `server` untouched); ROADMAP entry
9.1 split into **9.1a** (this entry, flipped to Done by this PR) and **9.1b**
(the GUI + config + default-switch, unblocked by this PR, Spec: none yet).
