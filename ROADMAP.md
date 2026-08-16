# screen-readers-mcp — Roadmap and Status Board

Companion to [`AGENTS.md`](AGENTS.md) (operating manual) and [`specs/`](specs/)
(design specs). This document owns build order **and execution status**. It is
the answer to "what should we do now?" — and it lives in the repo, so a fresh
session or a new contributor answers that question without anyone's private
notes.

## How to use this board — **Decided**

- **Finding the next step:** take the first entry in a lane below that is not
  marked Done, respecting the lane rules. Its "Spec" field tells you what kind
  of work comes next:
  - **Spec: none yet** → the next step is a spec conversation, not code. Branch
    off main for the entry, write the spec there (`specs/NNNN-title.md`) with
    Marlon, and get it agreed in conversation. The spec **must include the
    class/file layout** — every class to be added, its role, and its
    collaborators — so the decomposition is reviewed before code (see AGENTS.md,
    "Spec before code"). The spec rides in the implementing PR on that branch —
    it does not land on main separately — and the PR updates the entry's Spec
    field. Never code ahead of an agreed spec: implementation starts on the
    branch only after the spec is approved in conversation.
  - **Spec: exists** → implement it in a PR judged against the spec (branch off
    main; short PR: one component + its port(s) + tests, per AGENTS.md).
- **Marking done:** the implementing PR flips its own entry to
  "Done (PR #n, date)" as part of the PR. The mark becomes true on main exactly
  when the PR merges — no separate bookkeeping commit.
- **Lanes:** lane 1 (bridge) and lane 2 (server) may run in parallel — at most
  one open PR per lane, never two in the same lane. Order within a lane is
  strict. (Entries 5 and 6 predate this rule and are grandfathered; from here
  on it holds.)
- **Manual live-NVDA checklists** and their results live in the implementing
  PR's body as checkboxes; findings are written inline on the unchecked item
  (NVDA version, expected vs observed) and spawn new iteration entries here.
  The `no unchecked checkboxes` CI job keeps an unfinished checklist from
  merging.
- **Grandfathering:** entries merged before this board existed are backfilled
  as Done with their historical PR numbers, with RFC 0001 as their spec.
  In-flight PRs at the time the board landed also run under RFC 0001; every
  entry after them gets its own spec file.

## Session map

The sessions come from
[RFC 0001](specs/0001-agent-driven-nvda-over-mcp.md), Milestones: **A**
foundation → **B** bridge core (headless) → **C** bridge↔NVDA (needs live
NVDA) → **D** MCP server (headless; parallel to B/C) → **E** introspection +
real-world → **F** packaging. Each board entry belongs to one session.
[Spec 0005](specs/0005-multi-reader-direction.md) (the multi-reader direction
RFC, agreed 2026-07-18) added one cross-cutting wire entry to lane 1 (entry 8,
a headless B follow-up) and amended the scope of entries 9 and 12.

Session E was originally one entry (11). It became four on 2026-07-23 — 11
(the real-world run), 11.1 (introspection), 11.2 (human-in-the-loop) and 11.3
(observe-only) — with the run deliberately first. See the note under
Convergence for why.

## Status board — lane 1: bridge

**Lane 1 is complete** as of 2026-07-22: every entry below is Done, milestones
A–C are closed, and no lane-1 work is in flight. The known future lane-1 entry
is Remote TCP, deferred under 9.1b with its own security spec; it is not
scheduled. Work now proceeds in lane 2.

1. **Done** — A, foundation: shared wire protocol + tests, server and addon
   scaffolds, CI, GPL-2.0-or-later licensing. Spec: RFC 0001. Merged as PR #1
   (2026-07-13).
2. **Done** — B, wire enumerations as real enums (`StrEnum` in `protocol.py`).
   Spec: RFC 0001. Merged as PR #3 (2026-07-15).
3. **Done** — B, hexagonal architecture agreed for bridge AND server (docs
   only; the rules now in AGENTS.md). Spec: RFC 0001 + AGENTS.md. Merged as
   PR #4 (2026-07-15).
4. **Done** — B, headless foundation + buffer entities; drops the NVDA source
   dependency (pyright ignore list for the NVDA edge). Spec: RFC 0001. Merged
   as PR #5 (2026-07-15).
5. **Done** — B, MessageChannel port + JSON-lines adapter: the Session's
   whole-message I/O seam, framing behind the Transport adapter seam. Spec:
   [0002-bridge-message-channel.md](specs/0002-bridge-message-channel.md)
   (retroactive, rides in the PR). Merged as PR #6 (2026-07-17).
6. **Done** — B, Transcript port + file transcript stack: the session's
   human-readable record, vocabulary tested against a fake writer, real IO in
   a decision-free leaf. Spec:
   [0003-bridge-transcript.md](specs/0003-bridge-transcript.md) (retroactive,
   rides in the PR). Merged as PR #7 (2026-07-17).
