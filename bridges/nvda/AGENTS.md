# bridges/nvda/ — the NVDA bridge add-on

The manual for this package. The repo-wide manual is the root
[`AGENTS.md`](../../AGENTS.md) — the four-role vocabulary (port / controller / entity
/ adapter), the hard invariants, the workflow and the task list all live there
and are not repeated here. This file is the bridge's own rules: its
architecture, its dispatch layer, how its tests are shaped, and the NVDA
gotchas that cost real time.

`bridges/nvda/` is the `nvdaMcpBridge` NVDA addon (a global plugin), built with
scons and running on NVDA's embedded CPython 3.13. It is inert until a session
connects.

## Internal architecture — the bridge

Bridge (`bridges/nvda/addon/globalPlugins/nvdaMcpBridge/`): the Session
lifecycle in `domain/controllers/session.py` (+ `teardown_reason.py`), the
per-command handlers under `domain/controllers/commands/` (see "Command
handlers" below); entities `speech_buffer.py` / `braille_buffer.py` /
`indexed_buffer.py` / `bridge_events.py` / `connection_mode.py`; ports
`adapter_factory.py` (+ `AdapterSet`), `speech_source.py`, `braille_source.py`,
`gesture_sender.py`, `announcer.py`, `session_signals.py`, `log.py`,
`log_capture.py`, `bridge_config.py`, `event_bus.py`, plus `clock.py`,
`message_channel.py`, `transcript.py`; adapters `json_lines_channel.py`,
`file_transcript.py`, `text_file_writer.py`, `real_clock.py`, the `nvda_*.py`
edge adapters, and the connection stack (`socket_transport.py`,
`named_pipe_transport.py`, `tcp_listener.py`, `named_pipe_listener.py`,
`build_listener.py`). `protocol.py` (the synced shared wire module) sits at the
package root, `plugin.py` is the NVDA edge, and `views/bridge_dialog.py` is the
control UI — a **driving actor**, not an adapter: it consumes ports rather than
implementing one (see [spec 0011](../../specs/0011-bridge-control-ui.md)).

### Rules that keep this honest — the Python half

The root manual's shared rules apply unchanged (module headers state their role,
adapters are layered so the untestable part shrinks to a leaf, one class per file
and no re-export facades). These are the ones specific to this half:

- **Ports are `abc.ABC`s with `@abstractmethod`** (not `Protocol`): an
  incomplete adapter fails at construction, and the interface itself can't be
  instantiated. The domain depends only on ports; adapters subclass and
  implement them; **`wiring.py` is the only place that knows both.**
- **No DI container library.** `wiring.py` read top-to-bottom *is* the answer to
  "who connects what"; annotation-driven auto-wiring hides that graph and turns
  compile-time wiring errors into runtime ones inside NVDA. `dependency-injector`
  is additionally disqualified: it is Cython-compiled and ships platform wheels
  (the `pydantic-core` objection), and any third-party lib risks a collision in
  NVDA's shared `sys.modules`. If wiring ever gets genuinely hard to follow,
  promote it to an explicit hand-written `container.py` of factory functions —
  same central place, zero dependencies, still checked by pyright.
- **Mode (silent/live) is only known after `hello`.** Do not build
  mode-specific adapters up front. `wiring.py` injects an **`AdapterFactory`
  port**; `Session` reads `hello`, then calls `factory.build(mode)` for the
  adapter set. No "configure the adapter after constructing it".
- **The NVDA/SDK edge is exempt from the type checker; the domain is not.** We
  do **not** vendor stubs and do **not** depend on the NVDA source. Instead the
  side-effecting adapter files (those importing NVDA, plus the bridge's
  `plugin.py`) are listed in pyright's `ignore`, so their unresolved imports
  raise nothing. This is safe precisely *because* the domain is pure and fully
  strict-checked and those thin edge files are validated by the milestone-6
  live-NVDA integration tests. Keep edge files thin — real logic belongs in the
  checked domain.

## Command handlers — the dispatch layer — **Decided**

