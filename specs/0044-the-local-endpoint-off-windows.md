# 0044 — the local endpoint, and what it means off Windows

Status: **proposed 2026-08-29.** Board entry **11.35**, lane 2 (server). Opened
on 2026-08-29 by lane 3: entry 13.4 is where a VoiceOver bridge starts
listening, and on macOS there is nothing for it to listen on that this server
knows how to dial.

The one-line summary, which is also the organising principle:

> **[Spec 0010](0010-named-pipe-transport.md) asked for a local endpoint that is
> not the network, and got a named pipe, because it was standing on Windows. The
> requirement was the *property*, not the mechanism. So: keep exactly two
> transports, and let the leaf decide what "local" means on this host.**

Nothing about the wire shape changes, `PROTOCOL_VERSION` does not move, and the
NVDA add-on's behaviour is untouched. What changes is the vocabulary the server
and the published contract use for "the endpoint that is not TCP", and what that
vocabulary resolves to on a machine that has no named pipes.

---

## Part 1 — the evidence

### What the shipped defaults do on macOS today, measured

macOS 15.0, x86_64, Go 1.25.14, `main` at e48e690. The embedded
`server/config/defaults.json` resolved through `config.Load`, each endpoint then
handed to `bridge.DialerFor`:

```
nvda -> pipe:nvdaMcpBridge : pipe endpoint "nvdaMcpBridge": named pipes are Windows-only; configure a loopback tcp endpoint instead
nvda -> tcp:127.0.0.1:8765 : <nil>
```

So the shipped default set is, on this host, one dead entry and one live one.
The message is accurate and it is also the end of the road: there is no
`--reader` value a macOS user can write that reaches a local endpoint, because
`local` is not a thing the server has a word for.

The liveness half is the same shape. `EmptyPipeDirectory.Names()` returns `nil`
on every non-Windows host, so `PipeProbe.Live` finds nothing, so `BuildListing`
reports **every** endpoint as `unknown`. On the host lane 3 runs on,
`list_readers`'s liveness column is a constant.

### Spec 0010 asked for a property and then named a mechanism

`specs/wire/v1/protocol.md` §1 today:

> a **Windows named pipe** (spec 0010), rejecting remote clients
> (`PIPE_REJECT_REMOTE_CLIENTS`) and restricted by DACL to the owning user — the
> pipe analogue of the loopback-only bind.

Read that clause backwards and the requirement is visible: *an endpoint reachable
only from this machine, and only by this user, that is not a routable interface*.
"Named pipe" is how Windows spells that. It is not the requirement.

### The POSIX spelling of the same property is a file

A Unix domain socket is a filesystem path with filesystem permissions. A socket
in a directory the owner alone can enter is unreachable by any other user and
unreachable from the network by construction — the same two guarantees, obtained
from the same kernel that enforces the rest of the filesystem. There is no
handshake to get wrong and no DACL to build.

(`mkfifo` is not a candidate: a FIFO has no accept loop, no per-connection
channel and no peer credentials. It is a pipe in the shell sense, not in the
Windows sense.)

### The socket path is short, and the obvious directory is expensive

Measured on this machine:

| Fact | Value |
|---|---|
| `sun_path` capacity (`unsafe.Sizeof(syscall.RawSockaddrUnix{}.Path)`), darwin | **104 bytes** |
| `sun_path` capacity, Linux | 108 bytes |
| `$TMPDIR` | `/var/folders/vl/_f_73h_51fl2yplpylv9_1br0000gp/T/` — **49 bytes** |
| `$XDG_RUNTIME_DIR` | **unset** |
| `~` | `/Users/marlon` — 13 bytes |
| `~/.screenreader-mcp/nvdaMcpBridge.sock` | **50 bytes** |

Two things follow. First, a `$TMPDIR`-based path spends nearly half the budget
before the first meaningful character, on a machine whose per-user folder name is
generated: it is not safe on a host nobody has seen. Second, the home-relative
path costs 50 of 104 here, which leaves room but is not unlimited — a long user
name still exists somewhere.

And an overlong path fails uselessly. Measured, a 120-byte path:

```
listen unix /tmp/aaa….sock: bind: invalid argument
dial   unix /tmp/aaa….sock: connect: invalid argument
```

`invalid argument` names nothing: not the limit, not the path, not the fix.

### The code is already shaped for this

`DialerFor` switches on the endpoint's kind and hands a name to `pipeDialer`,
which has two implementations selected by build tag. The non-Windows one is a
refusal stub that fails at *construction* rather than at dial time — sitting in
exactly the position the real POSIX leaf belongs, and already carrying the
"report a bad endpoint when the configuration is read" behaviour this spec
wants. The same is true one layer over in discovery: `PipeDirectory` is a seam
with a Windows leaf and an empty non-Windows one.