7. B, session controller — split into two sequential PRs, one spec:
   [0004-bridge-session-controller.md](specs/0004-bridge-session-controller.md)
   (rides in PR 7a's branch).
   - **7a** — **Done (PR #9, 2026-07-17)**: five domain ports (`AdapterFactory`
     — mode known only after `hello` — speech/braille sources, synth swapper,
     gesture sender), `Session` (handshake, dispatch, heartbeat + inactivity
     watchdogs, teardown that always restores the synth), the scriptable
     fakes, session unit tests.
   - **7b** — **Done (PR #10, 2026-07-18)**, closes session B: `echo` wire
     command + `EchoHandler`, `wiring.py` (`build_session`), `LoopbackTransport`,
     and the headless wire-level scenario — the integration surface lane 2
     tests against.
8. **Done (PR #11, 2026-07-18)** — B follow-up (headless; added by
   [spec 0005](specs/0005-multi-reader-direction.md)), wire: the published
   contract — `hello` announces `reader` (name + version) and `capabilities`
   (replacing `nvdaVersion`), a `COMMAND_SHAPES` table in `protocol.py`, a JSON
   Schema generated from the dataclasses (`specs/wire/v1/schema.json`) with a CI
   drift gate, and the hand-written prose semantics doc
   (`specs/wire/v1/protocol.md`). Spec:
   [0006-wire-published-contract.md](specs/0006-wire-published-contract.md)
   (rides in the PR).
9. **Done** — C, bridge↔NVDA: real NVDA adapters (`adapters/nvda_*.py`),
   `synthDrivers/nvdaMcpSpy.py`, the `socket_transport.py`/`tcp_listener.py`
   accept stack, plugin wiring, panic gesture, scons build. Real adapters supply
   the live `reader`/`capabilities` values for the `hello` fields entry 8 adds.
   The listener is a **start/stop lifecycle controller** (`BridgeServer`) with
   observable status (stopped / listening on endpoint / session active) — the
   seam entry 9.1's control dialog drives — not a fire-and-forget loop
   (agreed 2026-07-18). Spec:
   [0007-bridge-nvda-edge.md](specs/0007-bridge-nvda-edge.md) (agreed
   2026-07-19; delivered as three sequential PRs, the split agreed 2026-07-19
   to keep checklist iteration on a small final PR). Scope: RFC 0001
   milestones 1–3; the fail-safe synth restoration design (config name swap,
   `pre_configSave` guard, `getSynthInstance` patch) is **Decided** in RFC 0001.
   - **9a** — **Done (PR #12, 2026-07-20)**: the headless connection stack —
     `Listener` seam + `TcpListener`, `SocketTransport`, and `BridgeServer`,
     proven by a real-socket integration scenario in CI.
   - **9b** — **Done (PR #13, 2026-07-20)**: the NVDA adapters (`nvda_*.py`) +
     `nvdaMcpSpy` spy synth (addon still inert), the pure `spy_sink` seam
     unit-tested, and the announced capabilities narrowed to
     speech/braille/gestures.
   - **9c** — **Done (PR #14, 2026-07-21)**: the switch-on — `plugin.py`
     wiring, the panic gesture (`kb:NVDA+control+shift+b`), packaging verified,
     and the live-NVDA checklist run with Marlon at the keyboard (results in
     the PR body). Live testing **pivoted the silent-mode mechanism**: the spy
     synth + `SynthSwapper` + RFC 0001 fail-safe (9b) were replaced by
     transparent capture at `filter_speechSequence` (the real synth stays
     loaded; it cannot strand the user mute), and the PR added session beeps,
     the `announce` hint command, crashed-client resilience, and a build
     dependency fix. See [spec 0008](specs/0008-transparent-silent-capture.md).
9.1. C follow-up, bridge control UI + connection config (agreed 2026-07-18;
   split into 9.1a/9.1b 2026-07-21 — the transport leaf has no UI dependency,
   so it does not need to wait behind the dialog).
   - **9.1a** — **Done (PR #18, 2026-07-21)**: the named-pipe transport leaf (ctypes,
     stdlib-only) — `NamedPipeListener`/`NamedPipeTransport`, implementing the
     existing `Listener`/`Transport` seams exactly, so either can be handed to
     `BridgeServer` interchangeably with `TcpListener`/`SocketTransport`.
     Local-machine-only by construction (`PIPE_REJECT_REMOTE_CLIENTS` + an
     owner-only DACL, the pipe analogue of the loopback-only bind). Proven by
     a real-named-pipe headless integration scenario in CI, the same tier of
     proof 9a gave the TCP leaf, **and then by a live-NVDA check against a
     real, running NVDA** (`test_live_nvda_pipe_e2e.py`: handshake, a
     silent-mode gesture captured, two sequential sessions) — on the strength
     of that result, `plugin.py` was flipped to the pipe as the default in
     this same PR (amendment to spec 0010), rather than waiting for 9.1b.
     `TcpListener` stays in the tree, unwired, as 9.1b's compat option.
     `DEFAULT_PIPE_NAME` added to the shared wire module; the wire spec's
     transport section (`specs/wire/v1/protocol.md` §1) amended to describe
     it. Spec: [0010-named-pipe-transport.md](specs/0010-named-pipe-transport.md).
   - **9.1b** — **Done (PRs #20, #21, #22, 2026-07-22)**: an NVDA menu → Tools
     entry opening a bridge dialog — connection-mode combo (Local: named pipe
     [default] / loopback TCP; Remote: TCP/IP, **greyed out** — see below),
     status indicator showing the accepting endpoint, Start/Stop buttons
     driving entry 9's lifecycle controller, and an auto-start checkbox — all
     persisted to NVDA config. The pipe is already the plugin's default
     (9.1a); this entry lets a user *override* it back to loopback TCP via
     config, rather than making the switch itself. **Remote TCP is deferred —
     Decided**: it is remote keystroke injection (`pressGesture`) and config
     write (`setConfig`), so enabling it is a future entry with its own
     security spec (explicit warning + bridge-generated access token presented
     in `hello`); until then the combo shows it disabled. Delivered as three
     sequential PRs: **#20** the domain foundation (`EventBus`, `Log`,
     `BridgeConfig` ports + the `BridgeEvent` DTO), **#21** the adapters and
     plugin wiring (`IniBridgeConfig`, the event bus, `BridgeServer` status
     events), **#22** the dialog itself (`views/bridge_dialog.py`, Tools menu
     registration) with the live-NVDA GUI checklist run against NVDA 2026.1.1
     (results in the PR body). Spec:
     [0011-bridge-control-ui.md](specs/0011-bridge-control-ui.md).
9.2. **Done (PR #17, 2026-07-21)** — C follow-up, NVDA log capture per
   session: every session tees NVDA's own log to a fresh, session-scoped file
   for `hello` to teardown, so debugging an add-on no longer needs manual
   before/after markers in `nvda.log`. `hello` gains an optional `logLevel` to temporarily
   raise NVDA's own logging verbosity for the session (restored at
   teardown), alongside the always-on capture. A second, parallel artifact
   to the existing transcript (spec 0003) — NVDA's real diagnostic log, not
   the bridge's domain vocabulary. Needs live NVDA (checklist: capture file
   distinct from `nvda.log`, `logLevel` surfaces DEBUG lines, level restored
   after teardown). Spec:
   [0009-nvda-log-capture.md](specs/0009-nvda-log-capture.md) (agreed
   2026-07-21).

## Status board — lane 2: server (headless; may run parallel to lane 1)

**Lane 2's only entry is complete** as of 2026-07-23: session D is closed, and
with lane 1 already complete, convergence is unblocked. Entries 11a and 11b (the
real-world run) are Done; work now proceeds through the convergence entries
below. **Open as of 2026-08-16**: 11.3, 11.6, and the entries 11.14–11.17 that
came out of the first external run. Their order among themselves is not yet
decided — 11.14 is docs-only and 11.15 is small and well understood, so neither
needs to wait behind 11.3's and 11.6's unagreed specs, but taking them first is
a reprioritisation to make explicitly, the way 11.4 was taken before 11.3.

**11.8–11.13 are reserved, and were claimed first.** PR #54 numbered the
external-run entries 11.8–11.11 on 2026-08-15 without checking the open PRs that
also edit this file, and two of them had already taken that range: **#51** claims
11.8–11.10 (speech segmentation, the round-trip cost, the mute watchdog) and
**#52**, stacked on it, claims 11.11–11.13 (specs 0024–0026). Both were opened
2026-08-03, so they have precedence and the external-run entries were renumbered
to 11.14–11.17 on 2026-08-16 rather than the other way round. **Spec numbers
0024, 0025 and 0026 are likewise taken by #52** — the next free spec number is
0027. Anyone adding a board entry or a spec should check the open PRs first;
this file is edited by nearly every PR, so a number that is free on main is not
necessarily free.

10. **Done (PRs #29, #30, #31, #32, #33, #34, #35, #36, #37, #38,
    2026-07-23)** — D, MCP server — **in Go**, a statically linked binary
    speaking MCP over stdio and JSON lines to one bridge. Spec:
    [0013-mcp-server.md](specs/0013-mcp-server.md) (agreed 2026-07-22; rides in
    10a's branch). Scope: RFC 0001 component 2 + milestone 4, encoding the
    reader-agnostic chassis principles of
    [spec 0005](specs/0005-multi-reader-direction.md) (no reader conditionals;
    reader identity surfaced; reader vocabulary as opaque data; bridge endpoint
    as composition-root config). The language change **amends 0005's "the v1
    server is Python"**, and the entry's original "`BridgeClient` port" wording
    is amended to seven capability-group ports — both recorded in spec 0013,
    both landing in 10a. Dialing **both** the pipe and loopback TCP is in scope
    from the start (amended 2026-07-22, superseding the earlier "small lane-2
    follow-up" note), and 0013 goes further: each reader declares every endpoint
    its bridge is known to listen on, tried in order, so spec 0011's transport
    toggle needs no configuration. Delivered as three sequential PRs:
    - **10a** — **Done (PRs #29, #30, #31, #32, #33, 2026-07-22)**: the module,
      the generated wire binding, the layered endpoint
      config, and the bridge client: dials a bridge and completes a handshake,
      proven headlessly. No MCP surface. Carries spec 0013 and the 0005 and
      AGENTS.md amendments; deletes the Python `mcpServer/` scaffold and turns
      the CI `server` job into a Go one (job name unchanged — branch protection
      matches literal names). **Delivered as five sequential PRs** (the short-PR
      principle applied to a 6,000-line first cut): the wire binding and the Go
      CI job; the `mcpServer/` deletion; the domain; the bridge client;
      discovery, config, wiring and the entry point. The deletion waits for the
      first, because the `server` job must be repointed at Go before the
      directory it names disappears.
    - **10b** — **Done (PRs #34, #35, #36, 2026-07-23)**: the MCP surface:
      `list_readers` / `connect_reader` /
      `disconnect_reader` / `status`, the capability-gated tool set, the
      `screenreader://info` resource, and the agent-initiated connection
      lifecycle (no auto-connect, no backoff). Amends the wire prose with the
      pipe naming convention.
    - **10c** — **Done (PRs #37, #38, 2026-07-23)**: the cross-language
      conformance job (`windows-latest`, the real Python bridge over a real pipe
      and over TCP), release plumbing for the `server-v*` tag, and the board
      flip. The conformance tier is the successor to the same-bytes drift
      guarantee the two halves had while both were Python: it is the only place
      where both implementations of `specs/wire/v1/` are real, so a bug in the
      generated binding — invisible to every tier whose bridge is a Go fake
      encoding with that same binding — has somewhere to surface. It found one
      on its first run (the named-pipe leaf reporting an idle read as a lost
      connection, so every command slower than one 50 ms poll failed over the
      transport the add-on ships listening on). The `conformance` job is a new
      job name, so it became a **required status check only after it had
      reported green on main** (2026-07-23) — branch protection matches required
      checks by literal name, so pushing the workflow and flipping the setting
      are deliberately two steps, in that order.

## Convergence (requires C and D both Done)

**Entry 11 was resequenced on 2026-07-23** (agreed in conversation). It
originally read "introspection + real-world" as one entry. It is now **four**,
because a discovery pass found that the two halves have almost nothing to do
with each other and that the real-world run is not blocked on anything:

- The server side of introspection is **already complete**. `FocusInfo()`,
  `State()`, `GetConfig()` and `SetConfig()` exist on `JSONLinesClient`, the
  four tools exist, and the capability gate covers them — all merged in 10b.
  The entire remaining gap is bridge-side: `NVDA_CAPABILITIES` in
  `domain/controllers/commands/registry.py` announces only
  speech/braille/gestures/announce, and the four commands answer
  `NotImplementedHandler`. So introspection is a **lane-1-only** entry.
- The real-world run therefore needs **nothing new**: the gate derives the
  advertised tool set from what `hello` announced, so an agent connecting today
  sees the four ungated tools, the five speech tools, `getBraille` and
  `pressGesture` — press a gesture, read what was said, which is the core loop
  the run exists to exercise. Running it first means the findings shape the
  entries after it instead of being guessed at.

**The run is `live` mode, attended — Decided (2026-07-23).** This is what makes
the ordering work. In `silent` mode all of NVDA's speech is suppressed, so an
agent that announces "I am stuck" tells the tester something they then cannot
act on: they cannot hear their way to the chat window to reply, and their only
escape is the panic gesture, which stops the whole bridge. In `live` mode the
real synth keeps talking, so the tester hears the app, hears themselves reach
the agent's window, and answers there normally. Silent + unattended is exactly
the configuration that needs entry 11.2, which is why 11.2 comes after the run
rather than before it.

11. **E, the real-world run** — split into two sequential PRs, one spec:
    [0014-announce-and-real-world-run.md](specs/0014-announce-and-real-world-run.md)
    (**drafted 2026-07-23, awaiting review**; rides in 11a's branch). Scope:
    RFC 0001 milestone 6.
    - **11a** — **Done (PR #39, 2026-07-24)**: expose `announce` at the MCP
      server. The bridge half has shipped
      since 9c (spec 0008): `NvdaAnnouncer` speaks straight through
      `getSynth().speak()`, which bypasses the suppression filter, so a hint is
      audible even mid-silence, and the bridge already advertises
      `Capability.ANNOUNCE`. The server simply never exposed it — there is no
      `announce` tool and no `CapabilityAnnounce` in the domain vocabulary, so
      the one channel the agent has for reaching a human is unreachable. Five
      files: a domain port, a `JSONLinesClient` method, the domain capability
      constant plus its handshake mapping, the tool, and a registry line.
      `CommandAnnounce`, `CapabilityAnnounce` and `AnnounceParams` already exist
      in the generated binding, so the wire needs no change.
    - **11b** — the end-to-end run against
      [EnhancedFindDialog](../EnhancedFindDialog) with Claude Code as the MCP
      client, `live` mode, tester at the keyboard. The live-NVDA checks here are
      what prove each real adapter behaves like its fake. **Findings are the
      deliverable**: they spawn iteration entries (E.1, E.2, …) in this board,
      per the checklist rule above.
      - **E.1 — `pressGesture` never reached NVDA: the `kb:` prefix was fed to
        `fromName`.** Found in the 11b run (NVDA 2026.1.1, Claude Code driving)
        when every agent-sent gesture was refused — `kb:windows+d` and
        `kb:control+l` both came back `unknown gesture id '…': 'kb:…'`. Root
        cause: `NvdaGestureSender.press` passed the wire's opaque inputCore id
        (`kb:control+l`) straight to `KeyboardInputGesture.fromName`, which wants
        the **bare** combo (`control+l`) — it splits on `+` and looks each token
        up in `vkCodes`, so `kb:control` raised `KeyError`. Every `pressGesture`
        failed identically; the `capture` scenario only ever "passed" on the
        tester's **physical** keypresses, not the agent's. Fix: a pure
        `bare_key_name` helper strips the `kb:`/`kb(layout):` source prefix,
        headless-tested in `tests/unit/adapters/`; the NVDA-touching sender is
        one line thinner. **Fixed in PR #41 and verified live 2026-07-25** —
        after the rebuild, agent-driven gestures drove the desktop end to end
        (spec 0018 Part A).
      - **E.2 — the gesture vocabulary is the reader's user-facing command
        notation, not an internal id. Done (PR #41).** E.1's tolerated `kb:` is
        NVDA inputCore's internal source-namespace, which no agent learns from
        user-facing docs; a source-privileged session reached for it and hit the
        bug, whereas an agent reading only the NVDA User Guide would have sent the
        prefixless `NVDA+f7` and worked even pre-E.1. So the canonical vocabulary
        is the User-Guide key-combo form (`NVDA+f7`, `control+l`, `escape`),
        prefixless; the server routes it opaquely, the bridge maps it via
        `fromName`, and a source prefix is reserved for future non-keyboard
        vocabularies. Reworded `protocol.md` and the `press_gesture` tool
        description; the bridge still tolerates a legacy `kb:`. Validated live in
        both `live` and `silent` mode. Spec:
        [0018-input-vocabulary.md](specs/0018-input-vocabulary.md), Part A.
      - **E.3 — a `type` primitive for literal text. Done (PR #42), verified live
        2026-07-25.** (lane 1 + lane 2). Gestures are commands; typing a URL or
        phrase is content and needs its own command, not one `pressGesture` per
        character (fragile: `VkKeyScanEx` fails for off-layout characters). A new
        `typeText` command + `typing` capability, injected via Win32 `SendInput`
        with `KEYEVENTF_UNICODE`, gated like `pressGesture`; withholding it under
        observe-only still rides on 0017, a separate entry (11.3) not yet built —
        only the `mutates_reader` classification it needs landed here. Live
        end-to-end against a real NVDA and Chrome: `type_text
        "www.blindtec.com.br"` landed all 19 characters (echoed back
        individually by NVDA's own "speak typed characters", proving the
        injection is indistinguishable from a real keystroke), the page loaded,
        and its Elements List was read back through `press_gesture`/`get_speech`.
        Spec: [0019-type-primitive.md](specs/0019-type-primitive.md).
        **Prioritised in lane 1** so the live tests can enter text — URLs, search
        phrases — instead of spelling them one gesture at a time.
11.1. **Done (PR #43, 2026-07-29)** — E, bridge introspection (lane 1). The four handlers behind
    `getFocusInfo` / `getState` / `getConfig` / `setConfig`, their ports and
    NVDA adapters, and re-widening `NVDA_CAPABILITIES` to announce `focus`,
    `state` and `config` — at which point the server's four already-built tools
    light up with no server change at all. Needs live NVDA. Spec:
    `0015-bridge-introspection.md` (agreed 2026-07-25; rode in 11.1's branch).
    Scope: RFC 0001 milestone 5. `setConfig` was amended twice during review and
    ended up never writing to the reader's config at all: a session override map
    with hooks on **both** ends of `AggregatedSection`, because hooking reads
    alone let NVDA's own settings dialog launder an override into the user's
    profile and persist it. Live-verified on a real NVDA, including the override
    beating both a manually activated and a trigger-driven profile switch — the
    claims `test_profile_override.py` was meant to cover and never has, since it
    needs NVDA's own interpreter and cannot run under pytest.
11.2. **E, human-in-the-loop** (both lanes). **Done** (#45). The agent asks the
    tester for something it cannot supply itself — a password, a CAPTCHA, a
    physical act — and gets an answer back, without ending the session. Live
    checklist in the PR body. Spec: `0016-human-in-the-loop.md` (agreed
    2026-07-29; implemented with the heartbeat fix on `0016-human-in-the-loop`).
    It was
    scheduled **after** the run so the run could say whether the cheap shape
    (announce, suspend suppression, acknowledgement gesture) suffices before a
    reply dialog is built: it ran, it does, and stage 2 stays unbuilt. The 11.1
    run also produced the evidence for the timeout analysis — sessions were
    silently torn down by the 120 s inactivity watchdog while a tester worked in
    NVDA's dialogs, discarding overrides mid-test.
11.3. **E, enforced observe-only** (both lanes). A session where the bridge
    *rejects* `pressGesture` and `setConfig`, so the tester drives and the agent
    can only watch. Orthogonal to capture mode — capture mode is about audio,
    this is about input — so it is a `control` field on `hello`, not a third
    `CaptureMode`. Spec: `0017-observe-only-control.md` (drafted, awaiting
    review; rides in 11.3's own PR).
11.4. **Done (PR #46, 2026-07-31)** — E, log slices on demand (both lanes). The
    agent asks what NVDA logged *while a given command ran*, filtered by level
    and by pattern and projected to the fields it needs, instead of being handed
    a path and reading the whole file. Finishes what 0009 started: that entry narrowed the haystack
    to one session, this narrows it to one command — and **supersedes that spec's
    capture file**, since the level raise is global, so NVDA's own `nvda.log`
    already holds identical records. Motivated by measurement during the 11.2
    review: the bridge answers in 0.2-0.5 ms, so the transport was never the cost;
    the cost was moving tens of thousands of tokens of log into context to find
    four lines. Needs live NVDA. Spec: `0020-log-slices-on-demand.md` (agreed
    2026-07-30; rides in 11.4's own PR).
    **Taken before 11.3** deliberately: it pays for itself in every later live
    session, 11.3's own included, and 11.3's spec is still awaiting review.
11.5. **Done (PR #48, 2026-08-01)** — E, observing the log (both lanes). Live
    checklist run 2026-08-01 (27 checks green, no failures — see
    `scripts/live_test.py` scenarios `log` and `logsilent`). The agent marks the
    present moment, then asks what has arrived *since it last looked* — instead
    of only being able to ask what a given command logged. Comes straight out of 11.4's live run,
    which found two things its model cannot serve. A command window closes when the
    handler returns, but NVDA does the work a millisecond later on its own thread,
    so one window holds `inputCore.executeGesture` and little else; and the cases
    that matter most have **no commands at all** — a trigger whose consequences
    arrive over the next fifteen seconds, or "watch what I do, a bug is about to
    appear", where the human is driving and nothing the agent issues is what gets
    logged. Adds a mark (`getLogPosition`), a caller-held cursor
    (`sincePosition`/`nextPosition`), `lastSeconds` for "it just happened", and
    `waitForLog` — the `waitForSpeech` shape, so it stays pull rather than the push
    0020 rejected. Also extends a command's span to the *next* command, which is
    what makes a single window mean something again and retires 11.4's
    `capturedAtLevel` compromise. Needs live NVDA. Spec:
    `0021-observing-the-log.md` (**agreed 2026-07-31**). Its one open question —
    whether the journal coordinate belongs on braille entries and transcript
    lines — was settled in review: braille yes, transcript no, because the
    transcript outlives the journal and its reader is the human at the machine,
    not the agent.
    The live run confirmed the thing 11.4 could not do: a gesture's span now
    holds `speech.speech.speak` and `tones.beep` alongside
    `inputCore.executeGesture`. Item 6 is closed both ways: the agent causes a
    real NVDA ERROR itself (`logerror`) and wakes on it in 3.2 s, and the human
    causes one while the agent watches (`logwatch`), which is the case the
    command was written for. Only a braille entry's coordinate is untested, for
    want of a display.
    **It also turned up an exposure that is NOT this entry's to fix:** the
    gated tools went invisible for the whole run, which is why the checklist had
    to be driven through `scripts/live_test.py`. Read at the time as a client
    that ignores `tools/list_changed`; **diagnosed on 2026-08-02 as our own
    `poe redeploy` killing the client's server process**, after which capability
    discovery never re-runs. The failure is silent and points at the wrong
    component either way, since `connect_reader` returns success with a full
    capability list. Its own entry, below.
11.6. **E, a connected session an agent cannot use** (server lane). Found live on
    2026-08-01 while running 11.5's checklist; **diagnosed 2026-08-02, and the
    diagnosis reversed the premise.** Every capability-gated tool reaches the
    agent through one `tools/list_changed` notification emitted when
    `connect_reader` succeeds (spec 0013), and in 11.5's run the gated surface
    stayed invisible for a whole session — which is why the checklist had to be
    driven through `scripts/live_test.py` instead. The entry was written as *the
    client ignores the notification*. **It does not.** Claude Code honours it in
    both directions (370 successful gated calls across five earlier sessions,
    and tools withdrawn again on disconnect); the server declares
    `tools.listChanged` correctly, which an independent MCP client confirms
    against the current binary. What actually severs it is **our own
    `poe redeploy`**: it kills every `screenreader-mcp.exe`, the client's
    included, and a killed stdio server drops out of the client's managed
    lifecycle — it is silently respawned to serve the next call, but capability
    discovery never re-runs, so the tool list stays frozen at the ungated four.
    Documented client behaviour, not a defect ("stdio servers are local
    processes and are not reconnected automatically"). Reproduced
    deterministically, and across every transcript in the project's history **no
    gated call has ever succeeded after a redeploy killed the server in that
    session**. What still makes it worth an entry is the shape of the failure:
    `connect_reader` returns success *with a full capability list*, so the agent
    concludes the server or the bridge is broken and spends a session there.
    **The cure exists and costs one command** — `/mcp reconnect
    screen-reader-testing`, verified — but only the human can run it: `/mcp` is
    client UI, unreachable from an agent by any route. Now written into
    `AGENTS.md` and printed by `redeploy.py` itself. That leaves the entry
    smaller and no longer urgent — a shipped user never redeploys — so what
    remains to be argued is (1) whether a genuinely deaf client is supported at
    all, on principle rather than under a live failure, and (2) whether the dev
    loop should stop severing the surface by construction. Options unchanged
    ((a) say so at the point of failure; (b) an always-present dispatcher tool;
    (c) advertise everything always; (d) gate by default with an opt-out), with
    one new argument: under (c)/(d) the tool list never changes, so a stale
    cached list is a *correct* one and the redeploy breakage stops mattering.
    A hot-reload proxy (**mcpmon**) would remove the human from the loop
    entirely and retire `redeploy.py`'s kill-by-image-path; it is the only route
    to an autonomous rebuild-and-test loop, and it is boardable separately
    rather than required here. Still needs a spec conversation: it revisits a
    decision spec 0013 made deliberately. Spec:
    [0022-tool-discovery-an-agent-can-rely-on.md](specs/0022-tool-discovery-an-agent-can-rely-on.md)
    (premise corrected 2026-08-02, not agreed).
11.7. **Done (PR #49, 2026-08-01)** — E, drive it like a user (server lane).
    Also found during 11.5's live run.
    `pressGesture` and `typeText` return `{ ok: true }`, which means the
    reader **accepted** the input — and 0021 already proved that the reader does
    the work afterwards, on its own thread, so the result *cannot* mean the
    effect happened. Three failures in that run had the same shape (a console
    typed into before it opened, a search term typed into whatever held focus,
    a remapped gesture opening the wrong dialog) and each surfaced later as an
    unrelated check failing, naming the wrong component. The hand-tuned
    `time.sleep(1.5)` calls in `scripts/live_test.py` are the standing
    workaround.
    The first draft answered with a `waitForFocus` command; **review rejected
    it** and the entry is the better for it. Focus is not the axis — most reader
    commands never move focus — its `role`/`appModule` matchers are vocabulary a
    user does not have, its `found: false` collapses agent error with app
    behaviour (the exact fault the entry exists to fix), and it would not even
    have caught the console failure, where focus was correct and the field was
    not empty. What a user actually does is press, listen to the announced
    window title, then ask the reader "where am I" with its own command and
    listen again. Speech is the observable that is always there, and the wait for
    it — `waitForSpeechToFinish` — already exists.
    So the deliverable is a **doctrine, not a protocol change**: a new static
    `screenreader://guidance` resource holding the act/settle/listen/orient/
    escalate loop, plus `press_gesture`, `type_text`, `get_focus_info` and
    `wait_for_speech_to_finish` descriptions that say the true thing at the point
    of failure. Introspection keeps its place — reframed as *assert in a test*
    and *survey an application*, which is the strongest case for it and points at
    a future object-navigation entry — but stops advertising itself as the way to
    find out where you are. **No wire change, no bridge change, no new
    capability.** Spec:
    [0023-drive-it-like-a-user.md](specs/0023-drive-it-like-a-user.md)
    (agreed and implemented 2026-08-01).
    **The board carried this entry as "not agreed" until 2026-08-15**, two weeks
    after PR #49 merged the guidance resource, the four rewritten tool
    descriptions and their tests: the implementing PR edited ROADMAP.md but
    never flipped its own entry. It was not alone — **11.4 (PR #46) and 11.5
    (PR #48) had drifted the same way**, one still reading "Next." and one
    "Implemented", and all three were corrected together on 2026-08-15 from the
    merge commits. Recorded rather than quietly fixed, because "the implementing
    PR flips its own entry" exists precisely so the board is true on main the
    moment a PR merges; three consecutive entries missing it makes this a
    process gap rather than an oversight, and the next entry to merge should be
    watched for it. Entry 11.14 amends the shipped guidance rather than
    reopening this one.
    **It was watched, and it drifted again: 11.8 (PR #51) merged on 2026-08-16
    still reading "Implemented on this branch"** — a branch that no longer
    exists — and was corrected here. That is four consecutive entries, so the
    rule is now demonstrably not self-enforcing and the remedy is not more
    diligence. The cheap fix is a CI check: a PR that changes ROADMAP.md and is
    not itself a board-bookkeeping PR should fail while any entry it touches
    lacks a Done mark or a stated reason for not having one. Worth its own
    entry; noted here because this is where the evidence accumulated.
11.8. **Done (PR #51, 2026-08-16)** — E, speech text an agent can segment
    (lane 1, bridge). Found live on 2026-08-03 driving Chrome to a real site.
    `_join_speech` concatenated a sequence's string parts with `""`, so the
    boundaries NVDA knew about were destroyed at the only point they were still
    known. A Windows system-menu item arrives as `("Move", "indisponível", "m")`
    — label, state, accelerator — and reached the agent as `Moveindisponívelm`.
    A desktop icon arrived as `Google Chrome17 de 37`, a list as `Desktoplista`.
    This is not cosmetic: it is ambiguous, and the agent must guess word
    boundaries on **every read**, in whatever language the user runs. In that run
    it also hid the accelerator letters, which were the one-keystroke answer to
    the menu the agent was arrowing through five presses at a time.
    **It hit both modes, differently, which is why it read as noise rather than
    a defect.** Live mode captures at `pre_speechQueued`, further down the
    pipeline, where NVDA has already inserted its own separators — so the same
    utterances arrived *double*-spaced (`Google Chrome  17 de 37`) while silent
    mode, capturing at the `speak()` filter on the raw sequence, got none at all.
    One join, two symptoms, neither of them right. Stripping the parts before
    joining normalises both to a single space.
    Fix: join with a space, dropping whitespace-only parts so no double spaces
    appear. **What makes this entry worth reading is why it survived so long.**
    The suite has a test named `test_adjacent_string_parts_join_without_separators`
    whose whole job was to pin this behaviour — and it was **blind to it**,
    because its fixtures baked the space into the first part (`"hello "`,
    `"world"`), so both joins produced the same string. 379 tests passed against
    the change. The fixtures were unrepresentative of production data in exactly
    the way that mattered, and a test that cannot fail is not coverage. Fixtures
    are now realistic (no trailing spaces) and were verified to fail against the
    old join with the live string. Spec: none needed — a defect fix with its
    guard corrected.
11.9. **E, the round trip is the cost — the settle is a no-op** (lane 2, server).
    **Measured 2026-08-03; the measurement reversed the premise, twice.** The
    session was slow, and the diagnosis started at `SPEECH_FINISHED_SECONDS`:
    both modes settle by an elapsed-time heuristic (spec 0008 removed the spy
    synth, so `exact_finish` is false everywhere), and silent mode appeared to
    pay a full second per read waiting out a synth that never runs. A spike
    shortened it for silent mode. **The numbers say that was wrong.** From the
    bridge transcript, NVDA finishes producing a keystroke's speech **~124 ms**
    after the gesture (`GESTURE windows+d` 09:04:24.078 → last `SPEECH`
    09:04:24.202). An agent's tool round trip measured **~2.64 s**. So the 1 s
    window has *always already expired* by the time `waitForSpeechToFinish`
    arrives: it returns `finished: true` off a stale `_last_time` having observed
    nothing. Controlled: a settle timed against a **deliberately quiet** buffer
    took 8.293 s, and one immediately after real speech took 8.297 s — identical,
    because both returned instantly and the time is all harness. The constant was
    never being paid, so the spike was reverted; only its comment survives, on
    the constant, so the next reader does not re-derive this.
    What is left is larger. **A third of every step's cost buys nothing**: the
    act/settle/listen loop is three round trips (~7.9 s) of which the settle is
    pure waste, and this run spent ~30 calls ≈ 78 s almost entirely on round
    trips rather than on NVDA. Two routes, and they compose: (a) zero-code —
    stop calling the settle, since speech lands 20× faster than the agent can
    ask, and re-read on the rare empty result; (b) let `pressGesture`/`typeText`
    optionally return the speech they caused, collapsing act/settle/listen into
    **one** call (~3× faster), which is 0023's doctrine made cheap instead of
    merely documented. **Both routes need 11.x's `since_index` fix first**, and
    this is what promotes it from nicety to prerequisite: `finished: true`
    already collapses "speech happened and stopped" with "speech never started",
    and today that is masked only by the agent being slower than NVDA. Remove the
    round trips and the mask goes with them. Same shape as 0020/0021/0023 — one
    observable covering two situations, cured by letting the caller say which one
    it is in. Needs a spec conversation; touches the wire.
11.10. **E, how long has the human been mute?** (lane 1, bridge). Found the hard
    way on 2026-08-03: an agent held a **silent** session open while doing
    several minutes of out-of-band shell work, and the user — who cannot hear
    their computer during suppression — sat mute until they hit the panic
    gesture. Twice. The failsafe worked exactly as spec 0008 designed it, and
    that is the good news. The gap is that nothing else did. The session has an
    inactivity watchdog, but it never fired **because the agent was active** — a
    call every few seconds. The watchdog asks *"is the agent still there?"* when
    the question that matters to a suppressed human is *"how long have I been
    unable to hear my machine?"* Those come apart precisely when an agent is busy
    but slow, which after 11.9 we know is the normal case, not an edge one. A
    wall-clock cap on **continuous suppression**, independent of agent activity —
    warn audibly through the announcer at N seconds, lift suppression at M —
    would have interrupted this at a minute. Note it interacts with 11.9: making
    the agent faster shortens every exposure, but does not bound it. Agent-side
    discipline (never hold a silent session across work that does not drive the
    reader) is the immediate mitigation and costs nothing, but it is discipline,
    not a guarantee, and the person it fails is blind and mute at the time. Needs
    a spec conversation.
11.11. **E, a session the agent can hear** (lane 1, bridge). Found live on
    2026-08-03. The agent pressed `NVDA+space` meaning to return to browse mode,
    but the page reload had already restored browse mode, so the toggle entered
    **focus** mode — and the next six `h` presses were typed into a search field
    instead of walking headings. The agent could not tell "no headings here" from
    "the keys went somewhere else" and said so in writing. **The human knew
    instantly: he heard the focus-mode tone.** `browseMode.reportPassThrough`
    plays `focusMode.wav` unless `passThroughAudioIndication` is false, in which
    case NVDA speaks the words instead — so the information exists, in the
    channel this session cannot capture. The gap was **already documented three
    times** (0001 names this exact gesture, `StateResult`'s docstring names it,
    0023 lists it under honest limits) and the prescribed cure — call `getState`
    — is correct and was not used, because after 11.9 a poll costs a full round
    trip to learn one bit NVDA computes in microseconds. What generalises: in a
    silent session **the human hears only the tones and the agent reads only the
    words**, so each is confident and each is missing half. Proposes a membership
    test — a session may change a setting only if the change moves information
    between channels without adding or removing any — plus disclosure of every
    key changed, and reporting (not fixing) the quiet states it must not touch.
    A `setConfig` one-liner is the mitigation available on today's build, no code.
    Spec: [0024-a-session-the-agent-can-hear.md](specs/0024-a-session-the-agent-can-hear.md)
    (drafted 2026-08-03, not agreed).
11.12. **E, one round trip per intention** (lane 2, server + bridge). Implements
    the two routes 11.9 named. 0023's act/settle/listen loop is three round trips
    (~7.9 s) to carry ~124 ms of reader work, and 11.9 measured that one of the
    three observes nothing at all. The maintainer's reframing is the substance:
    **wait ~100 ms after dispatch and return what arrived** — because
    `waitForSpeechToFinish` asks "has speech *stopped*?", which is unanswerable
    (silence before and silence after are the same observable), while a grace
    window asks "has speech *started*?", which is a fact at a stated instant. It
    costs ~4% of a round trip rather than a whole one. Ships: the grace window on
    `pressGesture`/`typeText`; **per-gesture speech bookmarks** so a batch stays
    observable (5 keys go from 5 trips ≈ 13 s to 1 trip + 500 ms, *and* a silent
    key becomes visible instead of inferred); a `getState` snapshot on the result
    for silent effects only — explicitly **not** focus, so 0023's "pre-effect
    focus is wrong by construction" stands; and `announce` riding along, because
    11.10's protection must not be the thing that costs the most. **No `await`
    parameter**: its false answer would conflate not-yet with never, the
    objection that sank `waitForFocus`, and the maintainer's "wait a little and
    query again" leaves the slow case at today's two trips rather than making
    every call ambiguous. Honest risk: 2.6 s was measured, 5–12 s was observed
    hours later, and the gap is unbracketed — the benefit is proportional to a
    number nobody has measured.
    Spec: [0025-one-round-trip-per-intention.md](specs/0025-one-round-trip-per-intention.md)
    (drafted 2026-08-03, not agreed).
11.13. **E, where am I, and what is on the page** (lane 1, bridge + server). Two
    questions the repo has been treating as one. **"Where am I" is already
    solved and this builds nothing for it** — it is `NVDA+Tab`, a gesture whose
    answer is speech, made one round trip by 11.12; 0023 settled that and a
    `whereAmI` tool would be the obvious wrong answer. **"What is on this page"
    has no answer at any usable cost**: line-by-line arrowing is one round trip
    per line, which is where the 2026-08-03 run actually died — it reached the
    results page and never got the three titles. 11.12 does not help, because it
    makes a step cheaper without reducing the number of steps. Proposes
    `getPageSnapshot`, gated on a new `document` capability: the browse-mode
    buffer as lines, roles included, bounded and paginated, with `truncatedBy`
    naming *which* bound bit and `hasDocument: false` distinguished from an empty
    page — 0021's and 0020's lesson applied to a new tool rather than
    rediscovered in it. The 0023 tension resolves on the same test as 11.11:
    browse mode **is** a flat text rendering the user arrows through, so a
    snapshot changes the channel, not the substance. Say-all capture was the more
    faithful design and is deferred, not on principle but because **nobody has
    tested whether say-all advances when no synth runs** — a cheap experiment
    that should happen before this is agreed.
    Spec: [0026-where-am-i-and-what-is-on-the-page.md](specs/0026-where-am-i-and-what-is-on-the-page.md)
    (drafted 2026-08-03, not agreed).
11.14. **Done (PR #55, 2026-08-16)** — E, the guidance never says how to get the
    application in front (server lane). Docs only.
    **Entries 11.14–11.17 all come from one session that nobody on this project
    was sitting at** — an external agent drove a third-party application (acter)
    through the MCP on 2026-08-15 and reported back. That is a different
    evidence tier from every E-finding before it, all of which came from
    checklists run with the maintainer at the keyboard, and it is worth
    recording what it produced: **no bugs.** Five pieces of feedback, every one
    a missing affordance. After 11.5 and 11.7, that is the result worth having.
    Two of the five asks are not entries of their own: `type_text replace: true`
    and the report's "act on trigger" stretch goal are both absorbed by 11.16.
    This entry: nothing in `screenreader://guidance`, the README or any tool
    description says how to put the application under test in the foreground, so
    the run dropped to PowerShell and Win32 `SetForegroundWindow`. The reporting agent's own read is that the scoping is
    correct — it is not a screen reader concern — but that it is the first thing
    any agent needs. 0023's guidance already carries the matching warning
    ("Before you type, know where you are"), and `type_text`'s description
    carries a longer one; both name the hazard and neither names the remedy,
    which is what makes the gap look deliberate rather than missing.
    **The doctrine answer is `press_gesture`**, not PowerShell: a user switches
    windows with alt+tab or the Start menu, so doing it that way is both
    expressible through the MCP and more faithful to what is under test.
    OS-level activation is named as the setup fallback that sits outside the
    tool. Amends the shipped guidance resource plus the README; 11.7 is Done, so
    new scope cannot fold into it. Spec: 0023, amended in the implementing PR —
    no new spec file.
11.15. **E, speech and braille entries carry no time** (both lanes). The run's
    strongest ask. An assertion of the form "X happened promptly after Y" is a
    large fraction of what accessibility testing is, and the run's single most
    valuable measurement — a stop waking a sleeping script in 63 ms — could not
    be made through the MCP at all: the agent read `session-*.log` off the
    reader's disk and diffed timestamps by hand. `getSpeech` returns
    `logPosition`, which places an utterance in the journal's **ordering**;
    recovering wall clock from it costs a `getLog` round trip per entry, and in
    silent mode the journal holds no speech record to land on.
    **The bridge already takes the instant.** `SpeechBuffer.append` calls
    `self._clock.monotonic()` on every append and stores it as a single
    overwritten `_last_time` scalar for the still-speaking heuristic; the change
    is to keep it per entry, in a parallel list beside `_log_positions`. The
    `Clock` port is already injected into `IndexedBuffer`, so braille rides
    along and there is no new port and no new wiring.
    Decided 2026-08-15: **wall clock, not monotonic** — `Clock.time()`, on the
    precedent of `getLogPosition`'s `time` field and for the same reason, since
    a stamp that cannot be joined to `nvda.log` or the transcript loses half its
    value. And the field is **not named for speaking**: live mode hooks
    `pre_speechQueued` (queued for the synth), silent mode
    `filter_speechSequence` (inside `speak()`), and neither is audio — in live
    mode a long utterance ahead of it can put seconds between the stamp and the
    human hearing it. It is the moment the reader **emitted** the utterance,
    which is also the better number for the measurement that motivated it, since
    synth queueing and audio latency belong to the synth and would be noise in a
    responsiveness figure. The two hook points are different pipeline stages, so
    live and silent stamps are not strictly comparable to each other —
    irrelevant at millisecond resolution, recorded so nobody rediscovers it.
    Amends published wire v1 (no external consumers; both implementations
    in-tree and covered by `conformance`). Needs live NVDA, but barely: the
    stamp is taken in a pure domain entity against an injected clock. Spec: none
    yet.
11.16. **E, no way to combine an action with its submit** (server lane). Every
    command in the run cost two round trips (`type_text`, then `press_gesture
    ["enter"]`) at 5–10 s each. **The measured cost is not ours** — 11.4
    established the bridge answers in 0.2–0.5 ms — it is the client model's turn
    time. So this removes model round trips, not transport, and must not be
    written as a latency optimisation or it will be measured against the wrong
    number.
    It is not only throughput: one scenario was **untestable**. A command with a
    1.5 s finish delay always completed before the agent could stop it, and the
    run had to substitute a different command to test stopping at all. A
    sequence with a **per-step delay** (not one interval for the whole batch)
    fixes that class, because the timing is evaluated where the latency is
    0.2 ms rather than where it is 5–10 s.
    Decided 2026-08-15:
    - The step vocabulary must include a **settle** step
      (`waitForSpeechToFinish`), not only a blind `delay`. The guidance says
      "never sleep instead"; a sequence that can only sleep is a machine for
      mass-producing the exact failure 0023 exists to prevent. `delay` is for
      the **application's** known timing, `settle` for the reader's unknown
      latency, and the descriptions must say which is which.
    - A **`waitForSpeech` step subsumes act-on-trigger.** The report's stretch
      ask — "when speech matches X, immediately press Y, evaluated bridge-side
      where the latency isn't" — is just a sequence whose middle step blocks on
      speech; the next step then fires ~0.2 ms later. No new concept, and
      nothing is pushed, so 0021's pull-not-push decision stands untouched. Its
      `found: false` is deliberately not an error, so inside a sequence it
      aborts the remaining steps but must report "the trigger never fired"
      distinctly from "a step failed".
    - **Abort on first failure, with per-step results**, so partial execution is
      legible; and **validate the whole plan against the session's capabilities
      up front**, so a bad plan is rejected before any keystroke is delivered
      rather than discovered halfway through.
    - A **trailing read step is in scope**, so one call can be the whole
      documented act/settle/listen loop — three model turns become one. A
      primitive that cannot express the loop 0023 teaches will be used without
      it.
    - **Server-side composition over the existing tools**: no wire change, no
      bridge change, no add-on rebuild, no v1 amendment. Server→bridge is
      0.2–0.5 ms, so a server-side loop hits a 1.5 s application timer with
      orders of magnitude to spare. Classified `mutates_reader` so 11.3
      withholds it; no capability of its own.
    Also retires the report's smallest ask, `type_text replace: true` — select
    all, delete, type is a sequence. Spec: none yet.
11.17. **E, a toggle with no setter** (both lanes). `NVDA+space` is a toggle and
    there is no idempotent way to say "be in browse mode", so automation must
    `getState`, branch, press, then re-check — and a wrong guess flips the wrong
    way and silently corrupts everything after it. The run demonstrated the
    consequence rather than describing it: an agent that assumed auto-switching
    got wrong answers and blamed the application, which is 0023's failure shape
    reached independently by someone who had never read 0023.
    The ask was `set_browse_mode`. **Rejected in favour of `setState` mirroring
    `getState`** — same struct, fields optional, set the ones present — because
    0005 chose the **capability** as the unit of reader difference on purpose
    ("JAWS lacking braille, TalkBack lacking config"): a reader without these
    toggles declines `state`, the tool never appears, and the server carries no
    reader conditional either way. A per-toggle catalog announced in `hello` was
    considered and dropped as parallel machinery for a reader that does not
    exist yet.
    What fixes the bug is that the compare-and-set happens **inside NVDA** —
    read `treeInterceptor.passThrough`, act only if it differs — so there is no
    window between the read and the press, and the operation is idempotent by
    construction rather than by the caller's care.
    One asymmetry, and it is exactly the toggle that was asked for:
    `browseMode`'s **set-domain is narrower than its get-domain**. `"none"`
    means the focus has no `treeInterceptor` at all, which cannot be conjured,
    so setting it is nonsense and must be rejected outright; and even within
    `{browse, focus}` the set cannot succeed when the focus is not a browsable
    document. That case has to say the specific thing — *the focused object is
    not a browsable document* — rather than return a bare failure or a silent
    no-op, or the agent goes looking in the wrong component again. The tri-state
    was chosen over a nullable bool for this same reason and the setter must
    honour it. `speechMode`, `sleepMode` and `inputHelp` are symmetric.
    Classified `mutates_reader` for 11.3. Amends published wire v1. Needs live
    NVDA. Spec: none yet.
12. F, packaging/release — split into two entries (agreed 2026-07-22), because
    the bridge's release path is decidable now while the server's distribution
    still has open questions from [spec 0005](specs/0005-multi-reader-direction.md).
    Spec: [0012](specs/0012-packaging-and-release.md) (12a).
    - **12a** — **Done (PR #25, 2026-07-22)**: the per-component tagging scheme
      shared by every component (`<component>-v<semver>`, version read from the
      component's own manifest and verified against the tag), plus the bridge's
      release workflow (tag `nvda-bridge-v*` → draft GitHub release carrying the
      `.nvda-addon`), the path-filtered PR add-on build, and the PR comment
      linking it. `ci.yml`'s gate jobs stay unconditional and unchanged.
    - **12b** — server distribution. Spec: none yet → specify when reached.
      Scope sketch: RFC 0001 milestone 7, plus what is left of spec 0005's
      decision list: umbrella Windows installer vs per-channel-only distribution
      (NVDA add-on store stays canonical for the add-on), an `.mcpb` bundle for
      Claude Desktop users, and targets beyond Windows amd64. The
      **implementation language is no longer open** — spec 0013 decided Go at
      session D and PyInstaller is off the table — and entry 10c already delivered
      the `server-v*` release path 12a reserved the namespace for: a tag builds
      the binary, runs it to check its version against the tag, and publishes a
      draft release.

## Out-of-band work (not board entries)

Changes that no entry called for, recorded so the board is not silently
incomplete:

- **PR #44, 2026-07-29** — one definition of "green". `uv run poe ci` runs
  everything CI runs, in CI's order, from the repo root; `uv run poe doctor`
  checks the machine can work the repo and **gates every other task**, because a
  broken toolchain makes passing and failing tests equally uninformative. Also
  quarantined the live-NVDA tests behind `poe live`: they drive the developer's
  real screen reader, were harmless only by accident (they skip when nothing is
  listening), and took over a blind maintainer's machine mid-task twice before
  being marked `live_nvda` and excluded by default.

- **2026-07-31** — the lint gate, and CI actually calling it. Ruff's rule set is
  now **chosen** in all three configs rather than inherited from whatever
  version is installed; the whole tree (179 files) was brought under it; and
  `ruff format --check` — the half that catches indentation, and the half that
  was missing — runs in `ci`. That gap is why PR #46 could add a dozen
  space-indented files to a tab repo without a single gate objecting, and the
  dev scripts turned out to be linted by *nothing*, falling between `shared/`
  and `bridges/nvda/`.

  The same PR made `.github/workflows/ci.yml` stop duplicating commands: each
  job now installs a toolchain and calls one task (`poe ci-shared`, `ci-server`,
  `ci-bridge`, `ci-conformance`). Two hand-maintained definitions of "green" had
  drifted in both directions — `poe ci` ran a lint task the workflow did not,
  while **staticcheck and the Linux build existed only in the workflow**, so no
  developer could run them. What made the unification possible was splitting
  `poe dev` (asks whether *this workstation* is fit: Go, ripgrep, intact venvs,
  a fresh server binary) from `poe ci` (does not, because a runner is rebuilt
  from the workflow every time and cannot have drifted). Those machine checks
  were the blocker: the `shared` job installs uv and nothing else, so the
  required `go` and `rg` aborted it before a single test ran.

## Principles — **Decided**

- PRs are short: one component + its port(s) + unit tests; nothing lands
  untested. Session B's split into PRs #3–#7 is the template — a "session" is
  a context boundary, not a PR size.
- Spec before code: every entry not grandfathered above is implemented against
  a spec agreed in conversation before any implementation is written, and the
  spec includes the class/file layout (roles + collaborators) so the
  decomposition is caught in review, not after code. The spec file rides in the
  implementing PR's branch and merges with it. If implementation forces a spec
  amendment, the amendment rides in the same PR.
- Items marked **Decided** here, in AGENTS.md, or in a spec's agreed sections
  are settled. Do not relitigate them silently; to change one, propose it
  explicitly and update the doc in the same PR that implements the change.