The `Session` is a controller, but it does two jobs and delegates one. Session
**lifecycle** — the handshake, the heartbeat/inactivity watchdogs, and the
teardown that restores the synth on every path — stays in
`domain/controllers/session.py`. Per-command work lives in
`domain/controllers/commands/`, one **`CommandHandler`** (an `abc.ABC`) per wire
command, one file each, mirrored one-for-one by a test. This keeps the Session
small and lets a command be added or tested in isolation.

- **A handler is a controller.** It orchestrates one use case over
  ports/entities and returns a wire result, or **raises** to fail it — a
  `CommandError` for its own errors, a `protocol.ValidationError` for bad
  params, `GestureError` from the port. The Session centralises everything
  else: it wraps the result in a `Response` with the request id, turns any
  raise into an error reply, and owns the watchdog bookkeeping. Handlers never
  touch the channel, the loop, or teardown.
- **Handlers see only a `SessionContext`, never the Session.** The context
  (`commands/session_context.py`) is the per-session bundle — clock,
  transcript, the speech/braille buffers, the `AdapterSet` — plus exactly one
  lifecycle capability, `close(reason)`. A command that must end the session
  (`bye`, and session C's panic path) calls `close`; it cannot reach lifecycle
  internals. Because a handler needs only a hand-built context, it is
  unit-tested with **no Session and no run loop** (`tests/support/context.py`
  builds one from fakes).
- **The registry is an explicit map, not a container.**
  `commands/registry.py`'s `build_command_registry(...)` is a hand-written
  `command → handler` dict, read top to bottom — the same reason `wiring.py` is
  explicit (no DI container, no decorator auto-registration). Handlers are
  stateless singletons; the per-session state is the context passed to
  `execute`. **`hello` is the exception:** it is the bootstrap command that
  *builds* the session, so it is wired with the `AdapterFactory` and the NVDA
  version and populates the context — the Session no longer knows the factory
  at all.
- **Dispatch policy is declared on the handler, not special-cased in the
  loop.** `resets_inactivity` (false only for `ping`) and
  `available_before_hello` (true only for `hello`) are class attributes the
  dispatcher reads, so the one loop needs no `if cmd == ...`.
- **One dispatch loop.** The Session runs a single `while self._reason is None:`
  loop over a pre-hello/established state: pre-hello only `hello` is accepted
  and any failure ends the handshake; established, the session is tolerant (an
  error reply, keep going). A `TIMEOUT` sets no reason and polls again; every
  real exit sets the reason. (This replaced the two poll loops the first cut
  had.)

## Testing — the bridge

The root manual carries every rule both halves share, and they all apply here:
`tests/unit/` mirrors the package file for file, one test module per source
module, a source file with no test file is a deliberate statement, doubles are
hand-written stateful fakes subclassing their ABC rather than mocks, fixtures
serve uniform collaborators while builder helpers serve per-test scenarios, and
time is injected rather than patched. Below is only what is specific to the
bridge.

### `tests/integration/` — headless scenarios and live-NVDA ones

**`tests/integration/` is named after the USE CASE, not the file** — these prove
a whole scenario end to end. Two kinds live here. **Headless** scenarios drive
the real session stack (real dispatch, real JSON-lines framing) over a
`LoopbackTransport` with a fake NVDA, no socket and no NVDA — so they **run in
CI** like any unit test (e.g. `test_wire_session_roundtrip.py`, the recipe lane
2 builds on). **Live-NVDA** scenarios (`test_live_nvda_e2e.py`,
`test_live_nvda_pipe_e2e.py`) need a real NVDA and are the only place that
proves a *real* adapter behaves like its fake; they do not run in CI.

### Driving a live NVDA — three things that cost real time

A live-NVDA run drives the machine a **blind developer is currently using**. Everything below was learned by getting it wrong on the maintainer's own desktop.

**Announce every phase transition, not just the start.** `announce()` is the only channel the tester has. Without it, focus moves, dialogs open and keys are typed with no explanation — which for a screen-reader user is indistinguishable from their machine misbehaving. Announce *before* the action, including before verification steps, not only before the ones you hand over.

**Prime the control, then set the override — never the reverse.** A settings dialog reads its values when it *opens*. If a dialog is already open when an override is set, pressing OK writes the **pre-override** value back, which the hook faithfully captures into the override map — so the override looks displaced when it was simply overwritten, exactly as spec 0015 documents. This reads as a failure of the write hook and is not one. Sit on the control first.

**The 120s inactivity watchdog invalidates any step with human work between the override and the check.** `ping` deliberately does not reset it (`command_handler.py:38-41`: it proves liveness, not that the agent is still testing). A session dies while the tester navigates a dialog, silently discarding the override, and the result reads as "the override did not survive a profile switch". Either prime the tester so the gap is seconds, or drive the whole step from the agent. Most steps turn out to be agent-drivable: `get_config`, `get_speech` and `get_focus_info` make the assertions without anyone needing to *hear* anything, so reserve the human for what genuinely needs hands or ears.

Corollary worth remembering: `setConfig` can enable a setting a test needs and teardown restores it, so "the tester's configuration is wrong for this test" is usually solvable without asking them to change anything.

## Gotchas — NVDA and the add-on build

The root manual keeps the gotchas that span the repo (CI job names, the three
pyright configs, what language servers get wrong here). These are the bridge's.

- **Silent-mode synth swap fights config profiles.** NVDA reloads the synth
  from `config["speech"]["synth"]` on *every* `config.post_configProfileSwitch`
  (`synthDriverHandler.py:420`, `566-584`). The naive
  `setSynth(spy, isFallback=True)` leaves config pointing at the real synth, so
  the first profile switch rips the spy out. Fix: set config's synth name to
  the spy, guard `config.pre_configSave`, and patch
  `synthDriverHandler.getSynthInstance`. See the spec's fail-safe section.
- **NVDA answers on non-speech channels.** Some actions (e.g. NVDA+space
  toggling browse/focus mode) signal via an earcon/beep, not words, so speech
  assertions have nothing to match. Use `getState` (browse/focus mode, speech
  mode, sleep, input help) to assert those.
- **NVDA reference source is `../nvda/source`** (2026.1). Consult it for APIs
  rather than guessing; only `source/` is needed. It is a **reference only** —
  not a build/CI/type-check dependency. Adapter files that import NVDA go in
  pyright's `ignore` list (see the ports & adapters section); the domain they
  serve stays fully strict-checked.
- **`buildVars.pythonSources` must be RECURSIVE (`**/*.py`).** This addon is a
  hexagonal *package* with subdirectories, not the flat single-module addon the
  AddonTemplate assumes. sconstruct turns each `pythonSource` into a build
  dependency of the `.nvda-addon`, so the template's non-recursive
  `globalPlugins/nvdaMcpBridge/*.py` tracked only the top-level modules — editing
  anything under `adapters/` or `domain/` changed no tracked dependency and
  `scons` reported *"up to date"* without repackaging, silently shipping stale
  code. (The build *action* rglobs the whole tree, which is exactly why a forced
  clean rebuild always looked correct and hid the hole.) When you build, don't
  trust "up to date" alone after a subdirectory edit — or just keep the glob
  recursive.
- **A crashed client must never take the bridge server down.** A client that
  dies mid-session RSTs the socket, so `sock.recv` raises `ConnectionResetError`
  (WinError 10054), *not* `b""`. The Session loop only catches `ChannelClosed`,
  so an un-mapped socket error escapes up through `run()` and kills the
  `BridgeServer` accept loop — a crashed *client* stops the *bridge*. The
  `SocketTransport` leaf maps any socket error other than the idle timeout to
  `b""` (an abrupt reset is an abrupt EOF), and `BridgeServer` wraps each session
  so no session fault can break the accept loop. Keep both.
- **NVDA mutations run on NVDA's MAIN thread; the bridge Session runs on a
  background (server) thread.** Anything that touches NVDA from an adapter —
  `tones`, the synth, gestures — must marshal to the main thread
  (`adapters/nvda_main_thread.run_on_main`, or `wx.CallAfter`), or it races
  NVDA's own main-thread work. Teardown paths use the fire-and-forget form so a
  main-thread caller (panic/terminate) can't deadlock waiting on the thread it
  is joining. (The original silent-mode mute bug was exactly a server-thread
  `setSynth` racing a main-thread config-profile reload; spec 0008 removed the
  synth swap entirely, but the thread rule stands for tones and gestures.)