This is not an accident. `pipe_transport_other.go`'s own header says it:

> This is not merely CI convenience (spec 0013): a VoiceOver or TalkBack bridge
> implies a non-Windows server host […] so a server that cannot compile without
> pipes would be a server that cannot be ported.

## Part 2 — the shape

### Decision 1: two transports, and the local one resolves per platform — **agreed in conversation, 2026-08-29**

A caller asks for **the local endpoint** or for **loopback TCP**. Which local
mechanism that means is the leaf's business: a named pipe on Windows, an
`AF_UNIX` socket on POSIX.

Not a third kind. A `unix:` alongside `pipe:` and `tcp:` would put the host's
answer into every config file, every default, and every piece of documentation
that names an endpoint — and would make `server/config/defaults.json`, which is
*embedded in the binary*, host-specific. The whole point of the current shape is
that one shipped default works everywhere.

### Decision 2: the kind is spelled `local`, and `pipe` is a parsed alias that is never printed — **agreed in conversation, 2026-08-29**

`TransportPipe` becomes `TransportLocal`, spelled `local`. `pipe:` continues to
parse, forever, and normalises to `local` on the way in: it appears in shipped
defaults, in `--reader` help text, in `specs/wire/v1/protocol.md`, in this
repo's own tests, and in whatever config files people already have.

It is normalised rather than preserved because `Endpoint.String()` is documented
as the round-trip — "what an agent is shown is exactly what may be written back
into a `--reader` flag". Two spellings for one thing would become two spellings
in the answer, and an agent comparing `list_readers` output against a config file
would see a difference that means nothing.

`ipc` was the runner-up. `socket` was rejected because TCP is a socket too.

### Decision 3: the address stays a bare NAME; an absolute path is an override — **agreed in conversation, 2026-08-29**

`local:nvdaMcpBridge` is what we ship, on every host. The bare name is the
load-bearing part: it is what keeps the embedded defaults host-independent.

An address that is already a path is used verbatim — `local:/tmp/my.sock` on
POSIX, `local:\\.\pipe\myBridge` on Windows. That loses nothing, because what
would fork the shipped config per host is a path in the **defaults**, not a path
being *expressible*. The derived location is pre-configured; someone who wants a
different one can say so.

The distinction is syntactic and platform-shaped, so it lives with the
resolution: on POSIX an address beginning with `/` is a path; on Windows one
beginning with `\\` is.

### Decision 4: where the socket lives — **agreed in conversation, 2026-08-29**

```
$XDG_RUNTIME_DIR/screenreader-mcp/<name>.sock     when XDG_RUNTIME_DIR is set
~/.screenreader-mcp/<name>.sock                   otherwise
```

Directory mode **0700** — which is where the filesystem-permission property
actually comes from, and therefore the part of this that is contract rather than
convenience. `$TMPDIR` was rejected on the measurement above.

`XDG_RUNTIME_DIR` first because on the hosts that set it (systemd Linux) it is a
per-user, mode-0700, cleaned-at-logout directory: exactly this, already
provided. macOS sets it for nobody, so in practice the macOS answer is the home
path, and the ordering costs macOS nothing.

**The server never creates that directory.** It dials. Creating it, with the
right mode, and unlinking a stale file before binding, are the *listener's*
obligations — 13.4 for VoiceOver — and they are stated in `protocol.md` because
they are the half of the rendezvous the dialing side cannot enforce.

### Decision 5: the length is checked at endpoint construction — **agreed in conversation, 2026-08-29**

Against **103 usable bytes** (104 including the terminating NUL — the darwin
figure, so a path this server accepts is dialable on every POSIX host we
target). The check applies to a derived path and to an absolute override alike.

At construction, because that is where this server already reports a
misconfigured endpoint: before anything is attempted, naming the endpoint the
user actually wrote. The alternative is the measured `connect: invalid argument`
above, at the moment an agent asks to connect, naming nothing.

### Decision 6: liveness generalises to a directory of sockets, and only bare names are judged — **agreed in conversation, 2026-08-29**

The `PipeDirectory` seam becomes `LocalDirectory`, with the same one method.
Windows lists `\\.\pipe\`; POSIX lists the socket directory, keeps the entries
ending in `.sock` and trims the suffix, so both leaves answer in the same
vocabulary the probe already uses: **bare endpoint names**. The probe is
unchanged in every decision it holds — walk the candidates, ask the listing,
never the reverse.

macOS gains something real by it: `list_readers` starts answering *listening* /
*not listening* on the host lane 3 is built on, instead of `unknown` for
everything.

One rule is added, and it is the honest half. An endpoint whose address is **not
a bare name** — an absolute-path override, on either platform — is not judged at
all: the listing cannot speak for it, so it reports `unknown`, exactly as a TCP
endpoint does. Without that rule an override would report *not listening* while
its bridge was running, which is worse than saying nothing.

### Decision 7: the POSIX resolution rule lives in the domain; the Windows prefix stays in the leaf — **agreed in conversation, 2026-08-29**

`domain/entities/endpoint.go` says today that `\\.\pipe\` "is an OS spelling and
belongs in the leaf". That stays true, and the two cases are not symmetric:

- The Windows spelling is a **constant prefix**. Nothing is decided; the leaf
  concatenates.
- The POSIX location is a **derivation**: an environment variable with a
  fallback, a directory, a suffix, an override case, and a length limit. Five
  decisions — and it is the *rendezvous*, the thing both halves must compute
  identically or never meet. `protocol.md` carries it for exactly that reason.

So the derivation is pure domain code, taking the environment's *values* as
arguments and touching no OS: `LocalSocketPath(name, LocalSocketDirs{...})`. It
compiles and is unit-tested on **every** host, including the Windows leg of CI,
where the POSIX leaf itself is not compiled at all. The leaf reads
`XDG_RUNTIME_DIR` and the home directory, calls it, and dials — no judgement
left in it.

### Decision 8: Windows keeps named pipes — **agreed in conversation, 2026-08-29**

Windows 10 1803+ has `AF_UNIX`, and it changes nothing here: the shipped NVDA
add-on listens on a pipe, and moving it would break every installed copy for no
gain. If that is ever revisited it is a new decision, not this one.

### Decision 9: `protocol.md` carries the rule, and `PROTOCOL_VERSION` does not move — **agreed in conversation, 2026-08-29**

This is a contract change, not only a server refactor: the resolution rule is
the rendezvous, so every bridge implements it and the published document states
it. §1 gains the local endpoint in both its spellings, the derived location, the
0700 directory, unlink-before-bind, and the length limit.

The version does not move. No frame, field, command or value changes shape;
v1 is pre-release and amendable in place under the policy in
[`shared/AGENTS.md`](../shared/AGENTS.md), and this is that policy's ordinary
case.

### What does NOT change

- **The NVDA add-on.** Not one line of `bridges/nvda/` behaviour. It is Windows;
  its local endpoint resolves to `\\.\pipe\nvdaMcpBridge` exactly as it always
  has; no socket path is ever computed for it. `DEFAULT_PIPE_NAME` keeps its
  name and its value.
- **`shared/screenreader_wire/protocol.py`.** Nothing in the socket half reaches
  Python. (Its *module name* changes — that is entry 11.36 and
  [spec 0045](0045-a-wire-module-named-after-the-contract.md), in the same PR
  and for an unrelated reason.)
- **TCP.** Same kind, same spelling, same loopback-only enforcement.
- **The probe's determinism rule.** A listening endpoint nobody configured is
  still invisible and still unconnectable.

### The same measurement, after

Same host, same command, with this spec implemented:

```
nvda -> local:nvdaMcpBridge : <nil>
nvda -> tcp:127.0.0.1:8765 : <nil>
```

Both shipped endpoints now resolve on macOS, from the same embedded
`defaults.json` that resolves to a named pipe on Windows. Four integration
scenarios that could not have been written before — a session over a real Unix
socket, a command slower than the poll interval over one, the probe seeing a
real listening socket, and the whole listing reporting it — pass on the macOS
leg of CI.

## Part 3 — what ships

1. `local` as the transport kind, `pipe` as a permanently accepted alias
   normalised on parse.
2. The POSIX socket-path derivation, in the domain, with its length check, unit
   tested on every host.
3. A real POSIX transport leaf: `net.Dial("unix", …)` where the refusal stub is
   now.
4. A POSIX directory leaf, so liveness is answerable on macOS.
5. `defaults.json` re-spelled `local:nvdaMcpBridge` — the same pipe on Windows,
   a socket path on POSIX, one file either way.
6. `protocol.md` §1 rewritten around the local endpoint, with the listener's
   obligations stated.
7. An integration scenario that establishes a session over a **real Unix
   domain socket**, mirroring the existing named-pipe one, on the macOS leg of
   CI (and any Linux leg later).
8. `--reader` help text, `server/README.md` and `server/AGENTS.md` re-spelled.

## Class/file layout

| File | Role | Change |
|---|---|---|
| `server/domain/entities/endpoint.go` | **entity** (existing) | `TransportPipe` → `TransportLocal` (`"local"`); `pipe` parsed as an alias and normalised; error texts say `local:<name>`; `IsBareName(address) bool` — the pure predicate decisions 3 and 6 both read. |
| `server/domain/entities/local_socket.go` | **entity** (new) — the POSIX rendezvous derivation, pure. Collaborators: none; called by the two POSIX leaves with values they read from the OS. | `LocalSocketDirs{RuntimeDir, Home}` (DTO, same file), `LocalSocketDir(dirs) (string, error)`, `LocalSocketPath(name, dirs) (string, error)`, `MaxLocalSocketPath = 103`, `localSocketDirName = "screenreader-mcp"`, `localSocketSuffix = ".sock"`. |
| `server/domain/entities/local_socket_test.go` | unit test (new) | XDG branch, home branch, neither (error), absolute override, `.sock` suffix, the 103-byte refusal and its message. Runs on every host. |
| `server/domain/entities/endpoint_test.go` | unit test (existing) | `local:`, the `pipe:` alias and its normalisation, `String()` round-trip, `IsBareName`. |
| `server/domain/entities/reader_listing.go` | **entity** (existing) | `liveness()` judges `TransportLocal` **with a bare-name address**; everything else is `unknown`. |
| `server/adapters/bridge/endpoint.go` | **adapter** (existing) | `TransportLocal` → `localDialer`; error text. |
| `server/adapters/bridge/net_transport.go` | **leaf adapter** (renamed from `tcp_transport.go`) | `tcpTransport` → `netTransport`, `dialTCP` → `dialNet(network, address, timeout)`. One wrapper, two networks; the deadline behaviour is `net.Conn`'s either way. |
| `server/adapters/bridge/local_transport_posix.go` | **LEAF adapter** (replaces `pipe_transport_other.go`) | `localDialer(address)`: reads `XDG_RUNTIME_DIR` and `os.UserHomeDir()`, calls `entities.LocalSocketPath`, returns a dialer over `dialNet("unix", …)`. ~15 lines, no test file, per the leaf rule. |
| `server/adapters/bridge/local_transport_windows.go` | **LEAF adapter** (renamed from `pipe_transport_windows.go`) | `pipeDialer` → `localDialer`; an address already beginning `\\` is used verbatim, otherwise prefixed. Behaviour otherwise identical, `winio.ErrTimeout` translation included. |
| `server/adapters/discovery/ports/local_directory.go` | **adapter seam** (renamed from `pipe_directory.go`) | `PipeDirectory` → `LocalDirectory`. Same single `Names()` method, now documented as returning bare endpoint names whatever the host's namespace is. |
| `server/adapters/discovery/local_directory_windows.go` | **LEAF adapter** (renamed) | Unchanged behaviour: lists `\\.\pipe\`. |
| `server/adapters/discovery/local_directory_posix.go` | **LEAF adapter** (replaces `pipe_directory_other.go`) | Lists `entities.LocalSocketDir(...)`, keeps `*.sock`, trims the suffix. An unreadable or absent directory is still an empty list, never an error. |
| `server/adapters/discovery/local_probe.go` | **adapter** (renamed from `pipe_probe.go`) | `PipeProbe` → `LocalProbe`; skips candidates that are not bare names; case folding kept (see Honest limits). |
| `server/adapters/discovery/local_probe_test.go` | unit test (renamed) | Plus the two new cases: an absolute-path candidate is never reported live, and a `.sock` name matches a bare candidate. |
| `server/fakes/local_directory.go` | **test double** (renamed from `pipe_directory.go`) | Mirrors the renamed seam. |
| `server/config/defaults.json` | shipped config | `pipe:nvdaMcpBridge` → `local:nvdaMcpBridge`. |
| `server/config/loader.go` | **adapter** (existing) | `--reader` example text in the error message. |
| `server/config/loader_test.go` | unit test (existing) | Re-spelled; one case pinning that a `pipe:` config file still loads and reports as `local:`. |
| `server/cmd/screenreader-mcp/main.go` | composition root (existing) | `--reader` help text. |
| `server/wiring/wiring.go` | composition root (existing) | `NewPipeDirectory`/`NewPipeProbe` → the renamed constructors. |
| `server/testsupport/reader.go` | test support (existing) | Comment and example spelling. |
| `server/tests/integration/connect_over_unix_socket_test.go` | integration scenario (new, `//go:build integration && !windows`) | Binds a real `AF_UNIX` listener under a short `XDG_RUNTIME_DIR`, serves `testsupport.FakeBridge`, dials `local:<name>`, completes a session, and asserts the probe reports it listening. |
| `server/tests/integration/connect_over_named_pipe_windows_test.go` | integration scenario (existing) | Endpoint spelling only. |
| `specs/wire/v1/protocol.md` | published contract | §1: the local endpoint in both spellings, the derived POSIX location, 0700, unlink-before-bind, the length limit, and the naming convention restated for both mechanisms. |
| `server/README.md`, `server/AGENTS.md` | documentation | Spelling, and the sentence that says which mechanism a host gets. |

No new port, no new controller, and no change to any domain port's signature.

## What is deliberately not built

- **A third transport kind.** Decision 1; it would make the embedded defaults
  host-specific, which is the property this whole design exists to keep.
- **Linux's abstract socket namespace** (`@name`, no filesystem entry). It has no
  macOS equivalent, so it would be a second POSIX answer serving one host, and
  its permission story is the opposite of the one decision 4 is built on.
- **The bridge-side name override.** Board entry **11.37**: today a name can be
  overridden on the dialing side only, which is a way to make the two sides
  disagree silently. It is not on lane 3's critical path and is not fixed here.
- **A dialing probe.** Unchanged reasoning: the bridge serves one session at a
  time, so a probe that connected would occupy the slot the agent is about to
  ask for.
- **`AF_UNIX` on Windows.** Decision 8.
- **Creating or chmod-ing the socket directory from the server.** It dials; the
  listener owns the directory. Doing both would let a server started first
  create a directory with the wrong owner.
- **Any change to `shared/`'s wire constants.** `DEFAULT_PIPE_NAME` is the NVDA
  bridge's pipe name and remains exactly that.

## Honest limits

- **A stale socket file reads as *listening*.** Unlike a pipe, the file outlives
  the process: a bridge killed hard leaves one behind, and the directory listing
  cannot tell it from a live one. `connect_reader` then fails with
  `ECONNREFUSED` where it would otherwise have failed with "nothing there" —
  the same class of race the Windows namespace has between listing and dialing,
  but reachable by a crash rather than only by timing. The mitigations are on
  the listener: unlink before bind (which 13.4 must do, and `protocol.md` will
  require) and unlink at exit, best effort.
- **Case folding is kept as it is** — the comparison lowercases both sides,
  because Windows pipe names are case-insensitive. On a case-**sensitive** POSIX
  filesystem that can match a name the user did not write; the consequence is a
  dial that then fails, not a wrong connection. macOS is case-insensitive by
  default, which is the host that matters for lane 3. Splitting the rule per
  host would put a platform decision back into the probe, which is the one place
  this design keeps platform-free.
- **The 103-byte limit is the smallest of the POSIX hosts**, so on Linux the
  server refuses four bytes it could have dialed. That is the price of one
  constant and one behaviour on every host.
- **`XDG_RUNTIME_DIR` is trusted as given.** If it is set to something that is
  not a private directory, the socket is not private. Checking would mean the
  server auditing a directory it does not own and does not create.
- **`local:nvdaMcpBridge` is unproven against a real NVDA.** The Windows
  resolution is the same concatenation it always was and the integration
  scenario dials a real pipe, so what is untested is one string in
  `defaults.json` reaching a bridge that is actually running. The next live run
  on Windows is where that is confirmed; until then it is a claim this PR does
  not make.
- **The POSIX leaf reads the environment at dial-build time**, so a process
  whose `HOME` changes mid-run is not tracked. Neither is anything else in this
  server's configuration, which is resolved once at startup on purpose.

## Open questions

None. The one that was open — whether this PR carries a live-NVDA checklist —
was settled in conversation on 2026-08-29: **it does not.** Nothing on the NVDA
path changes but the spelling of one shipped default, and the pipe leaf and the
pipe scan are exercised against a real namespace by the existing Windows
integration scenario in CI. What no automated tier proves is that the *re-spelled
default* reaches a real NVDA, and that is recorded above under Honest limits
rather than blocking a merge on a host the work is not being done from.

## Not in scope

- Board entry **11.37** (the endpoint name overridable from the listening side).
- Board entry **13.4** (the VoiceOver bridge that will listen on this endpoint).
  This spec's obligation towards it is `protocol.md`, not code.
- Remote / non-local transports of any kind. `requireLoopback` is unchanged and
  the contract's local-machine-only rule is unchanged.
