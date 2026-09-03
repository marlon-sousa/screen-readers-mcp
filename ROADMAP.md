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
- **Lanes:** lane 1 (NVDA bridge), lane 2 (server) and **lane 3 (the macOS
  VoiceOver bridge)** may run in parallel — at most one open PR per lane, never
  two in the same lane. Order within a lane is strict. (Entries 5 and 6 predate
  this rule and are grandfathered; from here on it holds.)
  - **Lane 3 was opened on 2026-08-28 — Decided.** Spec 0041's spike and spec
    0043's direction RFC were both taken with no board number precisely because
    "where does a VoiceOver bridge sit" was unanswered. It is answered: a third
    lane, parallel to the other two, because a VoiceOver bridge is neither the
    NVDA bridge nor the server and blocks on neither.
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
below. **Open as of 2026-08-29**:
11.18, 11.23, 11.37 —
**three entries**, none of which has a spec yet and one of which (11.18) is on
hold. 11.37 is not on anyone's critical path and is recorded rather than
scheduled, so the lane has no head that anything waits on. **11.35 and 11.36
are Done**, shipped together on 2026-08-29 (specs 0044 and 0045) and taken ahead
of the other two because lane 3 blocked on both while neither 11.18 nor 11.23
blocks on anything — the reprioritisation this board requires to be made
explicitly, the way 11.22 was taken before 11.6. Both were lane-2-shaped work
that existed for lane 3's benefit: 11.35 made the local endpoint mean something
off Windows, and 11.36 renamed the wire module before a third binding was
written against the old name. **Lane 3's two cross-lane dependencies are
therefore both cleared**, and 13.3 and 13.4 wait on nothing but their own lane. (11.28 is Done: the flaky roundtrip now reports where
its budget went, spec 0039 — the flake itself is not fixed, and that is the
claim. 11.31 was opened and closed in one documentation PR and never joined this
list: the four READMEs had drifted behind the shipped surface, one of them still
teaching a rule spec 0022 retired.) (11.29 and 11.30
are both Done, shipped together in one PR:
the inclusive left edge, spec 0037, and attendance you can ask for again, spec
0038) (11.16 is Done: `run_sequence`, spec 0036; **11.13 is Done**:
the document snapshot, spec 0026, which closed the server lane's head; **11.29 and 11.30 were
both opened by 11.16's live run** — 11.29 a pre-existing bridge off-by-one it made
reachable, 11.30 a fact an agent is told once and can never ask for again) (11.26 and 11.27 were both opened by the 11.11/11.17 live run,
and both are now Done: 11.26 in PR #71 and 11.27 in **PR #72**) (11.22-11.24 opened by the second external run,
[0030](specs/0030-the-second-external-run.md)). **11.22 is Done** (PR #65),
taken ahead of the lane head; see the reprioritisation note below. It answered
0030 ask 1b and deliberately left 11.6 open — the two shared a symptom and were
different failures. **11.6 is now Done too** (2026-08-19), and 11.22 is why it
could be: publishing the surface as a document removed the scarcity three of
11.6's four options existed to answer. **11.24 is Done**: its (a) half
closed with 11.6 as an instance of a rule rather than a spelling, and (b) — the
ack on a riding announcement — closed on 2026-08-20 (PR #69). **11.21 is Done** in the same PR
that opened it. 11.3 was
taken out of the queue on 2026-08-18 and is on hold; see its entry. **11.12 and
11.9 are Done** (PR #64): 11.12 implemented both routes 11.9 named, which is
what 11.9 existed to have built, so the pair closes together. Of the external run's four, 11.14 and 11.15 are settled. **Spec 0029
is complete**: 11.19 (PR #61) made the persona exist and travel, and 11.20
gave the reader its own document, so an agent now declares a stance and is told
what that stance means on the reader in front of it.

Their order is **not** simply the numbering. **11.3 is on hold as of
2026-08-18** — it had been drafted-but-unagreed since 2026-07-29 and passed over
four times, and the fifth pass was made a decision rather than another silence.
**11.11 and 11.17 closed together on 2026-08-20** (PR #70) — the pair the board
required to be decided in one conversation, and they were — so lane 1 has no open
entry at all. **11.6 closed on 2026-08-19**, taking 11.24(a) with it, so the
server lane's head is **11.13**, and **11.13 closed on 2026-08-22**, so both
lanes are open again.

**11.22 is taken before 11.6, deliberately, on 2026-08-18** — the
reprioritisation this section requires to be made explicitly, the way 11.4 was
taken before 11.3. Three reasons, all recorded in
[0031](specs/0031-the-tools-describe-themselves.md) Part 1. 11.6 is by its own
entry "smaller and no longer urgent" and needs a spec conversation that reopens a
decision spec 0013 made deliberately, with four options still on the table. 11.22
is independent of that conversation and of every client's behaviour, so it can
ship without prejudging any of the four. And 11.6's own 2026-08-18 corroboration
is a failure it cannot explain — an agent that connected cleanly, without a
redeploy, and still saw nothing — which is precisely the half 11.22 answers.

Three pairings matter more than the numbers:

- **11.9 and 11.12** are one topic — 11.9 is the analysis, 11.12 the remedy.
- **11.11 and 11.17** are one gesture, from two sessions, with complementary
  remedies. **Both Done (PR #70, 2026-08-20)**, decided in one conversation and
  shipped in one PR, which is what the pairing was for. See either entry.
- **11.19 and 11.20** are two halves of personas, sharing **one spec**,
  [0029](specs/0029-connecting-as-somebody.md), because the split between them
  *is* the design. **Re-scoped 2026-08-17**: the halves are no longer *server*
  and *reader* but **mechanism** and **document** — 11.19 makes the persona
  exist, travel and be recorded; 11.20 gives the reader its own document. Both
  touch both lanes and both need an add-on rebuild, so neither is a
  server-only ship. **11.19 shipped in PR #61**; 11.20 is what is left, and it
  now carries more than its original scope — after TalkBack disposed of a
  server-owned vocabulary, the ordinary vocabulary ITSELF is in the bridge's
  document, not only the list of what falls outside it.

Anything taken out of numeric order is a reprioritisation to make explicitly, the
way 11.4 was taken before 11.3.

**Check the open PRs before claiming a number.** On 2026-08-15, PR #54 numbered
the external-run entries 11.8–11.11 without doing so, and two PRs open since
2026-08-03 had already taken that range — #51 (11.8–11.10) and #52, stacked on
it (11.11–11.13, specs 0024–0026). They had precedence, so the external-run
entries were renumbered to 11.14–11.17 on 2026-08-16 rather than the other way
round, and #51 could not merge at all until that was untangled. Nearly every PR
edits this file, so **a number that is free on main is not necessarily free**.
The next free board number is **11.38** in the convergence series and **13.34**
in lane 3, and the next free spec number is **0057**. Spec **0056** was spent on
2026-09-03 by **13.24, 13.32 and 13.33 TAKEN TOGETHER** -- three failure points on
one setting, the voice a session leaves selected on somebody's machine, sharing
one design question about what a session may do with a voice identifier that does
not resolve. Marlon approved the bundle that day, and **this line moved in the
same commit**; the three entries consumed no new board number between them.
**That is a precedent worth naming rather than a one-off**: entries bundle when
they share a DECISION, not merely a file -- answering the same question three
times in three PRs risks three answers. Board numbers **13.32** and
**13.33** were spent on 2026-09-03 by 13.31's own live checklist -- a restore
script that does not restore, and a launcher that dies when it asks a human a
question -- and neither took a spec number of its own at the time, the 13.11
precedent; they took 0056's when they were bundled. Spec **0055** and board
number **13.31** were spent on 2026-09-03 by one question Marlon asked of the
AppleScript inventory -- if a user cannot type a command name, why should we have
to -- and this line moved in the same commit. **13.30 stands reserved** by 13.29
for the stamp measurement and has no entry of its own yet, which is why this entry
took 13.31. Spec **0054** and board
number **13.29** were spent on 2026-09-03 by a field report from an agent driving
this bridge against a real application -- every application chord had been silently
dead since 13.25 -- and this line moved in the same commit. Board number **13.28** was
spent on 2026-09-02 by 13.26's own live run, which removed a feature that entry had
already implemented -- writing the VoiceOver modifier raises a modal dialog on a
running reader -- and this line moved in the same commit. Spec **0053** was spent on
2026-09-02 by 13.26, which grew from one question about the AppleScript switch
into the frame for the whole handshake; this line moved in the same commit. Spec
**0052** and board
numbers **13.25**, **13.26** and **13.27** were spent on 2026-09-02: the first by
a question Marlon asked of the field report -- why a VoiceOver gesture is a
command name where an NVDA one is `NVDA+t` -- and the other two by what specifying
its answer turned up, a handshake that need not depend on the AppleScript switch
and a guidance table that names the release's bindings rather than the machine's.
This line moved in the same commit. Board numbers **13.23** and
**13.24** were spent on 2026-09-02 by two findings from 13.20's own live
checklist -- a bridge that died of SIGPIPE rather than tearing down, and a voice
identifier that is used without ever being resolved -- and neither took a spec
number of its own, the 13.11 precedent. Spec **0051** and board number **13.22**
were spent on 2026-09-01 by an agent that could not press two ordinary keys
together, and this line moved in the same commit. Board number **13.21** was
spent on 2026-09-01 by a defect found while using the bridge -- a lifted silence
cap that never re-armed -- and took **no spec number of its own**: its spec is
[spec 0050](specs/0050-the-handshake-climbs-the-ladder.md) §8, which is the 13.11
precedent. Spec **0050** and board
number **13.20** were spent on 2026-09-01 by the finding that `connect_reader`
established sessions on a machine that could not capture, and this line moved in
the same commit. Spec **0049** was spent on
2026-08-31 by 13.19, and this line moved in the same commit. Board numbers
**13.18** and **13.19** were spent on 2026-08-31 by two findings that came out of 13.17's live
run -- how much of an announcement a session can capture, and the discovery that
an unmodified letter key has no notation -- and this line moved in the same
commit. Spec **0048** was spent on
2026-08-31 by 13.17, and this line moved in the same commit. Board numbers **13.15**,
**13.16** and **13.17** were spent on 2026-08-31 by two findings that came out of 13.11's live
run — the voice substitution, whether `journal.plist` narrows this lane's "no reader
log" claim, and the discovery that this bridge cannot press a chord at all — and
this line moved in the same commit. Board number **13.14** was
spent on 2026-08-30 when the control dialog was split out of 13.10, and this line
was not moved with it -- corrected by 13.11, which spent no number of its own and
found the gap while looking for one. **13.11 took no spec number either**: its
spec is 0046's 13.11 section, which already existed, and its amendments went in
there. Spec **0047** and board
number **13.13** were spent on 2026-08-29 by the measurement that came out of
asking whether the capture voice could be selected without a human; it moved this
line in the same commit that spent both. Spec **0046** was spent on
2026-08-29 by **13.1**, lane 3's implementation spec, which also took board
number **13.12** for the measurement it deferred, and moved this line in the same
commit that spent both. Specs **0044** and **0045** were spent on 2026-08-29 by
11.35 and 11.36, which shipped in one PR and moved this line in the same commit. Three
unmerged branches account for the rest of the gap, which is exactly the case
the paragraph above describes: 11.32, 11.33 and spec 0040 were taken on
2026-08-27 by the observation stream, on the branch that also re-cut 0017; spec
**0041** was taken the same day by the VoiceOver capture spike, on its own branch
and with **no board number**, because where a VoiceOver bridge sits is a lane
question the board has not answered and claiming a number for it would decide
that by accident; spec **0043** was taken on 2026-08-28 by that spike's
direction RFC, on the same branch and likewise with **no board number**, for the
same reason; and 11.34 with spec 0042 were taken on 2026-08-28 by the macOS
host work, which moved this line in the same commit that spent them. (11.22–11.24 and spec 0030 were taken by the second external run on
2026-08-18; spec 0031 by 11.22's own spec; spec 0032 by 11.10 on 2026-08-19;
11.25 by the silence-cap fix on 2026-08-20, which is the
instance that proves the rule below: PR #68 took the number and left this line
reading 11.25, so the next session was told a number that was already spent, and
11.18 gained a second kind of evidence. Spec 0033 by 11.17 on 2026-08-20, taken
on a branch before it merged — which is precisely the case the paragraph above
says to check for; it merged in PR #70. 11.26–11.27 and specs 0034–0035 were
taken on 2026-08-21 by the two findings of that PR's live run. 11.27 and spec 0035 spent a day
in exactly that state — drafted on a branch, absent from `specs/` on main — and
**both landed in PR #72**, so the warning stands as a worked example rather than
as a live hazard.
11.28 was taken on 2026-08-21 by the AGENTS.md split, which opened it for a
flaky test the split's own gate run surfaced and deliberately did not fix — no
spec number went with it, since it has no spec yet.
11.31 was taken on 2026-08-27 by the README audit, and no spec number with it
for the same reason: a correction to documentation against the shipped surface
decides nothing. It moved this line to 11.32 in the same commit that spent the
number, which is the habit the paragraph above is asking for.
Spec 0039 was then taken the same day by 11.28, on that entry's branch before it
merges — again the case the paragraph above says to check for — and this line
moved to 0040 with it, in the same commit.
Spec 0036 was taken on 2026-08-22 by 11.16, drafted on that entry's branch
before it merges — which is again the case the paragraph above says to check
for.
11.29 and 11.30 were both taken on 2026-08-22 by the conversation following
11.16's live run, and **this line was not updated with them** — it still read
11.29 on 2026-08-23, when a session asking "what is next?" was handed a number
already spent for the second time. Corrected by a direct push to main.
Specs 0037 and 0038 were then taken the same day by those two entries, on the
branch that implements both — again the case the paragraph above says to check
for — and this line moved to 0039 with them, in the same commit, which is the
habit the paragraph is asking for.
This line is the one the paragraph above tells people to trust, so it is updated
by whichever PR consumes a number.)

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

## Status board — lane 3: the macOS VoiceOver bridge

**Lane 3 was opened on 2026-08-28** by the rule under "How to use this board";
its board was written on 2026-08-29. Its head is **13.12**: **13.1 through 13.11
are Done**, so the lane now has a declared bridge the tooling can see, a capture
voice, the wire contract's Swift binding, a bridge that **listens**, one that
**hears** -- an agent can read back what the reader said -- one that can make the
reader **quiet** (silent sessions are established rather than refused, the bridge
selects the capture voice itself and puts the user's own back on every teardown
path, and the silence it holds is a **lease** that expires if the bridge dies,
which is hard invariant 3 in its macOS form) and, since 13.7 and 13.8, one that
can **drive** it, by both halves of input: `pressGesture` dispatches VoiceOver's
own English command names through the reader itself, and `typeText` synthesizes
keystrokes into whatever holds focus. Since 13.9 it also answers **where the
agent is**: `getFocusInfo` reads the accessibility tree where the grant exists
and VoiceOver's own cursor where it does not, and **never asks for the grant to
do better**. And since 13.10 it can **talk to the person at the machine**:
`announce` speaks with the bridge's OWN synthesizer, outside VoiceOver entirely,
so it is audible in the one mode where the reader is mute -- which is what makes
`pressGesture`'s and `typeText`'s `announce` field honourable at all -- and
`askUser` / `waitForUserReply` put a question in front of them and collect the
answer later, without ever blocking the thread that renews the silence lease.
And since 13.11 it **says what it is** -- `guidance` serves this reader's own
account of the stance a session declared, written against a vocabulary that
already worked, which is why that capability came last -- and it is **packaged**:
`poe build` assembles the `.app`, `poe conformance` drives the real Go binary
against the real **Swift** bridge as well as the real Python one, and the reader
ships in `server/config/defaults.json` so no agent has to configure one.

So `hello` announces `speech`, `gestures`, `typing`, `focus`, `interact` and
`guidance`, and their sixteen commands answer. **Six of the contract's eleven
capability groups, and the five it omits -- braille, state, config, log,
document -- are absent from the READER rather than unimplemented here.** That is
the capability gate visibly doing its job, and it is the first bridge in the repo
where it is visible at all: the NVDA one announces every group, so its
conformance run has no unannounced capability to exercise and this one's does.

**The two halves stay apart because they cost different permissions, and that is
the lane's one design lever.** Pressing a command NAME is an AppleEvent; typing,
and pressing a CHORD, are Accessibility -- so **the Accessibility grant is
requested by the two commands that post a system event and from nowhere else in
the bridge**, which makes *"a session that presses only the reader's COMMAND
NAMES and reads speech never triggered an Accessibility request"* a statement the
test suite checks rather than one the documentation asserts. **That sentence lost
one word at 13.17 and kept its point**: until then `pressGesture` took only
command names, and the bridge could not send Command-L at all. Windows has no equivalent gate, so lane 1 has no analogue
and there was nothing to copy. **13.9 was the entry that could have quietly spent
that lever and did not** -- focus wants the same grant, so it reads whether the
grant is held through a one-method adapter seam that shows no dialog, and the
object it holds cannot request anything. 13.10 did not spend it either: the
three commands it adds talk to a PERSON rather than to the system, and the
counting-broker scenario drives all of them past a broker that is asked nothing.
And since 13.17 it can press a **chord**: `pressGesture` takes keystrokes as well
as command names -- `command+l`, which is how anybody opens a location bar and
which this bridge simply could not send through four entries, because a true
measurement about the reader's modifier commands had been generalised into a
false claim about the platform. **13.17's own live run then found two more
things, which are 13.18 and 13.19**: an announcement on this reader is TWO
utterances whose gap is the audio in a live session, so a batched press captures
the role and loses the text; and an unmodified letter key -- `h` with Quick Nav
on -- has no notation at all, because 13.17 made the `+` the discriminator. The keycode comes from the layout that is
actually active, read through Text Input Services, so it presses the right key on
a Brazilian keyboard and fails BY NAME on a character the layout cannot reach.
The next step is **13.12**, the measurement that asks whether VoiceOver can be
told what mode it is in -- and after it **13.14**, the control dialog, which
needed 13.11's live tier and now has it.

**The control dialog is NOT part of 13.10 any more, and that is a decision worth
reading before anyone re-opens it.** Taken by Marlon on 2026-08-30, while 13.10
was being implemented: *wait until you can control VoiceOver, so that you can
navigate through your own GUI by yourself, and keep using the config file until
then.* Every other entry in this lane is checkable by driving the reader and
reading back what it said; a window is only checkable by eye, unless the thing
driving it is the reader this bridge already talks to. So the dialog is **13.14**,
after the live tier exists, and until then a bridge is started by
`BridgeListener` -- which now reads the same persisted settings the dialog will
edit.

The lane rests on two documents that carry **no board number**, each taken
out-of-band for the reason it states: [spec
0041](specs/0041-can-voiceover-say-what-it-said.md), the research spike that
inverted "spec before code" because VoiceOver has no source to read, no plugin
API and no published extension point for speech; and [spec
0043](specs/0043-the-voiceover-bridge-is-one-swift-bundle.md), the direction RFC
— the VoiceOver analogue of [spec 0005](specs/0005-multi-reader-direction.md) —
written against that spike's measurements rather than against Apple's
documentation. Every entry below traces to one of them.

**The numbering starts at 13, not 12.** 11.x is the convergence series, up to
11.35, and 12 is lane 1's packaging entry. A fresh block is cheaper than the
collision this board has already had twice.

**Two dependencies cross lanes, and both are lane-2 entries taken first —
both now Done (2026-08-29), so nothing in this lane waits on lane 2 any more.**
**13.3 needed 11.36**, the wire module's rename to `screenreader_wire`, because
13.3 is where the third binding gets written and renaming after it costs the
rename twice; the module is now `screenreader_wire` and the Swift binding can be
written against the name it will keep. **13.4 needed 11.35**, the local endpoint
resolving per platform — a named pipe on Windows, a Unix domain socket on POSIX
— so a bridge asks for "the local endpoint" and the leaf decides what that
means; the server now dials one, `specs/wire/v1/protocol.md` §1 states where it
lives, and a Go integration scenario establishes a session over a real socket on
macOS. Neither added a transport and neither changed the wire shape. **13.1 and
13.2 waited for nothing** in any case, so the lanes run parallel as the lane
rule intends.

13.1. **The implementation spec** (lane 3; a conversation, not code). The first
    entry, and the largest single piece of thinking in the lane: spec 0043
    settled *shape and language* and deliberately gave **no class/file layout**,
    because it adds no production class. This entry writes the layout in full —
    every class, its role (port / controller / entity / adapter, or a named
    supporting construct), and its collaborators — which is the repo's review
    gate for the decomposition itself.
    **Four of spec 0043's six open questions were answered in conversation on
    2026-08-29** and are recorded in that spec rather than here: Swift for both
    halves, the rename to `screenreader_wire` (now entry 11.36), spec 0005's
    split trigger declined so the repo stays a monorepo, and the local
    endpoint's shape (11.35). **Three remain for this entry**, each because it
    changes the layout rather than the code inside it:
    (a) **which capabilities a VoiceOver bridge advertises**, given that the
    capability gate already makes a partial bridge a first-class citizen rather
    than a degraded one (spec 0013);
    (b) **braille** — VoiceOver's AppleScript exposes none at all, the braille
    window having exactly one property, `enabled`, so the honest answer is
    likely that the capability is *absent from the reader*, not unimplemented.
    Near self-answering, and left here rather than pre-empted because it decides
    whether a `BrailleSource` port exists at all;
    (c) **what the live checklist for this lane looks like**, given that
    VoiceOver crashes on the maintainer's machine as routine weather — five
    reports on 2026-08-28 alone, before the spike started. `focus`'s two
    cursors are the fourth open question and belong to 13.9, where a live reader
    can settle them.
    **All three were answered on 2026-08-29**, and two of them moved after the
    macOS host was measured rather than reasoned about: VoiceOver emits no
    diagnostic log of its own (52 unified-log records in an hour, every one from
    a framework it links), focus has three routes of which the obvious
    system-wide one fails, and its 45 toggles are richly drivable while almost
    none is readable — the exceptions, found in an undocumented `local.plist`,
    are recorded in the spec and do not add up to an answerable `getState`. The capability set is **speech, gestures, typing, focus,
    interact, guidance** — six of eleven — and it is announced one entry at a
    time, so the gate always describes what works.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md). Done (PR #82, 2026-08-29).
13.2. **The bridge the tooling can see** (lane 3). Promotes
    `spikes/voiceover-capture/provider/` to `bridges/voiceover/` — spec 0043
    keeps it deliberately, because it is not a sketch but a working
    `AVSpeechSynthesisProviderAudioUnit` carrying six fixes that each cost a
    live round against a real reader to find, none of them recoverable from
    documentation. Adds `Package.swift` and the
    `[tool.screen-readers-mcp.bridge]` declaration that [spec
    0042](specs/0042-the-server-is-everywhere-a-bridge-is-somewhere.md) requires,
    with its three tiers and their own commands, so the doctor and `poe bridges`
    see a second bridge with no central list edited anywhere. Deletes the
    disposable half of the spike — the AppleScript driver and the keyboard script
    have done their job now that their findings are written down —
    and keeps `VoiceOver.sdef`, which is the reference this repo otherwise does
    not have. **Amended 2026-08-29 by 13.1: the probe is KEPT too**, as
    `Sources/CaptureProbe/`, because it is what answers "is the capture voice
    published?" on the live checklist, and a checklist dependency is versioned
    rather than improvised (the 2026-08-22 rule).
    **The extension is decomposed, not promoted as-is**, and gains its first unit
    tests. The spike's one audio-unit class did all four of its layers at once —
    input, processing, audio output, text output — and being realtime is not a
    licence to leave it that way: Swift's whole-module optimization inlines across
    files, `final` types dispatch statically, and the no-allocation/no-blocking
    rule applies to **one function**, the render block. So the extension becomes
    its own small hexagon with its own ports, and the six fixes that each cost a
    live round against a real reader become assertions rather than comments —
    which is the reason spec 0043 kept the code and not only the measurements.
    Until this entry lands the spike must stay under `spikes/`: `bridges/` is
    scanned by the tooling, and a directory there without a declaration is
    reported as a bridge nobody declared.
    Verified by the doctor itself — two bridges selected on macOS, NVDA's `live`
    tier skipped with NVDA's own reason, VoiceOver's tiers running — and by the
    mirror of that on Windows.
    **Two layout amendments rode in with the code**, both recorded in spec 0046
    with their why: `Adapters/CaptureEventLine.swift` was added, because the two
    sinks emitting the SAME bytes is what makes them interchangeable when the
    sandbox denies one of them, and a property held by two copies of a function
    lasts until somebody edits one of them; and the extension stub is
    `Stub.swift` rather than `main.swift`, because SwiftPM identifies any
    `main.swift` as an executable target while an `.appex`'s entry point is
    `_NSExtensionMain`.
    **Verified against the pre-refactor code, not only against its own tests.**
    The old spike's probe was rebuilt from git and interleaved with the new one,
    five runs each on the same machine within the same minute: added latency
    0.207--0.231 s before, 0.219--0.237 s after, byte-identical audio and zero
    contention drops on both. Two costs were found by measuring and fixed --
    the first `AVSpeechSynthesisVoice(language:)` in a process costs ~150 ms
    (so `warmUp()` pays it at construction rather than on the first utterance
    after each of the system's free relaunches), and the full voice list is now
    taken as an autoclosure so the common path never enumerates it.
    **The doctor gained a distinction it did not have**, found by this entry's
    own tier declaration: a tool that cannot be asked its version at all is not
    the same as one whose version cannot be ordered. `codesign --version` is an
    unrecognised option that exits 2, so the doctor reported a perfectly good
    codesign as "present, but would not report a version" — a warning about the
    doctor wearing the clothes of a warning about the machine. `Tool` now carries
    `version_argv`, which also retires the hard-coded `go version` special case.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md). Done (PR #82, 2026-08-29). Done (PR #82, 2026-08-29).
13.3. **The wire contract's second binding** (lane 3; **needs 11.36**). Swift
    envelope and
    per-command codecs, written against
    [`specs/wire/v1/schema.json`](specs/wire/v1/schema.json) — the contract, not
    the code, which is exactly the cost spec 0005 anticipated when it said what
    is shared between implementations is the contract. Extends
    `scripts/drift.py` so the Swift binding cannot fall silently behind the
    schema the way nothing else in this repo is permitted to; no language server
    crosses the Go↔Python boundary and none will cross this one either, so the
    schema is the only index the three bindings share.
    **JSON-lines framing is NOT here**, contrary to this entry's original
    wording: spec 0046's layout puts it in `JsonLinesChannel`, an adapter, for
    the same reason it is one in the NVDA bridge. It rides with 13.4.
    **The binding renders the WHOLE contract** — 26 commands, 52 shapes — rather
    than the six capabilities this bridge advertises, because binding the subset
    would give the drift gate an exception list and an exception list is the
    thing that goes stale. Each unimplemented command's file says in its header
    that this reader cannot answer it, and why.
    **The gate needs no Swift toolchain**, deliberately: `scripts/swift_wire_binding.py`
    READS the source rather than building it, so `gate-swift` runs in the Windows
    `shared` CI job — which is where a change to the contract finds out it left
    the Swift rendering behind, instead of learning it later on the one host the
    binding is edited on. It raises rather than skips anything it cannot parse.
    Verified by mutation, not by assertion: nine deliberate drifts — a changed
    default, a lost field, an invented field, a missing command, a renamed
    vocabulary value, a required field given a default, a changed type, a bumped
    protocol version, and a `public typealias` (the re-export facade the repo
    bans) — each failed the gate with a message naming the file and the field.
    **`schema.json` now publishes defaults**, and that was found rather than
    planned: §7.2 of the contract has said "defaults live in `schema.json`" since
    v1, and they did not. `required` says a field may be absent and never said
    what absent MEANS, so a binding author reading only the published contract —
    the whole point of publishing it — could not know `graceMs` is 100, and the
    gate could not check the twenty-odd defaults the Swift source now carries.
    They are JSON Schema `default` annotations, which validators ignore, so no
    validation changed and `go generate` stayed a no-op.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md), whose
    13.3 section carries the six layout amendments this made, each with its why.
    Done (2026-08-30).
13.4. **Done** -- **Channel and session** (lane 3; **needs 11.35**). The bridge LISTENS on
    the local endpoint 11.35 taught the server to dial — a Unix domain socket on
    macOS, reached by the same bare name a Windows bridge answers on a pipe —
    with loopback TCP as the alternative the dialog selects, mirroring the
    Windows split rather than copying its mechanism. The Transport seam and its
    endpoint leaf, `JsonLinesChannel`, and the `Session` controller —
    handshake announcing `reader` as VoiceOver with its capability set, the
    command-handler registry, the heartbeat and inactivity watchdogs, and a
    teardown with the macOS form of hard invariant 3 in it. `hello`, `ping`,
    `echo`, `bye`. Headless, the analogue of lane 1's 7a/7b.
    **This is the first entry at which the Go server can connect to a VoiceOver
    bridge at all**, and it is the only one in the lane that depends on 11.35.
    **Proven against the kernel, not only against a fake.** The listener's three
    obligations are unit-tested against a fake binder because their ORDER is the
    contract, and then a real client -- built from the raw socket API, so a round
    trip is not our own code on both ends -- dials the derived path, handshakes,
    echoes and says goodbye; a stale socket file left by a "crash" is replaced
    rather than fatal; stopping unlinks it; and a second session is accepted after
    the first. The loopback alternative gets the same scenario, which is also the
    only place its leaf runs at all.
    **Proven against the real Go server, not only against a Swift client.** With
    `Sources/BridgeListener/` -- a versioned launcher, because the dialog that
    will start the bridge is 13.14 and a check's dependencies are versioned
    rather than improvised -- the shipped `screenreader-mcp` binary was pointed at
    `local:voiceoverMcpBridge` and: `list_readers` reported the endpoint
    **listening**, `connect_reader` completed the handshake and carried back
    `reader=voiceover`, `readerVersion=macOS 15.0.0`, `capabilities=[]`, the log
    path and `bridgeVersion`, `status` and `screenreader://info` agreed with it,
    `disconnect_reader` closed it, and the bridge's transcript recorded SESSION
    OPEN and SESSION CLOSE reason=client-bye. The MCP driver for that run was ad
    hoc; making it a versioned scenario belongs to 13.11 with the rest of the live
    run.
    **`hello` announces NO capabilities, and that is the entry working as
    designed** -- spec 0046 says the six arrive one at a time so the gate always
    describes what works, and at 13.4 the session exists and the reader edge does
    not. **A silent session is REFUSED until 13.6**: `silent` is a promise about a
    human's ears, nothing here can keep any part of it, and a session that
    reported `mode: silent` while the machine talked normally would be the exact
    failure the capability gate exists to prevent. The refusal names the entry
    that lifts it.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md), whose
    13.4 section carries the layout amendments this made, each with its why --
    including the one that cost a build: on a case-insensitive macOS filesystem
    `Ports/TcpBinder.swift` and `TCPBinder.swift` are one file, and the failure
    arrives as an undefined protocol descriptor at link time.
    Done (2026-08-30).
13.5. **Done** -- **The capture feed** (lane 3). A `SpeechSource` port over the extension's
    container file — which is not a fallback but the only door, since an
    extension holding `com.apple.security.network.client` is silently skipped by
    macOS and the only evidence is `Skipping network entitled extension` in the
    system log (spec 0041, B1). Then the buffer entity and the five speech
    commands: `getSpeech`, `getLastSpeech`, `getNextSpeechIndex`,
    `waitForSpeech`, `waitForSpeechToFinish`, with timestamps per [spec
    0028](specs/0028-when-was-that-said.md).
    **The bridge numbers utterances on its own side.** Spec 0041 measured the
    extension's sequence counter restarting whenever the system relaunches it,
    which it does freely — so a bridge that trusts those numbers has its
    ordering reset under it without warning.
    This is the entry the whole spike exists to make possible, and it is where
    the provider route pays for itself: the polling route cannot honour a single
    one of these five primitives (spec 0041's table of why).
    **Shipped**: `SpeechSource` over a `LineTailer` seam, `SpeechBuffer` and
    `SpeechText` as entities, `ContainerFileSpeechSource` holding every decision
    about the feed, and the five handlers -- with `speech` announced beside them,
    so the capability gate still describes exactly what works. **Silent mode stays
    refused**, and capture working makes that refusal MORE necessary rather than
    less: half a promise about a human's ears is the dangerous kind, because
    capture that works is what would make a claimed silence look plausible.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md), whose
    13.5 section carries the layout amendments this made, each with its why --
    including the two that were measured rather than reasoned about: the feed's
    tailer must attach to the file synchronously inside `start()`, or the
    utterance an action caused is the one lost to the scheduler, and the tailer
    is an adapter with a test rather than the leaf the layout named it.
    Done (2026-08-30).
13.6. **Done** -- **Capture mode, and hard invariant 3 in its macOS form** (lane 3). The
    marker file that flips the extension between pass-through and silence,
    driven by the mode `hello` declared, restored to pass-through on every
    teardown path — the default cannot be the setting that mutes a screen
    reader.
    macOS gives half of the invariant for free and takes a different price for
    it. **VoiceOver falls back to a working voice when the provider dies; it
    does not go silent** (spec 0041, C2), so the dangerous half holds without the
    bridge doing anything. But recovery is not automatic: VoiceOver then cannot
    resolve the voice again, logging *"Babelfish falling back to defaults due to
    missing identifier"* on every utterance, and **only restarting the reader
    re-binds it**. So this entry owes two detections that have no NVDA analogue —
    the capture voice not being selected, and the provider having died — each
    reported as a named condition rather than as an empty read-back.
    **A THIRD, added 2026-08-29 by [spec
    0047](specs/0047-selecting-the-capture-voice-without-a-human.md), and it is
    the one the others cannot see**: the voice published system-wide and
    nonetheless absent from VoiceOver's own picker, with the extension registered
    and its process alive. Nothing observable from outside the reader
    distinguishes it from health, and VoiceOver exposes no list of its voices, so
    `ProviderState` cannot promote `published` to `selected` on its own evidence.
    It must say so — and name re-registration plus a reader restart as the
    recovery, since restarts alone were measured not to be enough.
    **Shipped**: `SilenceControl` over a marker file the capture voice reads once
    per utterance, `ProviderLifecycle` over three independent signals, the
    `ProviderState` and `ReaderCondition` entities that turn each of them into a
    named diagnosis with its recovery, `SilenceCap` as the session's **third
    watchdog**, and the voice work spec 0047 made possible: the bridge reads the
    user's own voice at the handshake, points the reader at the capture voice
    itself, and writes theirs back on every teardown path. `ping` answers
    `suppressing` and `hello` carries `silenceCap`. **The refusal of silent mode
    was deleted with its named test and MOVED to the handshake** -- where a
    machine that cannot deliver silence is refused *by named condition, with its
    recovery*, while a LIVE session in the same state is not, because writing the
    voice applies live and an unhealthy live session can become healthy while it
    runs.
    **SILENCE IS A LEASE, and that is the entry's whole shape.** `protocol.md` §6
    asks a bridge to arrange its interception so that losing the bridge ITSELF
    lifts it; NVDA gets that from weakly-held extension points and this route
    cannot, because the marker is a file on disk read by a process the system
    owns. So the session refreshes it while it lives and the extension treats a
    stale marker as pass-through: **a SIGKILLed bridge un-mutes the machine by
    doing nothing at all**, and the `defer` that deletes the marker stays only
    because it makes the ordinary case immediate. The renewal is driven by the
    session LOOP rather than by a timer of the adapter's own, deliberately -- a
    timer would keep renewing for a session thread wedged inside a handler, and
    the loop is the thing that can lift.
    **Rule 0 rides on the same channel**: the marker carries the voice the user
    chose for themselves, so pass-through re-speaks in it and capture becomes
    acoustically invisible rather than a substitute nobody asked for -- with rule
    1 still winning, since a session that died without restoring leaves OUR voice
    looking like the user's and re-speaking with it is infinite recursion.
    **Found by a test rather than by a live run**, and worth recording because
    everything else was green: the edit that made the dispatch loop CALL the
    renewal silently did not apply, so every unit test passed while a real silent
    session would have un-muted itself after thirty seconds with nothing in the
    logs to explain it. A session-level test counting renewals caught it; an
    adapter-level one never could.
    **The read path was exercised against the real machine, read-only**: with the
    extension registered, `BridgeListener` reported *"VoiceOver is set to the
    capture voice, and nothing has been captured yet"* -- so pluginkit parsing,
    the published-voice suffix match and the system speech domain read all answer
    correctly on a live host. Nothing was written, and no reader was driven; the
    live checklist is 13.11.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md), whose
    13.6 section carries the layout amendments this made, each with its why --
    including the two that changed the mechanism rather than the naming: the
    marker is an object carrying `silent` AND the user's voice (a live session
    keeps one too, so presence is not silence), and `ProviderLifecycle` needs a
    third seam because pluginkit answers for the EXTENSION and only the machine's
    voice list answers for the VOICE.
    Done (2026-08-30).
13.7. **Done** -- **Input: commands** (lane 3). `pressGesture` over VoiceOver's own
    `perform command`, against the vocabulary in
    `SCRStringsToCommandsMap.scrconfig` — 415 entries on macOS 15.0 mapping an
    English phrase to an internal selector, undocumented, and the closest thing
    VoiceOver has to the bridge's gesture port. It is a better primitive than key
    injection: the reader does its own dispatch so nothing races with whatever
    else holds the keyboard, and **an unknown command fails cleanly** —
    `Command does not exist (6)` — which is the property this repo already wants
    from `Request.cmd`. AppleEvents only; no Accessibility grant is asked for
    here, which is what makes 13.8's laziness checkable. Gesture ids are English
    command names and nothing else at this entry, so a KEYSTROKE sent as a gesture
    is refused by name -- both notations, `control+l` and VoiceOver's own `VO-D` --
    because synthesizing one needs the grant 13.8 exists to keep lazy.
    **The `+`-joined half of that refusal was deleted by 13.17**, in the commit
    that made a chord pressable, and the `VO-D` half stands: `VO` is whatever the
    person bound their VoiceOver modifier to, so pressing it would mean guessing
    at somebody's configuration.
    **THE COMMAND IS ADDRESSED TO THE `commander object`, NEVER TO
    `application "VoiceOver"`, and that one line retired this entry's measured
    risk.** Spec 0047 recorded `perform command` as dead on the maintainer's
    macOS 15.0 -- error 4 for every name, including a bogus one where spec 0041
    had measured `Command does not exist (6)` -- and this entry could not be
    planned as if its mechanism were proven. Re-measured 2026-08-30: the
    `application` class does not respond to `perform command` at all (it is in
    `bridges/voiceover/VoiceOver.sdef`, and was there the whole time); the
    `commander object` does. Sending a command to an object that does not handle
    it fails BEFORE the name is looked up, which is exactly why a good name and a
    bad one failed identically. Addressed correctly, a valid command succeeds and
    a bogus one returns 6. The two specs disagreed because their scripts
    differed, not because the machine changed. Spec 0047's finding 4 is corrected
    and its open question 3 closed in this entry's PR, and
    `bash scripts/voiceover_channels.sh` now probes the commander while keeping
    the application probe as a labelled control.
    **Carries spec 0041's sharpest requirement.** After six consecutive
    `open next speech attribute guide` commands, every VoiceOver-specific call
    began failing while `tell application "VoiceOver" to return name` still
    answered and the process still ran: **the scripting object model died
    without VoiceOver dying**, silently, with nothing failing until the next
    call. A bridge on this route must treat "the reader answers its own name but
    not its own state" as a distinct, detectable, reported condition — returning
    an empty read-back is what a naive implementation does, and it is wrong.
    **Answered by a `ReaderLiveness` port asked only after a dispatch has already
    failed**: a reader that answers its own name but not the command is the named
    condition, with a reader restart as its recovery, and one that answers
    nothing at all is a different report with a different fix. A THIRD confound
    is documented and deliberately NOT detected -- the application under test
    wedged while the reader is entirely healthy, measured 2026-08-30 with an
    unresponsive Finder -- because nothing at this layer can see it, and a port
    that pretended to would be confidently wrong.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md).
    Done (PR #87, 2026-08-30).
13.8. **Done** -- **Input: typing** (lane 3). `typeText` by synthesized
    keystrokes -- layout-independent Unicode injection, not a key sequence, so the
    same text arrives on a Dvorak or an ABNT2 keyboard as on a US one -- with
    **Accessibility requested lazily**, only if the session asks to type. This is
    a macOS-only design lever with no NVDA analogue, because Windows has no such
    gate: the two halves of input cost different permissions, and keeping them
    apart is what makes *"this bridge never asked for Accessibility"* a checkable
    statement rather than an intention.
    **The laziness is structural, and it is checked rather than intended.** Every
    call to `PermissionBroker.request` in the repository is in a COMMAND HANDLER
    about to post a system event: not at construction, not in `Wiring`, not in the
    adapter factory, not in the doctor, not in a probe, and not in a test. A round
    trip in `Tests/Integration/SessionRoundTripTests.swift` drives a handshake, a
    gesture and a speech read past the broker and asserts it was asked **nothing
    at all**, then types and asserts it was asked exactly once.
    **13.17 gave it a second caller and narrowed the claim by one word**, which is
    written here rather than left to be discovered: a keystroke `pressGesture` is
    a system event costing the same grant, so the sentence the tests check is now
    *"a session that presses only the reader's COMMAND NAMES and reads speech
    never triggers an Accessibility request"*. The check itself moved into
    `AccessibilityGrant`, shared by the two handlers.
    **No test may touch the real grant or post a real event**, for the reason
    `Tests/Fakes/Support/ReaderEdge.swift` already existed: the real broker's
    request raises a system dialog and leaves the process granted with no undo,
    and a real `CGEvent` types into whatever window the developer has in front of
    them. Both are injected into the adapter factory so a test cannot reach either
    by accident.
    Carries the finding that **the target application rewrites what was typed** —
    two lines sent to TextEdit came back autocapitalized. "Send this keystroke"
    is not "this text arrives", and anything comparing typed input against
    observed output has to expect the app's own substitutions. That finding cited
    `spikes/voiceover-capture/keyboard.sh`, deleted when 13.2 promoted the spike,
    so it was evidence nobody could re-run: it is back as
    **`scripts/voiceover_keyboard.sh`**, beside `voiceover_channels.sh`, safe in
    the same specific sense -- it types into a scratch TextEdit document it
    creates and closes without saving on every exit path. **A separate script from
    the gesture probe on purpose**: the channels probe runs on a machine that has
    never granted Accessibility and this one cannot, which is the lane's design
    lever expressed as tooling.
    **The text is never logged and `typed` is a length.** protocol.md §5 says
    `typeText` is exactly how a secret is entered; the obligation lands on the
    transcript, which records `TYPE length=<n>` and can never record what.
    `typed` counts unicode scalars, which is the number lane 1's `len` and the
    server's conformance rune count both mean.
    **AND ONE MEASUREMENT THAT BOUNDS THE LEVER RATHER THAN BLOCKING THE ENTRY.**
    VoiceOver's own vocabulary contains real KEYS as named commands -- read off
    the machine on 2026-08-30, `SCRStringsToCommandsMap.scrconfig` has **30** of
    them: `tab key`, `return key`, the four arrows, `f1 key` through `f12 key`,
    `delete key`, `forward delete key`, `fn key`, plus modifiers in two flavours,
    momentary (`command key`, `shift key`, `option key`, `control key`, `fn key`)
    and sticky (`toggle command key`, ...). All are dispatched by the reader over
    AppleEvents and cost no Accessibility grant, so **if a modifier composed with
    the key after it, a chord would be reachable through `pressGesture` alone.**
    **Measured 2026-08-30 on macOS 15.0 (24A335): THEY DO NOT COMPOSE.** Four
    runs -- sticky and momentary, option and command -- each followed by
    `delete key` into a scratch TextEdit document, and every one of them deleted
    exactly ONE CHARACTER, the same as the no-modifier control; Option-Delete
    would have removed a word and Command-Delete the whole line. No modifier was
    left latched. The instrument is **`scripts/voiceover_modifiers.sh`**, safe in
    the same sense as the other two, and it clears and PROVES clear any sticky
    modifier it set. **The bound for `typeText` is independent of that and is
    stronger: the table contains ZERO letter keys**, so literal text could not
    come out of it however well it composed -- which is why typing synthesizes
    events and pays for the grant. What this changes is 13.11: the guidance
    document must tell an agent that `pressGesture` reaches VoiceOver's commands
    and single keys and **not** chords, rather than leaving it to discover that a
    modifier command appears to succeed and does nothing.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md), whose
    13.8 section carries the layout amendments this made, each with its why --
    including the one that moved a port: `PermissionBroker` goes in the
    `AdapterSet` and the CONTROLLER makes the request, rather than the typer
    holding a domain port, because the control dialog will need the same broker
    and a view may consume a port but not an adapter's private seam.
    Done (2026-08-30).
13.9. **Focus** (lane 3). `getFocusInfo` — and **`getState` is no longer part of
    this entry**, amended 2026-08-29 by 13.1. VoiceOver's AppleScript exposes four
    read/write properties in total and no state noun; its 45 toggles are commands
    with no query; and its preferences plist records only deviations from default,
    behind `cfprefsd`, with VoiceOver holding its own copy in memory. `setState`'s
    contract needs a read BEFORE the write, and the capture feed gives a read
    after it. So the toggles are reached through `pressGesture`, where VoiceOver's
    own announcement of the resulting mode comes back in the result's speech, and
    the agent — which knows the locale, the reader and the intent — does the
    compare. No power is lost; the promise `setState` cannot keep is.
    Focus itself has three routes: `text under cursor` of either cursor
    (AppleEvents only), the `describe` commands read through captured speech
    (AppleEvents only), and the accessibility tree (Accessibility). `getFocusInfo`
    answers from the tree when the grant exists and from the VoiceOver cursor when
    it does not, and **never requests the grant itself** -- the grant belongs to
    the commands that POST an event, and reading where the focus is is not one. Two measured traps ride
    with it: `AXUIElementCreateSystemWide()` fails with `-25204
    kAXErrorCannotComplete` — not a permission error, so no grant fixes it — and
    VoiceOver publishes no accessibility tree of its own.
    The dictionary exposes a `vo cursor` and a separate `keyboard cursor`, each with
    its own `text under cursor`, and they are two views that only usually agree.
    Note what `last phrase` actually is, since it is the obvious-looking
    shortcut here: not one phrase but the last output *request*, which after a
    VoiceOver restart returned an entire startup announcement and the focused
    item as a single string. Richer than "one word", and still one slot -- and it
    was NOT reached for here: both routes below answer a question about the
    element, and `last phrase` answers a question about the reader's output.
    **The route is chosen through a one-method adapter seam,
    `AccessibilityTrust`, that `TCCPermissionBroker` also answers**, rather than
    by handing the inspector the domain's `PermissionBroker` or by widening the
    port to `focusInfo(accessibilityGranted:)`. So 13.8's lever survives the
    entry that wanted the same grant without moving the machine to earn it,
    **structurally**: the object focus holds cannot request a permission, and a round trip in
    `Tests/Integration/SessionRoundTripTests.swift` drives `getFocusInfo` down
    BOTH routes past a counting broker and asserts it was asked nothing at all.
    `appModule` is the frontmost application's **bundle identifier** and `role`
    is `AXRole`; `AXRoleDescription` is asked for nowhere, because it is `AXRole`
    rendered into the user's language. And the entry's load-bearing rule is that
    **nothing merely empty is a fault**: finding 5's confound means a bridge that
    reported a named reader fault for an empty read would be diagnosing its own
    doing. The instrument is back too, as `scripts/voiceover_focus.sh` --
    read-only, showing all three views at one instant, and keeping the
    system-wide element as a control that is expected to fail (re-measured
    2026-08-30: still `-25204`).
    **And the two cursors were measured**, which is what the entry owed. Live on
    2026-08-30, macOS 15.0: one press of the reader's own `stop interacting with
    item` moved the `vo cursor` to the scroll area while the `keyboard cursor`
    and the accessibility tree both stayed on the focused text -- so **they
    separate on one ordinary keystroke**, and **the tree tracks the KEYBOARD
    cursor**, which is what makes it the right source rather than merely the
    richer one. The third result was not what anyone was looking for: **the VO
    cursor's answer is LOCALIZED** (`área de rolagem`) where the tree's `AXRole`
    is `AXTextArea` on every machine, so the fallback route's `name` is not
    comparable across machines -- which is what **13.11's guidance must say**.
    The instrument is `scripts/voiceover_cursors.sh`, kept separate from the
    read-only focus probe because it PRESSES: a disagreement cannot be waited
    for, it has to be provoked.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md), whose
    13.9 section carries the six layout amendments this made, each with its why.
    Done (2026-08-30).
13.10. **Done (2026-08-30)** -- **The human channel** (lane 3). **SPLIT WHILE IT
    WAS BEING IMPLEMENTED**: this entry was "the control dialog, and the human
    channel", and the dialog is now **13.14** for the reason stated in the lane
    header above. What shipped is the half that needed no window.
    `announce` **speaks with the bridge's own synthesizer, outside VoiceOver
    entirely**, which is the only reason it is audible in a silent session -- the
    mode where the capture voice is rendering the reader mute and `announce` is
    the human's ONLY channel. It excludes our own capture voice by identifier
    suffix, because an announcement rendered by the extension that is rendering
    silence would be silence talking to itself. That is a cleaner bypass than
    NVDA's, where the same claim rests on the interception being a filter in
    front of a synth that is still loaded.
    **So `HumanWarning`'s refusal is gone**, deleted in the commit that made the
    promise keepable, exactly as 13.6 deleted `VoiceOverAdapterFactory`'s refusal
    of a silent session: `pressGesture` and `typeText` now SPEAK their `announce`
    in both modes, and a warning that cannot be spoken stops the command rather
    than being dropped.
    `askUser` and `waitForUserReply` are **two commands** (protocol.md §5), so
    the one design question the spec left open had to be answered: the port
    PRESENTS and the answer is POLLED, never awaited. The alternative reads
    better and was declined because the thread that would block is **the one that
    renews the silence lease** -- a lease expiring while somebody reads a dialog
    is the failure 13.6's whole design exists to make impossible.
    Asking also **gives the reader back while the window is open** (§5:
    `suppressing` is false then), because a question put to somebody whose screen
    reader this session has muted is a dialog they cannot hear; the answer puts
    the silence back, unless the cap has already lifted -- that was a guarantee
    rather than a loan.
    **The endpoint NAME is now a stored setting** (11.37), the persisted
    `BridgeConfig` is real, the audible session cues are real, and
    `Precondition` names the kind of thing this bridge can observe, cannot set
    and cannot work without -- **AppleScript enablement is its only true
    instance**, because spec 0047's findings 16 and 17 moved voice selection from
    "report it and wait for a human" to "repair it". All four are read by
    `BridgeListener`, which now starts from the stored settings, lets a flag
    override them for one run, plays the cues as well as printing them, and
    prints what the machine can do before anything is pressed.
    `hello` announces `interact`, and its three commands answer.
    **The instrument is `bash scripts/voiceover_announce.sh`**, which is the one
    promise here no unit test can make: it opens a silent session against a
    listening bridge, presses one command to show the reader is inaudible,
    announces to show the bridge is not, and asks a question. It says plainly that
    it makes the machine speak.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md), whose
    13.10 section carries fifteen layout amendments, each with its why -- starting
    with the split.
13.11. **Done (2026-08-31)** -- **Packaging, CI, and the live run** (lane 3). `poe build` produces the
    `.app`; a macOS CI job builds and headless-tests the bridge; the
    `conformance` gate runs the real Go binary against the real Swift bridge, as
    it already does against the real Python one; `server/config/defaults.json`
    gains a `voiceover` reader so an agent does not have to configure one by
    hand. Then the live-VoiceOver checklist in the PR body, with **its fixtures
    versioned in the same PR** per the 2026-08-22 rule — a live checklist is this
    repo's substitute for a CI test on the reader edge, and evidence that cannot
    be re-run is weaker than it looks.
    Two costs this entry inherits and must state rather than discover:
    **updating the provider costs a VoiceOver restart**, every time, for every
    user; and **VoiceOver crashes routinely** — five crash reports on the
    maintainer's machine on 2026-08-28 alone, all before the spike started. "The
    reader restarts underneath the bridge" is normal weather on macOS, not an
    edge case, and it makes every check in this lane flakier than anything lane 1
    faced.
    **Gains the `guidance` capability and its documents**, amended 2026-08-29 by
    13.1: the document can only be written against a vocabulary that already
    works, and it is where VoiceOver's 45 undocumented toggle strings become
    usable — the agent is told which ones matter and that each announces its own
    result. That is the answer to "how does an agent read state on a reader that
    cannot be asked". It also carries the third rendering of the embedded-document
    trap: Go embeds at compile time, Python ships and reads at run time, and Swift
    resolves through a `Bundle.module` resource bundle that `build.sh` must copy
    into `Contents/Resources` or the failure is a runtime trap rather than a
    compile error.
    **And it owes 13.8's measurement a sentence**, because a negative that an
    agent will otherwise rediscover is a negative worth writing down: the
    vocabulary contains single KEYS (`tab key`, the arrows, `f1`-`f12`,
    `delete key`) and modifier commands in two flavours, and **the modifiers do
    not compose** -- measured 2026-08-30, re-runnable as
    `bash scripts/voiceover_modifiers.sh`. A modifier command SUCCEEDS and changes
    nothing about the key after it, so the guidance must say that `pressGesture`
    reaches commands and single keys and not chords, and that a chord needs
    `typeText`'s route and its grant.
    **What shipped, and the five things that differed from the plan** -- each
    recorded as an amendment in spec 0046's 13.11 section with its measurement:
    a **defect 13.10 shipped is fixed here**, because
    `Permission.automationVoiceOver` was read with an API that answers about the
    CALLING BINARY while this bridge sends every AppleEvent from an `osascript`
    subprocess -- measured 2026-08-30, `-1744` from the API against a successful
    reader reply on the same machine seconds apart, so the launcher printed a
    false negative about a machine that was working; it now asks the channel and
    reads the number, and `PermissionState` gained `cannotTell` for the answers
    that are not about a permission at all. **No second macOS CI job was added**:
    `portable (macos-latest)` already built and headless-tested the bridge, so it
    gained the packaging step instead -- `build.sh` is 220 lines that nothing had
    ever run in CI. **The doctor gains no staleness check for the Swift
    documents**, because SwiftPM already tracks them (measured), which makes this
    rendering of the trap the least dangerous of the three rather than an equal.
    **`build.sh` does not copy the resource bundle** into `Contents/Resources`
    yet, because the `.app` contains no code that could read a guidance document
    until 13.14 gives it the domain's edge. And **the bundle identity was not
    renamed**: dropping `spike` unregisters the published voice and needs a
    reader restart to recover, and it was deferred rather than paid on a week
    when the machine's publication state was already unreliable (13.13a) and no
    human was there to rescue it -- it should ride with 13.14, which touches
    `build.sh` anyway. The **version** half was paid:
    `BridgeVersion.swift` is now the one declaration and `build.sh` derives from
    it.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md).
13.12. **Can VoiceOver be asked what mode it is in?** (lane 3; a measurement, not
    a feature). Taken 2026-08-29 by 13.1, in the shape of
    [spec 0041](specs/0041-can-voiceover-say-what-it-said.md) and for the same
    reason: the alternative is to assume. Its target is sharper than when 13.1
    opened it: a fuller sweep on 2026-08-29 found **three** preference files with
    three different jobs, not one — `com.apple.VoiceOver4/default.plist`
    (persisted settings, deviations only), `com.apple.VoiceOver4/journal.plist`
    (timestamps, refreshed on every restart and therefore NOT a change log —
    [spec 0047](specs/0047-selecting-the-capture-voice-without-a-human.md)
    measured that), and `com.apple.VoiceOver4.local.plist` (runtime state,
    including `SCRScreenCurtainState` and VoiceOver's own unplanned-shutdown
    counter). Spec 0047 already diffed all three across a **voice** change and a
    clean quit and found nothing prompt; this entry asks the remaining question —
    **does a TOGGLE write promptly, where a voice change did not** — reusing
    0047's method and `scripts/voiceover_settings.sh`.
    If it is live and prompt, a **read-only** `state` becomes implementable and
    earns its own entry. If it is not, the answer is written down permanently and
    nobody re-opens it. Either way lane 3 ships v1 without `state`, so this blocks
    nothing and is deliberately last.
    Adds no production class, so it carries no class/file layout — exactly as
    spec 0041 did.
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md) (Part 2 states the question; the probe itself is this
    entry's work).
13.13. **AMENDED 2026-08-29 (late): the question is answered; what remains is
    wiring.** The bridge sets VoiceOver's voice by writing ONE preference —
    `VoiceOverDefaultVoiceSelections` in the **system speech** domain
    `com.apple.SpeakSelection`, never VoiceOver's own — and it applies **live, in
    both directions, with no reader restart, no UI, no AppleScript and no
    Accessibility grant**. Proven end to end on 2026-08-29 against a live reader.
    The trap that hid it for an evening: `defaults write` with an old-style plist
    literal makes every value a STRING, VoiceOver silently rejects the record,
    falls back to the system default AND rewrites the key — so the write looks
    like a no-op. Preserve types (export/modify/import);
    `scripts/voiceover_voice.py` is the mechanism. What is left for this entry is
    to record and restore the previous voiceId around a session, per spec 0046's
    lease-and-restore policy. Original scope follows.
13.13a. **Selecting the capture voice without a human** (lane 3; a measurement
    first, a feature only if the measurement allows one). Opened 2026-08-29 by
    [spec 0047](specs/0047-selecting-the-capture-voice-without-a-human.md),
    which was written against a live reader rather than against documentation.
    **One of spec 0043's two stated costs is already retired**: restarting
    VoiceOver is scriptable — `tell application "VoiceOver" to quit`, then
    `activate`, 13.8 s round trip, measured six times — and it needs only the
    AppleEvents grant the bridge already has, never Accessibility. So "updating
    the provider means restarting the reader" stays true and stops being manual.
    **The other cost is unresolved and has three untried routes.** The voice is a
    single preference key, read out of the system rather than guessed:
    `SCRCategories_SCRCategorySystemWide_SCRSpeechComponentSettings_SCRVoiceIdentifier`,
    holding an `AVSpeechSynthesisVoice` identifier. Writing it to the file and
    restarting did **nothing** — VoiceOver never even instantiated our voice.
    What is still untried, cheapest first: writing the CFPreferences **domain**
    (`com.apple.VoiceOver4/default`) rather than the file path, as Guidepup does;
    a matching `journal.plist` entry, since that file indexes the 38 settings
    that deviate and ours was never journalled; and the companion key
    `SCRVoiceUseCustomizedVoiceSettings`.
    **The maintainer's design — an activity carrying only the voice — is sound
    and is not what spec 0046 refuses.** An activity inherits everything it does
    not override, so it is additive, visible in VoiceOver Utility and deletable;
    Guidepup's refused mechanism symlinks the user's preference files to a
    mounted image and replaces their configuration wholesale. Different
    granularity, different answer. What blocks it is ACTIVATION: Apple documents
    three routes and no fourth — the VO-X chooser, VO-X-X previous activity, and
    automatic binding by app or website — and the only scripted one is a
    `perform command`, which is exactly what 13.7 now records as broken.
    **This entry therefore owes 13.7 an answer as much as it owes itself one.**
    It also needs one thing nobody can read from the system: an activity has to
    EXIST before its storage shape can be described, because profiles are user
    data and the default configuration archive holds no template.
    **The same day found something that displaces all of the above and is the
    entry's real first question.** The capture voice was **absent from
    VoiceOver's own picker** while `AVSpeechSynthesisVoice.speechVoices()` listed
    it, the extension was registered, and its process was alive — every signal
    outside the reader said the voice was fine. Five reader restarts did not
    repair it; `pluginkit -r`, `lsregister -f`, `pluginkit -a` and then a restart
    did, after which the picker showed
    `Português (Brasil)` -> `screen-readers-mcp` -> `Capture Spike`. So **the
    preference experiment above tested nothing**: VoiceOver did not have the
    voice in its catalogue at the time, and the write may well be sound. Repeat
    it first.
    It also **corrects spec 0041's C2**, which says only a reader restart
    restores a lost voice: a restart is necessary and not sufficient. And it
    hands **13.6** a fifth condition — published system-wide yet not offered by
    the reader — which the bridge cannot detect, because VoiceOver exposes no
    list of its own voices, so the honest report is "published; whether the
    reader offers it cannot be read" with re-registration as the instruction.
    **ANSWERED, later the same day, and the answer is not a preference.** Setting
    the voice by hand writes NOTHING: not `default.plist` (untouched, and still
    untouched after VoiceOver quit), not the journal, not the domain view, and
    the identifier appears in no file under `~/Library/Preferences`,
    `~/Library/Application Support` or `~/Library/Group Containers` -- while the
    selection survives a full reader restart. So the write route is dead, not
    mis-aimed, and the three hypotheses above die with it.
    **What works is the accessibility framework, by MESSAGE and not by
    coordinate**, and the recipe is in the spec: open the utility with VO-F8;
    `AXSelected` on the `Voz` category row, which does take because that is a
    real AXTable; `AXPress` the voice button and then the INNER `Voz, <voice>`
    button it reveals; `AXFocused` on the picker's search field and TYPE, which
    is not optional because the list is VIRTUALIZED and an unfiltered row is
    absent from the tree entirely; then `AXPress` **the button inside the target
    row's cell**. Verified as a round trip, both directions.
    An earlier draft of this entry concluded the opposite -- that only a
    synthesized click at the row's frame could commit it, and that the bridge
    must therefore report an unfixable precondition rather than set the voice.
    That was wrong, and it was refused on the right grounds: a framework that
    could not select a list item would fail everything built on it. The row and
    the cell expose no press action; the BUTTONS INSIDE THE CELL do, and the
    probe had stopped one level too shallow.
    So this entry's remaining work is an ADAPTER, not another measurement: a
    `ReaderVoiceControl` port over that recipe, with the reader restart from
    finding 1, and the named condition 13.6 now owes.
    Spec: [spec 0047](specs/0047-selecting-the-capture-voice-without-a-human.md).
13.14. **The control dialog** (lane 3; **needs 13.11's live tier**). Split out of
    **13.10** on 2026-08-30, by Marlon, while that entry was being implemented,
    and the reason is a rule about evidence rather than a preference about
    scope: *wait until you can control VoiceOver, so that you can navigate
    through your own GUI by yourself, and keep using the config file until
    then.* Every other entry in this lane is checkable by driving the reader and
    reading back what it said; **a window is only checkable by eye**, unless the
    thing driving it is the reader this bridge already talks to -- and this bridge
    can drive VoiceOver, so the dialog should be checked the way everything else
    is. That needs 13.11's live tier, so it comes after it.
    The macOS counterpart of [spec 0011](specs/0011-bridge-control-ui.md) --
    endpoint selection, connection state, the session's activity -- plus the
    three rows that exist only here: **whether AppleScript control of VoiceOver
    is enabled**, which the bridge cannot enable, cannot work without, and which
    no API can set for the user (VoiceOver Utility -> General; on Sequoia written
    to both a Group Container plist's `SCREnableAppleScript` and the legacy
    `/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled`); **which
    permissions are granted**, with a way to trigger the requests; and **whether
    the capture voice is selected in VoiceOver**, which is a VIEW of
    `ProviderState` rather than a boolean the dialog computes for itself.
    **Most of what it reads already exists and already has callers**, which is
    what 13.10 shipped: the persisted `BridgeConfig` (including the endpoint
    NAME, 11.37), the `ReaderScriptingSetting` port, `Precondition`,
    `Permission.automationVoiceOver`, the `EventBus` the server already emits to,
    and the audible cues. `BridgeListener` reads all of them today; the dialog
    replaces it as the thing a human drives, and adds the ability to EDIT the
    settings without a `defaults` command.
    **AND IT IS NOW THE ONLY PLACE `askUser` CAN BE CHECKED AT ALL.** Measured
    2026-08-31 by 13.11's live run: `AppKitPromptWindow` calls
    `NSApp.activate(ignoringOtherApps:)` and its header says a real window needs an
    `NSApplication` -- which `BridgeListener` does not have, ending as it does in
    `dispatchMain()`. So `askUser` returned a ticket, no window appeared, and the
    session died mid-poll. `announce` is unaffected and was confirmed audible in a
    silent session; the other two thirds of `interact` have no live check until
    this entry supplies the run loop. Spec 0046, amendment 17.
    **Three things it must do that nothing else can**, each already written down
    where whoever builds it will read them: give the app its dependency edge in
    `Package.swift` and its executable in `build.sh` (spec 0046, amendment 12);
    add `register()` / `unregister()` to `ProviderLifecycle`, which 13.6 left out
    because re-registration only takes effect after a reader restart and that is
    not a decision a handshake may take; and **NARROW the one-place claim about
    the Accessibility grant, everywhere it is written**, because the dialog's
    Request button is its second caller -- no COMMAND but `typeText` requests
    anything, and a human pressing a button is not a command (spec 0046,
    amendment 13).
    Spec: [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md), section
    13.14.

13.15. **A voice the reader offers and the system will not speak** (lane 3).
    Raised by Marlon on 2026-08-31, out of 13.11's live run, and it is a
    USER-FACING honesty problem rather than a bug in this bridge.

    **What was measured.** With VoiceOver set to `com.apple.eloquence.pt-BR.Reed`,
    a live session's pass-through came out in Luciana. The bridge was innocent at
    every step: it recorded the user's voice before writing ours, wrote it
    verbatim into the marker (`{"silent":false,"voice":"com.apple.eloquence.pt-BR.Reed"}`),
    and asked for it. The substitution is the SYSTEM's. Proved without ears, by
    the repo's own "compare states, not strings" technique
    ([`docs/how-we-found-the-voice-store.md`](docs/how-we-found-the-voice-store.md)):
    rendering one sentence with `say` produced **byte-identical audio** for
    Eloquence Reed, Eloquence Grandma and Luciana (53760 bytes, one SHA-256), and
    the same for Eloquence Reed and Samantha in English (41984 bytes). **The
    language is obeyed and the synthesizer is not.** Eloquence is advertised in
    the catalogue -- it appears in `speechVoices()`, in `say -v '?'` and in
    VoiceOver Utility -- and no payload is installed, so every request falls back,
    **including VoiceOver's own**.

    **Why it needs an entry.** Nothing in any API says a substitution happened:
    `AVSpeechSynthesisVoice(identifier:)` returns an object that names itself
    correctly, and `didStart` and `didFinish` both fire. So an agent, a
    maintainer, or this bridge's own log will all report the requested voice as
    though it were the delivered one -- which is exactly what happened, and what
    13.11 fixed at the log's end by renaming the field.

    **What the entry owes.** IF the bridge can determine that the reader's
    selected voice is not installed -- and the byte-comparison above shows it is
    determinable offline, so the question is whether it is determinable *cheaply
    at a handshake* -- then it must **say so plainly**: that the user's chosen
    voice will not be used, that the language default will be heard instead, and
    **how to install the voice outside VoiceOver** (System Settings >
    Accessibility > Spoken Content > System Voice > Manage Voices). A bridge that
    silently changes how somebody's machine sounds is doing the one thing Rule 0
    exists to prevent, even when the substitution is not its doing.

    If it turns out NOT to be determinable at reasonable cost, that is a real
    answer too and is written down permanently rather than re-investigated --
    the shape spec 0041 and spec 0047 both used.

    **It affects `live` sessions only.** A silent session renders nothing, so
    nothing is substituted; this quietly strengthens the standing advice to prefer
    silent.

    Spec: none yet -- a measurement-and-decision entry in the shape of
    [spec 0047](specs/0047-selecting-the-capture-voice-without-a-human.md).

13.16. **Does `journal.plist` change what "this reader has no log" means?** (lane
    3; a measurement, not code). Raised by Marlon on 2026-08-31, out of the voice
    work: the three-preference-file sweep found
    `com.apple.VoiceOver4/journal.plist`, **a per-key last-changed index** mapping
    every key in `default.plist` to the `CFAbsoluteTime` it was last written — and
    it appears in no public documentation.

    **Why it deserves re-examination now.** This lane has said, in the guidance
    document an agent reads and in `Registry.capabilities`, that VoiceOver **keeps
    no diagnostic log**, so the `log` capability group is absent from the READER
    rather than unimplemented. That claim was made against the question *"is there
    an NVDA-style event log?"* — and journalling is a different shape of answer:
    not what the reader DID, but **when each of its settings last changed**. If
    that is live and prompt, it is a real, if narrow, observation channel, and
    "there is no log here" is too strong a sentence to leave in a document agents
    are told to trust.

    **What is already known, and it cuts both ways.** [Spec
    0047](specs/0047-selecting-the-capture-voice-without-a-human.md) measured the
    journal **refreshing timestamps on restarts for settings nobody touched**, so
    it cannot be read as a change log as it stands — an earlier draft inferred the
    opposite from two data points and was wrong. But that experiment altered a
    **voice**, not a **toggle**, which is exactly the gap board entry **13.12**
    still has open.

    **So this entry and 13.12 should probably be answered together**, by one
    controlled experiment: toggle a setting whose key is known, watch all three
    files with `cfprefsd` in the picture, and see whether `journal.plist` moves
    promptly and *only* for that key. Whatever the answer, it settles two entries:
    whether a read-only `state` is implementable, and whether the guidance
    document's "no reader log" sentence needs narrowing to "no event log; setting
    changes are timestamped, with these caveats".

    Spec: none yet — a measurement entry in the shape of [spec
    0047](specs/0047-selecting-the-capture-voice-without-a-human.md).

13.17. **Done** -- **Chords: `pressGesture` takes keystrokes too** (lane 3; was
    **a v1 blocker for the `user` persona**). Raised by Marlon on 2026-08-31, in
    the sharpest possible form: *"All blind users will use chords to operate, no
    matter what. If chords aren't pressable, we need a driver."*

    **What shipped.** A gesture id is now either one of VoiceOver's own English
    command names, which goes to the reader as before, or a **keystroke** --
    `+`-joined, modifiers first and the key last, `command+l` -- which is posted
    at the system as a `CGEvent`. `CommandVocabulary` classifies rather than
    refusing, and the **space rule** decides: a separator counts as keystroke
    notation only in an id with no spaces at all, so `command key` still goes to
    the reader and `command+l` does not. **No new wire command**, because
    protocol.md §5 already calls a gesture id "the reader's own user-facing
    command notation" and on NVDA that notation IS keystrokes -- so this is the
    contract being met rather than stretched, and which of the bridge's routes
    carries an id stays the bridge's business.

    **The keyboard layout was the real work, and there is no table in this
    repository.** A `CGEvent` carries a virtual keycode and which one produces
    `l` depends on the active layout; a hard-coded ANSI table would have compiled,
    passed every test its author wrote, and pressed the wrong key on the
    maintainer's Brazilian keyboard. So `CurrentKeyboardLayout` asks
    `TISCopyCurrentKeyboardInputSource` and `UCKeyTranslate` and caches the
    reverse map **by input-source id, re-read per press**, so switching layouts
    mid-session needs no observer. A character the layout cannot reach is a
    **named failure that posts nothing** -- never a wrong key. Measured live on
    `com.apple.keylayout.Brazilian-Pro`: 110 characters mapped, `$` on the shifted
    layer of the `4` key, `ç` unreachable and reported as such.

    **The bug this entry produced, found by its own live run, is worth reading
    before anyone touches a `CGEvent` here again.** The first implementation set
    modifier FLAGS on the key event and posted no transitions -- which is what spec
    0048 §2.5 decided, on the reasoning that flags are what menu shortcuts match.
    They are, and the very first `command+l` opened Safari's location bar. It also
    left **Command held down on the maintainer's keyboard**, with
    `CGEventSource.flagsState` saying so and nothing else in the system doing:
    every keystroke afterwards was a chord, and the symptom that surfaced was
    `typeText` reporting `typed: 11` into an address bar the reader read back as
    empty. So v1 posts real modifier transitions, cumulative down and reversed up,
    **released from a `defer` even when the press failed**. `voiceover_modifiers.sh`
    had warned about that exact hazard in its header for a day and asserts against
    it after every probe; this entry's own instrument did not, on its first
    version, and so reported a successful chord on a machine it had just broken.
    It does now. Spec 0048 §2.5, amended with the measurement.

    **The lazy-grant lever survived and narrowed by one word.** The grant is
    requested on the first keystroke of a session exactly as on the first
    `typeText`, through a shared `AccessibilityGrant` -- so there are two callers,
    both command handlers about to post an event, and *"a session that presses
    only the reader's COMMAND NAMES and reads speech never triggers an
    Accessibility request"* is still what the counting-broker scenario asserts.
    That sentence was stated in **far more places than the eleven** spec 0046's
    amendment 13 counted -- 27 inside this bridge and 13 outside it -- and every
    one was rewritten in this PR rather than left to go quietly false. **A key
    with no modifier stays a command name** (`return key`), because routing it
    through the event path would spend the grant for a keypress that never needed
    one -- which 13.19 kept while giving the key itself a notation (`kb:enter`),
    so the lever's sentence survived that entry word for word.

    **`VO-D` is still refused**, and no feature retires that: `VO` is whatever the
    person bound their VoiceOver modifier to, so pressing it would mean guessing
    at somebody's own configuration. The refusal names both alternatives.

    **The gap it closed, and why it lasted.** Neither of this bridge's two input
    routes could send Command-L:

    - `pressGesture` dispatches VoiceOver's own command names through the reader.
      Its vocabulary contains single keys and modifier commands, and **the
      modifiers do not compose** — measured 2026-08-30, `bash
      scripts/voiceover_modifiers.sh`. `CommandVocabulary` therefore *refuses* a
      keystroke id outright.
    - `typeText` synthesizes a `CGEvent` with `virtualKey: 0` and a **Unicode
      payload** (`CGEventPoster.post(unicode:keyDown:)`). That is how literal text
      arrives; it never presses a key with a modifier held.

    So the bridge can drive the reader and can enter text, and **cannot press
    Command-L, Command-F, Command-W or Command-T** — which is how everybody
    actually uses a Mac.

    **It is OUR gap, not the platform's.** Core Graphics sends chords given a
    virtual keycode and `event.flags`; we already hold the Accessibility grant
    that costs. The 13.11 live run stated the limitation as though it were a fact
    about VoiceOver, and that was wrong — recorded here because the wrong framing
    is what let the gap sit unnoticed through four entries.

    **The three open questions were settled by asking what NVDA does**, on
    2026-08-31, and its answer pointed the same way in all three: NVDA's gesture
    ids are keystrokes and nothing else, `inputCore` decides whether the reader
    eats the key or the application gets it, the bridge writes `control+o` and
    `NVDA+t` on identical transcript lines, and one `gestures` capability covers
    the lot. So: **one transcript verb** for both routes here too, because a
    transcript is read across readers and a verb only this bridge could emit would
    make two runs of the same task structurally different; **one capability**,
    because capabilities gate command groups and both halves are `pressGesture`;
    and **the key goes last**, which is the rule
    `keyboard_gesture_name.press_order` already enforces in lane 1 -- so
    `command+l` is the same string on both readers and `l+command` is a named
    failure on both.

    **Why it blocked v1 for the `user` persona.** That stance's whole claim is that
    a task is driven with what an ordinary user has. On macOS that includes chords
    in the first minute of any session — opening a location, finding on a page,
    switching windows. A `user` run that cannot press them is not a restricted
    stand-in, it is an incomplete one, and its "the task failed" findings would be
    about the bridge rather than the interface under test.

    Spec: [spec 0048](specs/0048-pressing-a-chord.md). Instrument:
    `scripts/voiceover_chords.sh` with `scripts/voiceover_chord_press.swift`.
    Done (PR #92, 2026-08-31).

13.18. **How much of an announcement can a session actually capture?** (lane 3;
    **a measurement, not code**; VoiceOver only). Raised by Marlon on 2026-08-31,
    out of 13.17's live run, and it is the entry that decides whether this lane
    needs a new wait primitive or only better documentation.

    **What was measured, and it is already enough to make the entry worth
    opening.** Landing on an element in Safari web content produces **two**
    utterances -- the role, then the text -- and the gap between them is **50-110
    ms in a silent session and ~1505 ms in a live one**. Any command sent inside
    that window makes VoiceOver CANCEL the pending text, and a cancelled utterance
    is one this bridge never sees: the capture point is the synthesizer,
    downstream of the reader's own queue. Four moves batched into one
    `pressGesture` in a live session returned four utterances and **not one
    heading title**; the same nine moves in a silent `run_sequence` with a 400 ms
    gap captured twenty utterances with **every title present**.

    **One thing that is NOT a cause, checked rather than assumed, so nobody
    investigates it twice.** This bridge does not wait for audio before reporting:
    `CaptureController.capture()` emits to the `UtteranceSink` BEFORE it calls
    `synthesizer.speak`, so a session sees an utterance the moment VoiceOver hands
    it over and **first-utterance latency is identical in live and silent**. The
    spike did it the other way round and every utterance reached the file ~0.2 s
    late; the order was changed deliberately. What differs between the modes is
    when the NEXT utterance arrives, which is the reader's queue and not ours.

    **Two causes, and only one of them is VoiceOver's.** The first is that a live
    session is paced by AUDIO, because the reader waits for one utterance to be
    spoken before handing over the next -- which is a person listening, and not a
    defect. The second is OURS: `graceMs` returns as soon as the FIRST utterance
    arrives (`protocol.md` §5, spec 0025), so a batched press fires the next key
    the moment the role lands and cancels the text **in silent as well as live** --
    measured, 2 of 4 titles lost in a silent batch.

    **The primitive this reader wants does not exist in either bridge.**
    `SpeechBuffer.collectSince` waits for speech to have STARTED; `waitToFinish`
    waits for it to have STOPPED and cannot work alone, because silence before
    speech and silence after it are the same observable -- which is also why a
    `settle` step inside `run_sequence` returns immediately in the gap and is no
    help. What is missing is the COMPOSITION: start, **then** quiet. That has a
    start condition, so the objection against quiescence does not reach it.

    **AND THE THIRD CAUSE IS OUR OWN PIPE, which nothing has measured.** Lane 1's
    bridge runs INSIDE the NVDA process -- `filter_speechSequence` is a function
    call on NVDA's own thread -- so its capture latency is nil and `graceMs` races
    nothing. Here the reader, the capture voice and the bridge are **three
    processes**: VoiceOver hands the utterance to the `.appex`, which appends a
    JSON line to a file in its container, which `FileLineTailer` **polls every 50
    ms**. Its own header already calls that cadence "a deliberate floor on the
    feed's latency, and the one number in this class a live run should be measured
    against" (spec 0046, open question 3). **So `graceMs`'s default of 100 ms is
    about two poll intervals wide on this bridge and effectively unbounded on the
    other one** -- the same field, the same number, and a different meaning.

    The gap figures above are NOT distorted by that, and it is worth saying why
    before anyone re-derives it: `emittedAt` is stamped in the capture voice's own
    process when the utterance arrives and travels in the line, so a gap is the
    difference between two upstream stamps rather than between two poll ticks. What
    the pipe delays is WHEN A SESSION CAN SEE an utterance -- which is exactly what
    a grace window races.

    **Why this is an investigation and not a wire change.** The obvious answer is a
    second field beside `graceMs` meaning "wait for it to start, then for it to
    stop" -- and it would be wrong to ship on the reasoning above, because nobody
    has yet separated the three causes. Until the pipe's own contribution is known,
    any constant chosen would be fitted to a number that is partly ours.

    **So the entry owes measurements before it owes a design**, and they are
    cheap:
    - **how much of a grace window the pipe consumes**: time from `emittedAt` to
      the instant the utterance becomes readable in a session, and how that moves
      when `FileLineTailer`'s poll interval is varied. That separates our latency
      from the reader's and is the first thing to know;
    - the role-to-text gap in a NATIVE window against WEB content, in silent, on
      the same command shape -- which sizes any cap, or shows that a cap is the
      wrong shape;
    - whether the gap tracks the length of the role utterance, which would say
      whether the pacing is per-utterance or per-command;
    - whether a session can distinguish "the text is still coming" from "this
      element has no text", which is what any wait has to answer and may not be
      answerable at all.

    **It is VoiceOver-only, deliberately, and that was verified rather than
    assumed.** Read out of `../nvda` at `release-2026.1` on 2026-08-31: NVDA's
    `SpeechManager` DOES wait for the synth before pushing the next sequence
    (`_onSynthDoneSpeaking` -> `_handleDoneSpeaking` -> `_pushNextSpeech(True)`,
    `source/speech/manager.py`), so "NVDA does not pace" would have been wrong.
    What makes lane 1 immune is that `filter_speechSequence.apply()` is the FIRST
    LINE of `speak()` (`source/speech/speech.py:1096`) -- upstream of the manager,
    the queue and the synth alike. So it captures what the reader DECIDED to say;
    this bridge captures what got as far as being SPOKEN. Lane 1 also captures
    in-process, so it has no pipe to race. A contract change made for
    this reader's problem would make lane 1 pay a settle on every keypress for an
    announcement that has already arrived -- which is what spec 0025 chose the
    early return to avoid.

    Instrument: none yet; it wants one, in the shape of
    `scripts/voiceover_chords.sh`. Spec: none yet -- a measurement-and-decision
    entry in the shape of [spec 0047](specs/0047-selecting-the-capture-voice-without-a-human.md).

13.19. **Done** -- **A key that is not a command: `kb:h`** (lane 3; was "an
    unmodified letter key has no notation"). Found by Marlon on
    2026-08-31, driving 13.17's own build: with single-key Quick Nav on, an
    ordinary VoiceOver user presses **`h`** to move by heading, and this bridge
    cannot express it.

    **The gap, exactly.** 13.17 made the `+` the discriminator between the two
    notations `pressGesture` accepts, so an id with no `+` is a reader COMMAND
    NAME. That is right for `return key` and `tab key`, which the reader dispatches
    itself for free -- and it means a bare `h` is looked up as a command and
    refused: *"this reader has no command called 'h'"*. There is no way to ask for
    the letter key.

    **The capability exists and is reachable through the wrong tool.** Measured in
    the same run: `type_text "h"` DOES drive Quick Nav -- it moved to "nível de
    título 1" -- because the Unicode-payload event reaches the same place. So an
    agent can do it today by typing, which is precisely the confusion the two
    notations were separated to prevent, and which the guidance document currently
    contradicts ("a key with NO modifier is a command name").

    **What it must not break.** The reason a bare key stays a command name is the
    Accessibility grant: `return key` costs nothing and routing it through the
    event path would spend the grant for a keypress that never needed one. So the
    answer is not "a lone token is a keystroke" -- it is a way for an agent to say
    WHICH it means.

    **The notation is `kb:`, which is NVDA's, and that was Marlon's call on
    2026-08-31** over the `key:h` this entry had proposed and over widening
    `typeText`'s remit. `protocol.md` §5 had called `kb:` a *legacy* prefix that an
    NVDA bridge merely tolerates; it is now the contract's **source prefix** --
    redundant on a reader whose gesture notation is keystrokes and nothing else,
    load-bearing on a reader with two vocabularies. That is the namespace [spec
    0018](specs/0018-input-vocabulary.md) reserved, spent by the mirror image of
    the case it anticipated: not a new KIND of gesture, but the first reader whose
    unprefixed ids are not the keyboard.

    **And the instruction that made the entry bigger than its fix:** *"let's
    standardize the maximum we can with what nvda already does."* Read out of
    `../nvda/source/vkCodes.py` rather than recalled, this bridge's key names
    diverged from lane 1's in four places -- three that merely FAIL there
    (`return`, the four arrows, the casing of `pageUp`) and one that presses A
    DIFFERENT KEY: `delete` is this machine's erases-backwards key and Windows'
    erases-FORWARDS one. So NVDA's names are now the canonical ones, the Mac's are
    synonyms where they name the same key, and **a name that would mean a different
    key is refused by name** (`delete`, `insert`, and the `nvda` and `windows`
    modifiers), each carrying the alternative it should have been. One rule, and
    it is the one to keep: *a name that differs with no hazard is tolerated; a name
    that differs with a hazard is refused.* One key is irreducible -- NVDA calls
    forward delete `delete` -- and the guidance says so.

    **13.8's lever survives word for word**, which is why no forty-place sweep was
    needed this time: a keystroke costs the Accessibility grant whether or not it
    has modifiers, so *"a session that presses only the reader's command names and
    reads speech never triggers an Accessibility request"* is unchanged, and
    `return key` still costs nothing while `kb:enter` costs the grant.

    Spec: [spec 0049](specs/0049-a-key-that-is-not-a-command.md). Instrument:
    `scripts/voiceover_chords.sh`, which gained an unmodified-key press.
    Done (PR #94, 2026-08-31).

13.20. **Done** -- **The handshake climbs the ladder** (lane 3). Found by Marlon
    on 2026-08-31, driving 13.19's live checklist.

    **The problem.** `connect_reader` established a session on a machine that
    cannot capture speech and said nothing about it. `poe build` deletes and
    replaces the capture-voice bundle -- `build.sh` begins `rm -rf build` -- so
    the system forgets the extension; every session afterwards returned
    `speech: []`, which is indistinguishable from "the reader said nothing" and
    is the one answer [spec 0041](specs/0041-can-voiceover-say-what-it-said.md)
    says a bridge on this route must never give. It cost that checklist an hour,
    **and the bridge knew**: `BridgeListener` printed `providerNotRunning` at
    startup and the handshake went ahead anyway.

    **The decision.** `hello` stops REPORTING where the `ProviderState` ladder
    stopped and starts CLIMBING it, failing by name at the one rung it cannot
    climb. Five rungs, all eager: read both permissions; get the reader running
    (`open -a VoiceOver` -- `killall` alone was measured NOT to relaunch it);
    register the extension (`lsregister -f` then `pluginkit -a`, confirmed by
    POLLING, because `pluginkit` hands the work to `pkd` and returns); select the
    voice; and then make the reader speak and require the utterance to ARRIVE,
    which is the only evidence `capturing` accepts.

    **13.8's lever survives word for word, and there was no sweep.** The
    handshake READS the grants and never requests one -- a handshake that waited
    on a consent dialog nobody may be looking at is a handshake that hangs -- so
    `PermissionBroker.request` still has exactly two callers, both command
    handlers about to post a system event. What it cost is stated rather than
    hidden: a machine that has never granted Accessibility can no longer open a
    session at all, which is the property `scripts/voiceover_channels.sh` was
    written for. That script is unaffected; it drives the reader directly.

    **Fatal in BOTH modes**, which is not 13.6's asymmetry reversed. 13.6 is
    about a promise concerning a human's ears, which only `silent` makes. This is
    about a promise that `getSpeech` means anything at all, which a live session
    announces just as loudly -- and "it may become healthy while it runs" is a
    reasonable thing to say about a state nobody is repairing and an unreasonable
    one about a state the handshake has just tried to repair and failed.

    **The rule to keep is one sentence: SESSION state is restored at teardown --
    the voice selection, hard invariant 3, unchanged -- and MACHINE state is
    not.** There is deliberately no `unregister()`: undoing the registration
    would recreate this exact bug, and the accept loop is serial today but will
    not always be, so one client's disconnect must never deregister the voice
    under another.

    **The honest limit**, and it is `registered` to `published`: the system
    publishes a newly registered voice only after VoiceOver RESTARTS, and a
    handshake may not restart a blind person's screen reader. So registration
    succeeds, the proof still fails, and the failure names the restart and gives
    the command -- always as a pair, `killall VoiceOver && open -a VoiceOver`.

    **One consequence worth knowing before you read a transcript**: the proof's
    utterance is real speech and stays in the buffer, so index 1 of every session
    is the reader describing where its cursor is and a session's own speech
    starts at 2.

    Spec: [spec 0050](specs/0050-the-handshake-climbs-the-ladder.md). Open
    question it deliberately does not answer: **how a human grants these
    permissions** -- a button in the bridge is the candidate and has a real
    problem, since TCC attributes a grant to the process it holds RESPONSIBLE,
    measured on 2026-08-31 to be `/usr/libexec/sshd-keygen-wrapper`. That is its
    own entry.

13.21. **Done** -- **The silence cap lifted and never re-armed** (lane 3). Found
    by Marlon on 2026-09-01, driving the bridge. **Not a regression from 13.20**:
    the defect predates it and predates 13.10. Fixed in 13.20's PR because that
    is where it was asked for.

    **What happened.** A silent session: the agent connected, went quiet, the cap
    warned, it stayed quiet, the cap **lifted** -- and then the agent announced
    something and the machine never went silent again.

    **Why.** `SilenceCap.didLift` was a ONE-WAY LATCH: `check` answered `.none`
    for the rest of the session, so `announce` and `askUser` reset a window
    nothing was measuring. `protocol.md` §6.1 rule 4 says a lifted session **may
    go quiet again**, on a fresh window of the same length, each re-suppression
    audibly marked, *"so exposure stays bounded no matter how many times a session
    re-arms"* -- and lane 1 has done exactly that since its own cap entry. **A
    lift is a bounded window ending, not a decision that this session is finished
    being silent.**

    **How it survived, which is the part worth keeping.** `SilenceCap.swift`'s
    header named the gap and deferred it to 13.10 by name. 13.10 arrived, added
    the two commands that reset the window, and did not add the re-arm behind
    them; `WaitForUserReply` then wrote the omission down as though it were a
    decision. **A deferral that names the entry it is waiting for is only as good
    as that entry remembering it** -- and a gap described as a rule stops being
    re-examined.

    **The fix.** A third `SilenceCapAction`, `.resuppress`, returned when the cap
    is lifted and something audible has been heard since; a fifth cue,
    `silenceResuppressed()`, which is the lift's rising pair played backwards and
    carries words, because two tones cannot say why a reader just went quiet; and
    the Session acting on both, guarded. **Nothing heard, nothing re-armed**: the
    lift happened because the human had been told nothing, so re-arming on a timer
    alone would take their machine away for the very reason it was given back.

    Spec: [spec 0050](specs/0050-the-handshake-climbs-the-ladder.md) §8 -- no spec
    number of its own, the 13.11 precedent. Done (PR #95, 2026-09-01).

13.22. **Done** -- **Two keys held together** (lane 3). Found by an agent driving the bridge
    and relayed by Marlon on 2026-09-01: *"it could not activate quick nav
    because the command would be left and right arrows pressed together, and it
    can't press keys together. This needs to be generalized, if possible. On mac
    this is common."*

    **The gap.** `Keystroke` was modifiers plus exactly ONE key, so
    `kb:leftArrow+rightArrow` failed with *"'leftarrow' is not a modifier this
    bridge knows"* -- true, unhelpful, and pointing at the wrong thing. Arrow-key
    Quick Nav is that chord, and it is how an ordinary VoiceOver user turns on the
    mode they then navigate with all day.

    **The reported blocker was not one, and that half is already fixed.** All
    three Quick Nav toggles exist as COMMAND NAMES -- measured out of
    `SCRStringsToCommandsMap.scrconfig` -- and the guidance document already named
    them twice. The agent reached for the chord from general Mac knowledge
    instead. That is the THIRD time this lane has paid for that shape (spec 0048
    §1.1, spec 0049 §1.1), so the documents were fixed first, in PR #95: use the
    command name rather than the chord, the limit is named in general, and an
    agent that meets an act with no command name is told to REPORT it rather than
    reach for `type_text`, which sends characters and not keys.

    **The measurement is done** (2026-09-01, macOS 15.0), because the one thing
    that could not be reasoned out was whether VoiceOver accepts SYNTHESIZED
    simultaneity -- spec 0048 is the reason for asking rather than assuming.
    Control, probe, control: the two arrows pressed SEQUENTIALLY do not move
    arrow-key Quick Nav; pressed TOGETHER they do; pressed together again it comes
    back. State read from `SCRCInvertedTCommanderCaptureEnabled`, a key FOUND by
    the state-comparison technique in `docs/how-we-found-the-voice-store.md`
    rather than recalled. **No inter-event delay is needed.**

    **And the chord is NOT a clean toggle of one setting**, which cost a
    correction to the instrument and is the useful part of the entry: from
    `arrow=0 single=1`, one chord gave `arrow=1 single=1` and the next gave
    `arrow=0 single=0` -- so it takes SINGLE-KEY Quick Nav down with it, and the
    first version of the probe reported "restored" while having quietly turned off
    a setting the maintainer uses daily. It now watches and restores both, through
    the COMMAND NAMES rather than by pressing the chord again. That sharpens the
    recommendation rather than weakening it: each command name moves exactly one
    setting and says which way it went; the chord moves two and names neither.
    (**Amended on the live run, 2026-09-02:** the chord is not silent -- it
    announces a generic "Quick Nav on"/"off" -- but it does not say which of the
    two settings moved, and it moved both.)

    **What it must not do, and did not:** displace the command name as the
    recommended route
    (it costs no grant and announces its result), or spend 13.8's lever -- a chord
    is a `CGEvent` like any other keystroke, so `request` still has two callers.
    The sharpest rule is spec 0048's generalised: the keys are released in a
    `defer`, in reverse, so a post that fails partway cannot leave an arrow key
    held down.

    **What shipped**, and the shape is the one a notation entry should have --
    no new files, no new ports, no new capability: `Keystroke.key` became
    `Keystroke.keys`, parsed by one rule (leading modifiers are modifiers, the
    first token that is not one begins the keys, everything after it must be a
    key); `CGKeystrokePresser` presses them down in order and releases them in
    reverse from a SECOND `defer`, registered after the modifiers' one so Swift
    runs it first -- the keys come up while the modifiers are still held, which is
    what a real keyboard does. A press that fails partway releases exactly the
    keys that went down; one unreachable key in a chord posts nothing at all.
    `CommandVocabulary` needed no change, which is the reviewable claim rather
    than an absence.

    **Two amendments rode in the PR**, both in the spec: a token that names no key
    is diagnosed by POSITION -- not-last is reported as a misspelled modifier
    (`cmd+l`), last as a key -- because rule 3 moved which token fails; and
    `FakeEventPoster` gained a `keyFailureAt`, without which "it released what it
    pressed" cannot be asserted, since the existing `keyFailure` fails the release
    too.

    Spec: [spec 0051](specs/0051-two-keys-held-together.md) -- **Agreed
    2026-09-02.** Instrument: `scripts/voiceover_two_key_chord.sh`, which carries
    the measurement. **Stacked on PR #95** and opened once that merged, per one
    open PR per lane. Done (PR #96, 2026-09-02).

13.23. **Done** -- **The bridge died of SIGPIPE instead of tearing down** (lane
    3). Found on 2026-09-02 by 13.20's own live checklist, item 5, and fixed in
    13.20's PR because that is where it was found. **Not a regression from
    13.20**: the defect is as old as `SocketTransport`. What 13.20 added was a
    handshake long enough to be abandoned mid-flight, which is what made a
    latent crash reachable.

    **What happened.** `connect_reader` with VoiceOver not running overran the
    server's 15 s hello budget. The server hung up. The bridge's next `send` went
    to a closed peer, and on Darwin that raises SIGPIPE, whose default
    disposition **terminates the process** -- so the write did not fail, the
    bridge ceased to exist. Observed twice, exit 141 both times.

    **Why it mattered more than a crash.** Nothing in `Session.endSession` ran.
    The endpoint file was left behind, so every later dial answered `connection
    refused`. And rung 4 had already pointed the reader at the capture voice, so
    that selection was left dangling with no session alive: the next VoiceOver
    restart found the voice unpublished, fell back to the system default **and
    persisted it**, destroying the stored record of the maintainer's own voice.
    The identifier had to be recovered from a log line in a session transcript.
    **The damage outlived the process** -- and had that session been `silent`
    rather than `live`, the suppression would have outlived it too, which is hard
    invariant 3 exactly.

    **The fix.** `SO_NOSIGPIPE` on the accepted descriptor, beside the
    `SO_RCVTIMEO` that was already there. `send` now returns `EPIPE`, the
    existing `SocketError.latest("send")` reports it as an ordinary channel
    failure, the session ends by its normal path and both teardown steps run.
    Chosen over `signal(SIGPIPE, SIG_IGN)` at the entry point because this bridge
    has **two** entry points -- `BridgeListener` and the shipped `.app` -- so a
    fix at either is a fix at only one; the option travels with the descriptor
    that has the problem, and both binders build their transport from it.

    **It has a test, and that is a deliberate exception** to "leaf adapters get no
    test file". The rule's reason is that a leaf makes no decisions, and it is
    right about `send()` -- but the assertion here is not what the call returns,
    it is that **the process is still running afterwards**, which nothing above
    this layer can make: a fake transport cannot raise SIGPIPE, and a process
    killed by a signal reports no failure anywhere. The control was run: with the
    option disabled the suite dies mid-test with no per-test result, killed by
    signal 13. `SocketTransportTests.swift` says all of this in its header,
    including that unusual failure mode.

    **What is NOT claimed.** The fix is proven by that test and its control, not
    by a live reproduction: the overrun stopped reproducing once the machine was
    warm, and three later attempts -- including one from a freshly wiped bundle
    with the reader stopped -- all completed in about 5 s. So the 15 s budget is
    **not** simply too small for a cold reader, and this entry does not say it is.
    What the two observed overruns had in common has not been isolated. Spec: none
    -- the 13.11 precedent. Done (PR #95, 2026-09-02).

13.24. **Done (2026-09-03)** -- **A voice identifier is used without ever being
    resolved** (lane 3). Spec:
    [0056-the-voice-a-session-leaves-behind.md](specs/0056-the-voice-a-session-leaves-behind.md).
    **BUNDLED WITH 13.32 AND 13.33** into one spec and one PR, approved by Marlon
    on 2026-09-03: the three are three failure points on ONE setting -- the voice a
    session leaves selected on somebody's machine -- and they share ONE design
    question, which is what decided it. Answering *"what may a session do with a
    voice identifier that does not resolve?"* three times in three PRs risks three
    answers. Raised by Marlon on 2026-09-02 while 13.23 was being
    diagnosed, and kept separate from it on purpose: 13.23 is a bridge that dies,
    this is a bridge that quietly uses a voice that is not there.

    **THE ENTRY'S OWN FRAMING WAS WRONG IN ONE WORD, AND THE WORD DECIDED THE
    ANSWER.** The text below reads as the 13.20 shape -- refuse, as 13.20 refuses
    an unusable capture voice. There are two identifiers, and only one of them was
    ever unresolved: the CAPTURE voice has always been resolved, by
    `publishedCaptureVoice()`, matched by suffix against the machine's real
    published list, with rung 4 failing by name when there is no match. What was
    never resolved is **the user's own voice**. So an unresolvable identifier here
    never makes `getSpeech` meaningless and 13.20's precedent does not transfer.

    **Decided by Marlon, 2026-09-03**, on being shown that correction:
    *"I would like to have a default voice, but that handshake announcement must
    let the user know and give them instructions to install the voice."* So:
    **resolve and report, never refuse, in both modes.** The machine was already
    in that state before the session connected; the session did not cause it,
    cannot fix it, and refusing would deny testing on a reader that is otherwise
    perfectly capable -- while putting nothing back. **The defect this entry names
    is the SILENCE, not the fallback.**

    **What shipped.** One new port method, `systemPublishesVoice`, answered from
    the same published list our own voice is matched against -- one authority, so
    the two answers cannot disagree. Rung 4 resolves what it records and, when the
    machine does not publish it, SPEAKS a notice through the bridge's own
    synthesizer (audible even in a silent session, because it goes around the
    reader entirely) naming the voice and the settings path. Teardown asks the same
    question and **still writes the identifier**, which is the decision rather than
    an omission: writing it is what takes the reader OFF the capture voice, and
    refusing would leave our voice selected with no session alive -- 13.23's
    hazard, caused by the cleanup rather than by the crash. `ReaderCondition` gains
    a fifth case, the first that is not about the capture voice and that no
    `ProviderState` maps to.

    **The honest limit, stated rather than discovered.** The authority is
    `AVSpeechSynthesisVoice.speechVoices()`, which lists voices that are
    **advertised and not installed** -- 13.15 measured exactly that with
    `com.apple.eloquence.pt-BR.Reed`, the maintainer's own voice. **So this catches
    a voice that was REMOVED and not one that was never installed**, the method is
    named for what it can back up, and the live checklist had to demonstrate the
    warning with a synthetic identifier because his own machine publishes his.

    **Two things it deliberately did NOT do.** The agent is not told at `hello`:
    `HelloResult` has no notes field, and adding one is a protocol change across
    three bindings for a message whose only actionable audience is the person at
    the machine, who has just been told out loud. And teardown does not announce --
    a voice removed MID-session is noted and spoken to nobody, which is a stated
    gap rather than a hidden one.

    **The gap.** Nothing checks that a voice identifier still resolves before it
    is used, in either of the two places one is used. At teardown the bridge
    writes back whatever identifier it recorded at the handshake; if the user
    removed that voice mid-session, it writes a dead identifier and the reader
    falls back to the default with nothing anywhere saying so. In `live` mode the
    capture voice re-synthesizes with that same recorded identifier, and
    `AVSpeechSynthesizer` falls back silently on one it does not know -- so a
    session could change the person's voice for its whole duration and report
    success throughout.

    **Why it is worth an entry.** This is the shape 13.20 exists to kill: a real
    failure that renders as *"it just sounds different"* rather than as a named
    error. It is also the shape hardest to catch from inside, because every call
    involved succeeds.

    **What it needs.** Resolve the identifier before using it, and when it does
    not resolve, fail by name and say what to do -- System Settings >
    Accessibility > Spoken Content > System Voice > Manage Voices. It needs a
    spec conversation first: whether a session may proceed on the default voice
    with a warning, or must refuse, is exactly the kind of question 13.20 settled
    for capture and this has not settled for voices. **That question is answered
    above: proceed, and tell the person.** Spec 0056.

13.25. **Done (2026-09-02)** -- **A blind user sends KEYS, so the agent sends
    keys** (lane 3). Spec:
    [0052-the-keys-a-voiceover-user-presses.md](specs/0052-the-keys-a-voiceover-user-presses.md).
    **The direction was Decided**, by Marlon on 2026-09-02, in these
    words: *"an agent has to do what the user does, and what the user does is
    pressing keys, like in nvda."* What is left to a spec is HOW, not WHETHER.

    **Recorded honestly, because it is the reason this took three rounds:** this
    was raised twice before it was accepted. The bridge's answers each time were
    that the field report's agent had used the route the guidance recommends
    (true), and that the recommendation is earned by the permission lever (also
    true, and beside the point). Neither answers the premise. **The tool's whole
    claim is that an agent stands in for a user; a user presses keys.**

    **The fidelity problem.** A VoiceOver user presses `VO-M` to reach the menu
    bar. This bridge dispatches `go to menu bar` through the reader's `commander
    object`, and 13.7 made that the RECOMMENDED route -- it is the first section
    of `screenreader://reader-guidance`. Those are two different paths through the
    machine: a keystroke goes out through the window server, past the focused
    application, and reaches VoiceOver's event tap; a command name is dispatched
    INSIDE the reader and never passes the application at all.

    **So the recommended route can hide the exact defects this tool exists to
    find.** An application that swallows or reinterprets `VO-M` is invisible to
    `perform command`, which reports the command succeeding while a real user is
    stuck. The persona contract -- *"drive exactly as an ordinary user drives, so
    that reachable means the same thing in your report as in theirs"* -- is not
    honoured by a session reaching the reader through an automation channel no
    user has.

    **What it needs.** `vo` accepted as a modifier and resolved from the machine,
    exactly as lane 1 resolves `nvda`. The reason given for refusing it does not
    hold: NVDA's modifier is equally configurable (Insert, Extended Insert, Caps
    Lock) and lane 1 resolves rather than refuses, and VoiceOver's is readable --
    measured 2026-09-02, `com.apple.VoiceOver4/default.plist` stores deviations
    only, so an absent modifier key IS the Control-Option default. Then keys
    become the `user` persona's vocabulary, and the command name is demoted to
    what it actually is: an automation convenience and a diagnosis aid.

    **The cost is accepted, not discovered.** 13.8's lever is the sentence *"a
    session that presses only the reader's command names and reads speech is never
    asked for Accessibility"*. A faithful user-persona session presses keys, so it
    needs the grant, and that sentence stops describing ordinary driving -- it
    becomes a statement about reading-only sessions in the `validator` and
    `expert` stances. **A lever bought by driving the reader in a way no user does
    is bought with the fidelity this tool sells**, which is the trade Marlon made
    and the spec must state rather than re-open.

    **What it does NOT explain**, so the entry is not credited with more than it
    earns: the field report's menu-bar near-miss, where `go to menu bar` reached
    Finder's menu bar, was caused by an unbundled binary that macOS never makes
    the active application. `VO-M` would have landed in Finder's menu bar too.
    That case is about knowing WHICH application you are in, and belongs to its
    own entry.

    **TAKEN NEXT, ahead of every lower-numbered entry in this lane** -- Decided
    2026-09-02. The board's usual rule is that its first non-Done entry is the
    next step; this entry overrides it, so 13.12, 13.13a, 13.14 and 13.24 all wait
    behind it. The reason is that it changes what a session IS, and every hour
    spent building on the command-name route is an hour spent on the wrong
    premise.

    **The deliverable is knowledge, not only a notation.** Lane 1's guidance
    instructs an agent as if it had replaced the user -- what to press, what a
    user would do next, where the ordinary vocabulary stops. This lane's guidance
    is to be built to that same standard on VoiceOver's own keys, rather than
    around a dispatch channel. `screenreader://reader-guidance` becomes an account
    of what a VoiceOver user PRESSES.

    **What it cost elsewhere**, as shipped: `protocol.md` §5 gained the
    modifier-SYMBOL rule (a reader's symbol is resolved by its bridge and is never
    a key the caller spells out, `NVDA+f7` there and `vo+m` here); the
    reader-guidance documents were rebuilt around keys; 13.7's recommendation was
    demoted; 13.19's `VO-D` refusal now names the rewrite `vo+d` rather than
    sending the agent to a different route.

    **Two things came out of it that nobody was looking for.**

    - **This reader's FACTORY KEY BINDINGS are readable from the machine.**
      `SCRStringsToCommandsMap.scrconfig` (415 English names to command
      identifiers) joins `ScreenReaderConfiguration.archived-scrconfig`'s
      `SCRCConfigurationKeyboardKeyToCommands` (282 key specifications) on the
      identifier: **301 name-to-keystroke rows**, printed by
      `python3 scripts/voiceover_default_bindings.py`, which presses nothing and
      needs no grant. That is what let the guidance be rebuilt on MEASURED keys,
      and it retires 13.7's "this document contains no table of key combinations,
      and one would be worse than useless" -- which rested on a binding being
      unknowable from here, and it is not.
    - **This reader matches its bindings on the event's CHARACTER**, not on the
      keycode and the modifier flags, and that was a LIVE DEFECT rather than a
      missing feature: `control+option+shift+q` reached VO-Q instead of
      VO-Shift-Q, moved a different setting and reported success. An application
      never notices, because it matches keycode and flags -- which is why 13.17's
      `command+l` worked on the first try and three entries passed over it. Fixed
      by stamping the character the active layout produces on the layer being
      pressed.

13.26. **Done (2026-09-02)** -- **The bridge PREPARES the reader, and puts it
    back** (lane 3). Spec:
    [0053-the-bridge-prepares-the-reader.md](specs/0053-the-bridge-prepares-the-reader.md).

    **This entry was renamed while it was being specified, and the old title is
    worth keeping visible because it shows how much the answer grew.** It was
    filed as *"the handshake has two routes to its proof"* -- one question, raised
    by Marlon on 2026-09-02 while 13.25 was being specified: *do we still need
    VoiceOver controlled by AppleScript as a gate, to begin with?* Answering it
    turned out to require the handshake to stop INSPECTING the machine and start
    PREPARING it, and the board entry never caught up until this PR.

    **The requirement, in Marlon's words, and it is the frame for everything
    else:**

    > if we don't need apple script control for the operation, and we shouldn't
    > need, letting it on is an ask for doing "wrong stuff". a normal user doesn't
    > need it, so either I have a solid reason to let it on or it will be
    > disabled.

    > so the bridge has to "prepare voiceover". This makes sure voice is the way
    > it should, vo keys are the way they should, and vo is started.

    > And restore should kind of do the same in reverse.

    A blind person must be able to leave that switch **off** -- it lets any
    process on the machine drive the screen reader they depend on -- and this
    bridge must still establish a session, drive the reader, and prove it can hear
    it. 13.25 is what made that possible: keys are a route to this reader now, so
    AppleScript stopped being the only one.

    **What shipped.**

    - **Rung 1 asks for a ROUTE, not for every permission.** It used to loop over
      `Permission.allCases` and refuse unless every one was granted. Now:
      Accessibility plus a readable modifier means keys; the Automation grant plus
      the AppleScript switch means command names; neither is a refusal naming BOTH
      fixes, because an agent told about one of them sends a human to grant the
      wrong thing.
    - **The capture proof has two routes, and the command name goes FIRST** --
      deliberately the opposite of 13.25's rule for driving. A keystroke passes the
      application under test and a command name does not; that is the whole
      fidelity argument, and none of it applies to a probe, which tests nothing in
      front of the person. The cheapest, least invasive route wins. The probe is
      `speak the time and date` / `vo+f7`, chosen by Marlon over `go to dock`
      because that one MOVES the VoiceOver cursor and a connect that quietly walked
      somebody's cursor would be a small invisible edit to where they were
      standing, every time.
    - **Liveness stopped being an AppleEvent.** "Is VoiceOver running" is the
      running-application list now: no permission, cannot be switched off, and
      exact where the AppleEvent was a proxy.
    - **The modifier is borrowed where it is Caps Lock**, which a synthesized event
      cannot reach on this platform (measured four ways). Write ours, restart,
      **write theirs straight back** -- so the FILE never holds our value for more
      than a moment and a crash costs "the reader is on Control-Option until it
      next restarts" rather than a wrong preference surviving reboots.
    - **Everything a session changes is journalled**, one file for the machine,
      and `scripts/voiceover_restore.py` reports what is open and puts it back.

    **IT REVERSES A RULE MARKED DECIDED, and that is the entry's sharpest single
    line.** 13.20 wrote *"no handshake in this bridge may decide on a restart --
    it takes the reader away from somebody who is using it."* Marlon reversed it
    on 2026-09-02: *"restarting vo is not a problem for capturing as a bridge
    handshake, if needed."* The bounds are the point -- only for a named reason,
    announced first through the bridge's own synthesizer, and **quit, WAIT for the
    process to be gone, then open**. It also unblocks the one rung 13.20 could not
    climb, since macOS publishes a newly registered capture voice only after a
    restart.

    **And it found a SHIPPED DEFECT on exactly the machine it exists to serve.**
    Measured live 2026-09-02 with the switch off, `press_gesture ["go to menu
    bar"]` answered *"scriptingChannelDead ... Recovery: restart the reader"*.
    Every clause of that is true and the recovery is useless -- no restart brings
    back a switch somebody deliberately turned off, and following it costs a blind
    person their screen reader for nothing. The cause is that the switch removes
    the scripting **object model** and leaves the application answering its own
    properties, so it fails with **exactly** the numbers a wedged reader fails
    with: `-1728` to `return commander`, `-1708` to `perform command`. The two
    states are not distinguishable by error number, ever; only the PREFERENCE
    separates them, and the bridge was already reading it and never consulting it
    there. It consults it now, and separates three conditions where it separated
    two.

    **Who may use the dispatch channel at all**, settled with 13.25 and made
    consequential here -- *"can a user send commands directly? No? Then so cannot
    the agent."* `user` and `validator` press keys only; the channel is the
    `expert`'s instrument, and that stance is told plainly that it may be absent.
    *"Then the expert can, if they need, request apple script permission, and this
    has to be given by a human"* -- there is no mechanism to build, because no API
    sets that switch, so the affordance is `ask_user` plus a failure sentence that
    names the pane at the moment an agent discovers it wants the route.

    **AND IT LOST A FEATURE TO ITS OWN LIVE RUN, which is the part worth reading.**
    The entry also BORROWED the VoiceOver modifier on a machine bound to Caps Lock
    -- write Control-Option, restart, write the person's own value straight back --
    so that such a machine could be driven by keys at all. It was implemented,
    unit-tested, run live on 2026-09-02, and removed the same evening.

    **VoiceOver watches that key.** Changing it under a running reader puts a modal
    question on screen asking the person whether they want to use Control-Option
    instead. Spec 0053 §2.5 had measured that the write does not take EFFECT
    without a restart and that was read as "the running reader ignores it"; it does
    not. Three consequences, none of them a patch: the dialog **blocks the reader
    from quitting**, so teardown's own restart could not run and reported *"still
    running 10 seconds later"*; it **changed a stored setting nobody chose**
    (`SCRVOModifierControlOption` came back as `ControlOptionOrCapsLock`, restored
    by hand and verified against a snapshot); and it hid a third defect -- writing
    the person's value straight back means every later read returns THEIR modifier,
    so the probe and every `vo+...` in the session are refused and the borrow
    accomplishes nothing even when it works.

    **It was diagnosable only because a human said what was on his screen.** Nothing
    at the bridge's layer can see a modal window, and three plausible hypotheses for
    the failed quit -- an auto-relaunch, a stale `NSRunningApplication` list, a race
    with the launch -- were all wrong. Same lesson as the wedged Finder: when reads
    go quiet, ask what is in front of the person. **13.28 owns the retry.**

    **What it does NOT do**, so the entry is not credited with more than it earns:
    it adds no `restore_reader_settings` wire command. The
    [2026-09-02 field report](docs/feedback/2026-09-02-acter-run.md) asks for one;
    that is a change to the shared contract, the Go binding, the capability gate
    and lane 1 as well as lane 3, and it is a board entry of its own. The journal
    and the script answer *"what did this leave behind, and put it back"* today,
    with no protocol change, and are what such a command would be built on.

13.27. **Not started** -- **The key bindings this machine actually has** (lane 3).
    13.25's guidance names the reader's FACTORY bindings, read from the shipped
    configuration. A person who rebound a command in VoiceOver Utility gets their
    own key, recorded as a deviation in their own preferences, and nothing reads
    those -- so "the key did nothing but the command name worked" is currently two
    explanations the bridge cannot tell apart (a rebinding, or an application that
    swallowed the keystroke), and only the second is a defect in the thing under
    test.

    Reading the deviations would make the guidance's table true of the MACHINE
    rather than of the release, which is lane 1's standard exactly -- its tables
    are read out of NVDA at the moment the document is asked for. It is a decoding
    job against an `NSKeyedArchiver` archive with its own risks, and
    `scripts/voiceover_default_bindings.py` is the instrument to grow. Spec: none
    yet.

13.28. **Not started** -- **The modifier without writing a preference** (lane 3).
    13.26 needed the VoiceOver modifier to be one this bridge can press, borrowed
    Control-Option on a Caps-Lock machine by writing the reader's own preference,
    and had the whole design removed by its live run: **VoiceOver watches that key
    and puts a modal question on screen when it changes under a running reader**,
    which blocks the reader from quitting and changes a setting nobody chose
    (2026-09-02; spec 0053 §3.3 keeps the record).

    So the machine that still gets no session is the one whose `vo` is Caps Lock
    alone AND whose AppleScript switch is off. Spec 0052 §3.3's refusal stands and
    rung 1 names it.

    **The lead is Marlon's own, from the same evening**: *"I wonder if voiceover
    executable takes cli parameters."* It does not have flags of its own -- the
    binary is a 16 KB launcher stub -- but it is a Cocoa app, so `NSUserDefaults`'
    **NSArgumentDomain** may apply, and that domain outranks the persisted file:
    `open -a VoiceOver --args -SCRKeysToUseForVOModifier SCRVOModifierControlOption`
    would set the modifier for ONE LAUNCH with nothing written, nothing to restore,
    and nothing for the reader to notice.

    **Unverified, and the first deliverable is the measurement**, not the code: does
    VoiceOver read that key through a domain the argument domain reaches, or through
    `CFPreferences` against its group container, which it would not? A versioned
    instrument answers it. If the answer is no, the honest outcome is that this
    entry closes as "not possible without HID-level remapping", which 13.26 already
    declined to do to somebody's keyboard. Spec: none yet.

13.29. **Done (2026-09-03)** -- **Every chord a person presses, not just the
    reader's** (lane 3). Raised by an agent driving this bridge against a real
    application on 2026-09-03 and relayed by Marlon: `command+k`, `command+/`,
    `command+m`, `command+a`, `command+c` and `command+shift+a` all reported
    `pressed` and **did nothing**, while the same chords sent by System Events
    worked in the same app, the same field, seconds apart.

    **13.25 caused it, and 13.25's own checklist hid it.** That entry stamped every
    character key's event with the character the active layout produces, because
    this reader matches its bindings on the CHARACTER and `vo+shift+q` was reaching
    VO-Q. The stamp works for the reader and removes the chord from every
    application: measured 2026-09-03 across eight legs against TextEdit,
    control-probe-control, with the stamp as the only variable -- `command+a`
    /`command+c` copied nothing stamped and copied the document unstamped, and
    `command+shift+c` opened no window stamped and opened the Colors panel
    unstamped, both run in each order. **It is the call and not the character**:
    `command+c` stamped with `"c"`, byte for byte what the event already carried,
    died just the same, so there is no "stamp only when it changes something"
    narrowing. **And a Shift is not an escape** -- which matters because
    13.25's checklist contains exactly ONE Command chord, `command+shift+c`,
    recorded as opening the Colors panel. It does not reproduce on the code that
    shipped. One measured chord, of the one shape that would look like a control,
    is how a week of broken application input passed review.

    **The fix is one guard and one fact carried down.** `Keystroke` gains
    `holdsReaderModifier`, set by `parse` from the `ModifierSetting` it already
    reads, and true when the chord holds every modifier this machine's reader uses
    -- so `vo+m` and a literal `control+option+m` are the same fact, and a machine
    whose `vo` is Caps Lock or unreadable claims nothing. `CGKeystrokePresser`
    stamps only when it is true. 13.25's correction survives untouched for the
    chords it was for; everything else goes out exactly as the window server built
    it.

    **What this entry does NOT do**, and it is the open question rather than an
    omission: it never asks whether the stamp is needed at all. If a proper
    `CGEventSource` makes the window server fill both the `characters` and
    `charactersIgnoringModifiers` fields itself, the stamp and this flag both
    delete. That is a live measurement against the reader and it is **13.30**.
    Spec 0054.

13.31. **Done (2026-09-03)** -- **A user cannot type a command name, so neither may we**
    (lane 3). Marlon, 2026-09-03, on reading an inventory of where this bridge
    still uses AppleScript: *"if a user cannot type a command, why should we have
    to?"* No VoiceOver user has the command-name channel -- a person presses VO-M,
    and reaches an act with no key through the Commands menu -- so **the channel is
    deleted, entirely**, and with it every AppleEvent this bridge sends.

    **13.25 demoted it and this entry finishes the job.** That entry found the
    dispatch route reporting success on chords a real user was stuck on, hiding the
    defect class the tool exists to find, and left the route as an automation
    convenience. The convenience was still bought with a switch -- *"Allow VoiceOver
    to be controlled with AppleScript"* -- that lets ANY process drive the screen
    reader a blind person depends on, which is an indefensible thing to ask for in
    exchange for a route no human has.

    **Five callers, and four of them delete with no capability loss at all**: rung
    5's capture probe already has `vo+f7` beside it; `TCCPermissionBroker` read the
    Automation grant only because the channel needed it; `VoiceOverFocusInspector`'s
    cursor route serves a session that can no longer exist; `VoiceOverLiveness` has
    not used its script since 13.26. The fifth is `VoiceOverGestureSender`, and what
    it costs is **five commands that ship with no factory key** -- which a user
    reaches through the Commands menu (`vo+h` twice, type, Enter), and so can this
    bridge, because that is keystrokes plus typed text and it has had both since
    13.8.

    **The cascade is the interesting half.** `Permission.automationVoiceOver`,
    `ReaderScriptingSetting`, `VoiceOverPrefsScriptingSetting` and the whole
    `Precondition` entity (its only case was the switch) delete; rung 1 asks ONE
    question instead of two; `Gesture` stops being a choice and `CommandVocabulary`
    returns a `Keystroke` or refuses. The entry adds no file, which is most of the
    argument for it. **The known limit, stated rather than discovered:** the
    Commands menu is LOCALIZED where the dispatch names were English, so the
    English-name route through it is unverified off an English locale -- handed to
    13.27, which is already decoding this reader's own strings. Spec 0055.

13.32. **Done (2026-09-03)** -- **The restore script does not restore** (lane 3).
    Spec:
    [0056-the-voice-a-session-leaves-behind.md](specs/0056-the-voice-a-session-leaves-behind.md),
    **bundled with 13.24 and 13.33** -- see 13.24 for why the three are one entry.
    Found by
    13.31's own live checklist on 2026-09-03, on the maintainer's machine, with his
    voice left on the capture voice by a crashed session -- which is exactly the
    situation `scripts/voiceover_restore.py` exists for, and it did not handle it.
    Three defects, in order of how badly they mislead:

    **It reports the JOURNAL rather than the MACHINE.** After the voice had been put
    back by another route it went on printing *"it is now: the screen-readers-mcp
    capture voice"* as a statement of fact. It is a log reader presenting log state
    as machine state, so any restore performed another way makes it lie -- and the
    person reading it is by definition somebody recovering from a crash, which is
    the worst moment to be told a false thing confidently.

    **`--apply` did not apply.** It printed instructions instead of restoring, and
    the summary line still read *"Nothing was changed. Run again with --apply"* --
    which is what it had just been run with.

    **The instructions it printed name the WRONG KEY.** It offered
    `PlistBuddy -c 'Set :SCRKeysToUseForVOModifier com.apple.eloquence.pt-BR.Reed'`
    -- setting the VOICEOVER MODIFIER to a voice identifier. A human following it
    would put a voice id into the setting that decides what `vo` is, which is the
    setting 13.26 already learned not to write (VoiceOver puts a modal question on
    screen when it changes). This one is close to dangerous rather than merely
    wrong.

    **13.23 is the entry that created this script**, and its argument was that a
    crashed session leaves the voice selected and nothing can say so. The journal
    half works -- the change was recorded correctly, with the right previous value.
    The recovery half was never exercised against a real open change until now.

    **ALL THREE LANDED IN ONE COMMIT AND HAVE ONE CAUSE**, which is worth recording
    because it is a shape rather than an accident: b558c6e (13.26) is the file's
    only commit, and the three defects are a botched removal of the modifier
    branch. The half that called `restore_voice` was deleted with the modifier
    kind; its `else` survived as `if True:`, which is why the PlistBuddy line ran
    unconditionally and why `--apply` never applied. **A deletion that leaves a
    dangling `else` is a deletion that keeps running the wrong half**, and nothing
    caught it because `scripts/` is linted and has no test harness.

    **A FOURTH DEFECT FELL OUT OF FIXING THE FIRST**, and it is the same one a
    level up: the headline read *"1 setting(s) still changed"* from the journal's
    count, over a machine that had already been put back. It now counts what is
    still true OF THE MACHINE, and `is_open_on_the_machine` is where the two
    questions are kept apart -- with "I could not read the preference" counting as
    open, the same rule `process_is_running` applies to a pid it does not own.
    Spec 0056.

13.33. **Done (2026-09-03)** -- **`askUser` kills the launcher** (lane 3). Spec:
    [0056-the-voice-a-session-leaves-behind.md](specs/0056-the-voice-a-session-leaves-behind.md),
    **bundled with 13.24 and 13.32** -- see 13.24 for why. Also found by
    13.31's live checklist, and NOT caused by it: `main` was built in a worktree as a
    control and crashes identically. `BridgeListener` dies with **SIGILL (exit 132)**
    the moment `askUser` opens its AppKit window, preceded by
    *"Attempting to add timer to main runloop, but the main thread has exited"*.

    **The cause is structural rather than incidental.** `main.swift` ends with
    `dispatchMain()`, which parks the main thread by exiting it -- and AppKit needs a
    real main run loop. So `AppKitPromptWindow` is scheduling onto a run loop that is
    not there. It has presumably never worked from this launcher; what hid it is that
    `askUser` is only reached by `poe live`, whose script asks its question LAST and
    prints its closing summary before the process dies.

    **What it costs is more than a crash**: the session dies without tearing down, so
    the capture voice is left selected -- which is how 13.32's finding was produced in
    the first place. The two are one story.

    **It is 13.14's territory**, because the control dialog is what gives this bundle
    a real `NSApplication` and a main run loop. Until then either the launcher runs
    an `NSApplication` of its own, or `UserPrompter` is not reachable from it and says
    so by name rather than crashing.

    **THE LAUNCHER RUNS ONE, and it does not pre-empt 13.14.** `NSApplication.shared`
    with an `.accessory` activation policy, created on the main thread, and
    `application.run()` where `dispatchMain()` was. 13.14 gives the SHIPPED BUNDLE a
    dialog wired through `Wiring.controlSurface`; this is a dev launcher `build.sh`
    deliberately does not copy into the bundle, and borrowing AppKit's run loop is
    not designing a UI. **The refusal was declined for what it cost**: it would have
    made half of 13.10's human channel unexercisable against a real reader until
    13.14 lands -- and needed a new adapter, its fake, its tests and a `Wiring` fork
    keyed on which executable is running, to make a working feature not work.

    **THERE IS NO HEADLESS TEST FOR IT, AND THERE MUST NOT BE**, which is
    `AppKitPromptWindow`'s own no-test-file rule one layer up: a real
    `NSApplication` in a test process takes focus from whatever the developer is
    doing and announces itself out loud on a machine with a screen reader running.
    It is proved by the live checklist and by nothing else. Spec 0056.

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
11.3. **E, enforced observe-only** (both lanes). **On hold as of 2026-08-18** —
    taken out of the queue by decision, to be revisited later. It is not a lane
    blocker: nothing open depends on it, and spec 0029 (Part 3.2, 2026-08-17)
    has since decided the neighbouring question the other way — *deliver the
    right information per persona; if violations turn out to be common, gate* —
    so whether 0017's `control` field survives as written, or observe-only
    becomes the strictest persona the bridge enforces, is exactly what the later
    conversation has to settle. A session where the bridge
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
11.6. **Done (2026-08-19)** — E, a connected session an agent cannot use
    (both lanes; the wire gained one optional field). Shipped **option (c),
    advertise everything always**, plus the reader's guidance document in the
    handshake and the rule that no reader's syntax appears in the text an agent
    reads. **11.24(a) folded in and is Done with it**; 11.24 is now (b) alone.
    What decided it was not new argument but the capability backstop: an
    unadvertised call already ran through the same dispatcher and produced the
    same error from the same wording site, so gating the LIST never made an
    unusable call fail. With everything advertised the backstop became
    unreachable and was deleted, along with the `ToolPublisher` port and the
    connection controller's publish/retract -- the change removes code rather
    than adding it. The surface test (A.7) then found **eleven reader names and
    six key combinations** where the entry had reported one, which is the
    argument for a test rather than a correction, made before it was agreed.
    Original entry, kept because the diagnosis it records is still the reason
    half of this failure existed:
    Found live on
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
    decision spec 0013 made deliberately.
    **Corroborated from outside, 2026-08-18** ([0030](specs/0030-the-second-external-run.md),
    ask 1a): a second external run, driven by a non-Claude model in a different
    client, hit the same *"I can call it but I cannot see it listed"* gap — and
    hit it **without a redeploy**. That widens the entry: the diagnosis above
    explains this project's dev loop severing the surface, but it does not
    explain an agent that connected cleanly and still had no schemas in front of
    it. It also sharpens the cost, because the documented consequence was the
    agent reading our Go source to find out what it could call. Option (c) or
    (d) — a tool list that never changes — answers both readings at once, which
    is a point in their favour that the redeploy analysis alone did not surface.
    See also **11.22**, which publishes the same information as a document and
    therefore does not depend on any client honouring anything. Spec:
    [0022-tool-discovery-an-agent-can-rely-on.md](specs/0022-tool-discovery-an-agent-can-rely-on.md)
    (premise corrected 2026-08-02; **agreed 2026-08-19 — option (c), advertise
    everything always**). The decision turned on a fact the 2026-08-02 draft did
    not use: the capability backstop already runs an unadvertised call through
    the same dispatcher and words the same error, so gating the LIST was never
    what made an unusable call fail — it bought a shorter list and cost this
    entry. 0031 shipping removed the scarcity the other three options answered.
    **11.24(a) folds in**: under option (c) `press_gesture`'s description is read
    before any reader is chosen, which makes its NVDA example wrong rather than
    merely stale, and the spec adds the rule and the test that stop it recurring.
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
11.9. **Done (PR #64, 2026-08-18)** — E, the round trip is the cost — the settle
    is a no-op (lane 2, server). This entry was the ANALYSIS; 11.12 built both
    routes it named, in the same PR, so it closes with them. Its measurements
    are the whole argument for spec 0025 and are kept here in full rather than
    summarised away — the numbers are what make the design defensible, and the
    next person to doubt the grace window should be able to read them.
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
11.10. **Done (PR #67, 2026-08-20)** — E, how long has the human been mute?
    (lane 1, bridge). Found the hard
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
    not a guarantee, and the person it fails is blind and mute at the time.
    **Spec conversation held 2026-08-19**, and it added a constraint the entry
    did not have: an unattended run -- accessibility validation on a CI box with
    nobody in the room -- has no human to protect, so a cap there is damage
    rather than a safeguard. The switch is a property of the MACHINE
    (`config.ini` + the bridge dialog, defaulting to attended), deliberately not
    a persona and not on the wire: the agent declares the persona, so a persona
    that decided this would hand the session its own ceiling. Spec:
    [0032-a-bound-on-the-silence.md](specs/0032-a-bound-on-the-silence.md)
    (agreed 2026-08-19). **Shipped**: a `SilenceCap` entity measuring one thing --
    time since the human last heard their machine -- reset only by the sounds that
    reach them past the suppression (the start cue, `announce`, `askUser`) and by
    nothing else, however many gestures go by. Warns at 45 s over a **880 Hz** cue
    (the third pitch, above announce's 660 and askUser's 440, so it is tellable
    before any word arrives), and at 90 s **stops suppressing while capture
    continues** -- the speech source gains a third state in which the sequence is
    returned intact instead of emptied, so `getSpeech` answers with the same
    entries, indices and timestamps and the words also reach the speakers. The lift
    costs the agent its silence, not its evidence. Re-suppression is allowed,
    audibly marked and opens a fresh bounded window, so no run of bounded pieces
    adds up to an unbounded one. `unattended` in `config.ini` and the bridge dialog
    turns it off per machine, defaulting to attended. `HelloResult.silenceCap`
    carries it outward, `connect_reader` states it in one sentence, and `status`
    reports live suppression off the `ping` it already makes -- so a lift is
    discoverable by asking, with nothing pushed (0021 stands). The two traps Part 3
    named are both tested: callbacks are not double-run while passing through, and
    `resume()` after a prompt does not re-mute a lifted session.
11.11. **Done (PR #70, 2026-08-20)** — E, a session the agent can hear (lane 1,
    bridge). Found live on
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
    **Re-cut 2026-08-20, after 0025 shipped, and the entry is smaller than it
    was.** 0025 Part 3.3 puts `browseMode` on every `pressGesture`/`typeText`
    result, so the 2026-08-03 incident replayed on today's build IS caught: the
    toggle answers `"browseMode": "focus"` in the same call and the six `h`
    presses never happen. What survives is narrower and was never the headline. A
    snapshot answers *which* mode, never *when it changed* or *whether this
    session caused it* — one observable, two situations, the defect this repo has
    cured four times. And nothing rides on a call the agent does not make, while
    NVDA switches modes BY ITSELF (a page load, focus entering an editable
    field), which is the actual mechanism of the 2026-08-03 failure: the reload
    flipped the mode and the agent's toggle then flipped it the wrong way.
    Normalised, each switch lands in the speech stream in order with its own
    `emittedAt`, so *"pressing enter put us in focus mode"* becomes assertable
    where *"we are in focus mode now"* is all a snapshot can support. Part 3.3 of
    the spec (`readerQuiet` at `hello`) is **withdrawn** — 0025 built it, better,
    on every result — and the admitted set is cut to one key.
    **This is NOT marked "absorbed by 11.12."** 11.16 was marked that on
    2026-08-16 and the marking was withdrawn the same day, on reading the spec in
    full; the discipline that produced that withdrawal is why this entry states
    what shrank and what did not, rather than closing.
    Shipped: `normalize` on `hello` (unset means the mode's default — silent
    normalises, live does not), `normalized` on the result disclosing every key
    actually moved, and the admitted set as an entity holding **one** key.
    Written through the existing `ConfigAccessor`, so it is a session-scoped
    override teardown drops and nothing reaches the reader's disk. Two spellings
    changed against the draft and are recorded in the spec rather than applied
    quietly: the disclosure carries `previous`/`current` because `from` is a
    Python keyword and `protocol.py` is the contract's source; and a reader that
    REJECTS the admitted key fails the handshake naming `normalize: false`,
    because a rejection means the spec's own premise is false for that session.
    Spec: [0024-a-session-the-agent-can-hear.md](specs/0024-a-session-the-agent-can-hear.md)
    (drafted 2026-08-03, re-cut 2026-08-20, **agreed 2026-08-20** — both open
    questions settled there). **Decided with 11.17 in one conversation**, which
    is what the pairing asked for; shipped in the same PR, see that entry.
11.12. **Done (PR #64, 2026-08-18)** — E, one round trip per intention (lane 2,
    server + bridge). Implements
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
    number nobody has measured. **That gap was explained when the spec was
    agreed**: it is the client model's own turn time between tool calls, which
    grows with the conversation's context. Nothing is faulty, and it strengthens
    the case — if per-call model turns dominate, call *count* is the right lever.
    **Shipped as ONE PR** covering both lanes, though it was scoped as two. The
    halves are separately reviewable, but the wire change is not separately
    *testable*: `poe conformance` is the only tier where a Go server asking for a
    window meets a Python bridge actually waiting one out, and a live NVDA
    session is the only place the collapse can be judged at all. Splitting it
    would have bought a shorter diff at the price of two live sessions, and the
    second half is what the checklist actually exercises.
    Spec: [0025-one-round-trip-per-intention.md](specs/0025-one-round-trip-per-intention.md)
    (drafted 2026-08-03, **agreed 2026-08-16** — all five open questions settled
    there). The board read "not agreed" until 2026-08-18 while the spec said
    agreed: one more instance of 11.18's drift, found by reading both.
11.13. **Done (2026-08-22)** -- E, where am I, and what is on the page (lane 1,
    bridge + server). Two
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
    faithful design and was deferred, not on principle but because **nobody had
    tested whether say-all advances when no synth runs** — a cheap experiment
    that should happen before this is agreed. **Run 2026-08-18, and then run
    again.** The first run, during 11.12's live checklist, said it does not: in a
    silent session `NVDA+downArrow` emitted two chunks and stopped. The
    observation was real; the cause named for it was wrong, and the conclusion
    drawn — that say-all capture is dead — is **retracted**. The stall was ours.
    NVDA clocks say-all on a `CallbackCommand` it inserts at position 0 of every
    chunk (`speech/sayAll.py`), whose callback moves the caret and asks for the
    next chunk; silent mode returned an empty sequence from
    `filter_speechSequence`, deleting that callback along with the words, and
    `speech.speak()` then returns early on an empty sequence — so the speech
    manager, which is what turns callbacks into indexes, never saw it and
    `lineReached` could not fire. The two chunks were say-all's own
    `MAX_BUFFERED_LINES` fallback, the one path that advances without the
    callback. Fixed in PR #64 by running the non-audible callbacks ourselves,
    queued onto NVDA's event loop rather than passing them to the synth: an
    audit of every driver on the maintainer's machine found that only sapi5
    reports an index for a text-free utterance, while espeak, oneCore, RHVoice
    and ibmeci all clock indexes off audio, and NVDA's own `silence` driver
    notifies nobody at all — so pass-through would have made correctness depend
    on the tester's voice. **Re-run 2026-08-18 after the fix: say-all reads the
    whole document and carries the caret with it** — a heading, 30 paragraphs
    and a closing line captured complete in 328 ms, under `ibmeci`. So say-all
    capture *is* a route to reading a document in a silent session, and this
    entry still has two candidate designs to weigh rather than one.
    Spec: [0026-where-am-i-and-what-is-on-the-page.md](specs/0026-where-am-i-and-what-is-on-the-page.md)
    (drafted 2026-08-03, revised and **agreed 2026-08-22**, implemented in the
    same PR). The revision settled the two candidate designs and reversed one of
    the draft's decisions on the maintainer's instruction: **the whole buffer is
    the default**, because a snapshot bounded by default is incomplete by
    default -- `fromLine`/`maxLines`/`maxChars` survive as an agent-supplied
    opt-in whose cost (two calls are two moments) the contract now states. The
    say-all route is rejected on the DESIGN rather than on the retracted defect:
    it moves the caret, produces utterances with no line coordinates, and costs
    reader time proportional to the document. It stays available as a gesture
    and is the snapshot's cross-check. Two further decisions the board did not
    carry: `truncatedBy` is `"none"`/`"maxLines"`/`"maxChars"` with **no null**
    (0015's doctrine -- a falsy check must not be how an agent asks), and
    `capturedAt` is stamped on every result including `hasDocument: false`.
    The tool is `get_document_snapshot` (wire `getDocumentSnapshot`), gated on a
    new `document` capability -- the NVDA bridge now announces eleven groups.
    **The finding that shaped the implementation**: the buffer's raw text has no
    roles in it, so the snapshot renders through `speech.getTextInfoSpeech`,
    which yields what `speakTextInfo` would have spoken and speaks nothing. That
    buys four properties -- no speech is emitted, the caret does not move, the
    control-field cache is carried across lines as arrowing does, and **that
    cache must be ours**: `getTextInfoSpeech` writes its cache back onto the
    document object unless `useCache` is an explicit `SpeakTextInfoState`
    (`speech/speech.py`, `_getTextInfoSpeech_updateCache`), so the default would
    silently corrupt the user's real browse-mode context. **Live run 2026-08-22, all ten checklist items pass**, and it
    earned its keep: it found a caret-dependent rendering no unit test could
    have, because the seeding happens inside NVDA -- `SpeakTextInfoState(obj)`
    does not merely avoid writing back, it SEEDS itself from the user's live
    reading position, so a snapshot taken with the caret inside a list rendered
    line 0 as `fora de lista titulo nivel 1 ...` and the same unchanged page
    returned different text from two caret positions. Fixed by clearing the
    three caches; the spec's checklist item 5 now carries the converse as a
    standing check. Item 9 answered in favour of the unbounded default -- 1103
    lines rendered in no more time than one line, within a two-second noise
    floor, reader responsive throughout -- and surfaced the one surface change
    the run argued for: the render is cheap and the ANSWER is not, since 1103
    lines is 60 KB of JSON, so the tool description now names `maxLines` as the
    remedy for a document already known to be huge. Also confirmed live: the
    tool refuses on a bridge without the capability, naming it; and it works
    under `user` as well as `expert`, since it is deliberately not stance-gated.
11.14. **Done (PR #55, 2026-08-16)** — E, the guidance never says how to get the
    application in front (server lane). Docs only. Ask 4 of
    [0027](specs/0027-the-first-external-run.md), which preserves all five asks
    of this run as received, with a traceability table — read it before deciding
    any of 11.15–11.17 is finished.
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
    the run dropped to PowerShell and Win32 `SetForegroundWindow`. The reporting
    agent's own read is that the scoping is
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
11.15. **Done (PR #60, 2026-08-16)** — E, speech and braille entries carry no
    time (both lanes). Ask 1 of
    [0027](specs/0027-the-first-external-run.md), and the run's strongest ask.
    An assertion of the form "X happened promptly after Y" is a
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
    stamp is taken in a pure domain entity against an injected clock. Spec:
    [0028-when-was-that-said.md](specs/0028-when-was-that-said.md) (agreed
    2026-08-16, implemented in the same PR). The field is
    `emittedAt`, and the spec adds two things the board did not carry: `monotonic`
    **stays** for the still-speaking heuristic rather than being replaced, and a
    stamp on *command* results is deliberately deferred until after 11.12, whose
    grace window is about to change what those results hold.
11.16. **Done (2026-08-22)** — E, no way to combine an action with its submit
    (server lane). Ships `run_sequence`: one MCP call carrying up to 32 steps of
    six kinds, with per-step bookmarks and ONE merged speech window. The class of
    behaviour that could not be tested at all is testable — a command with a 1.5 s
    finish delay can now be typed, submitted, waited on and interrupted inside a
    single call, because the steps are separated by a fraction of a millisecond
    rather than by two agent turns. Composition is over the bridge's existing
    commands, so no wire change, no bridge change and no add-on rebuild. `outcome`
    is three-valued: a `wait_for_speech` step that timed out reports
    `trigger_not_found`, which is neither `completed` nor `failed`. The tool is
    advertised like every other and carries the third gating value — *gated by its
    steps* — with the whole plan validated against the session's capabilities
    before the first keystroke is delivered.
    **The "absorbed by 11.12" marking of 2026-08-16 was withdrawn the same
    day**, on reading spec 0025 in full. 0025 solves a *larger* problem — a grace
    window collapsing act/settle/listen from three round trips into one — and
    because it is larger it looks like it must cover this too. It does not: it
    makes each intention cheap, it does not let two intentions travel together,
    so `typeText` then `pressGesture ["enter"]` remains two calls. This entry's
    own blocking case therefore survives 0025 intact — a command that finishes in
    1.5 s still cannot be interrupted, because two agent turns still elapse
    before *stop* can be sent.
    0025 should be judged on what it claims, which is well measured; it simply
    must not be allowed to close this. Reinstated with the two asks it carries —
    the `waitForSpeech` step that makes act-on-trigger fall out (0025 rejects the
    `until:` *parameter* shape, on a sound argument that does not reach a
    sequence *step*), and `type_text replace: true`. See
    [0027](specs/0027-the-first-external-run.md), asks 3, 3b and 5, all now
    reading **unmet**. **Sequence after 11.12**, whose grace window changes what a
    sequence step should return and would otherwise be designed against twice.
    Every
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
    all, delete, type is a sequence.
    Spec: [0036-one-call-several-intentions.md](specs/0036-one-call-several-intentions.md)
    (**agreed 2026-08-22**; it rode on this entry's implementing branch and merged
    with the PR, carrying nine layout amendments made while implementing). The tool is
    `run_sequence`. Two of the 2026-08-15 decisions are amended in it, both
    because spec 0025 was agreed the day after them: the **trailing read step is
    narrowed to an orientation read** (focus, optionally braille), since 0025 put
    speech on every mutating result and the sequence's own merged window already
    spans the whole plan; and the **"no capability of its own" question is moot**,
    since 0022 removed the visibility gate entirely on 2026-08-19 — capability is
    a per-call check now, so the plan is validated up front and the tool is
    advertised like every other.
    **What the live run added** (NVDA 2026.1.1, 2026-08-22, both capture modes),
    which is the half no automated tier reaches: the untestable scenario really is
    expressible — a say-all started, left running 1.5 s and interrupted by a
    keystroke, all inside ONE call, with nothing arriving after the plan closed.
    Against a real reader the per-step spans partitioned the merged window exactly
    (`2→2→5→13→13→17→17` over a merged `[2,17)`, every index present once). A
    refused plan delivered no keystroke **and spoke no announcement** — verified by
    the speech index not moving across two malformed plans, one of which carried an
    `announce` the human would have heard. `trigger_not_found` came back as an
    ordinary successful MCP result naming the waiting step, with the remaining
    steps absent from `steps` entirely. `state` moved `none` → `browse` → `none`,
    sampled after the last step each time. `screenreader://tools` rendered the
    third gating value under its own `## Gated by its steps` heading, claiming no
    capability. The braille half of the read step could only be exercised, not
    confirmed: no display is attached to this machine, so its window was legitimately
    empty while its own index space advanced independently of speech.
    The run also **opened 11.29** — a pre-existing off-by-one in the bridge's
    `wait_for_speech` that this entry's start-mark amendment made reachable, and
    that costs the amendment its exact intended case.

11.17. **Done (PR #70, 2026-08-20)** — E, a toggle with no setter (both lanes).
    **Paired with 11.11** — same
    gesture, same confusion, two different sessions, and the remedies are
    complementary rather than competing: 11.11 gives the agent the *tone* it
    cannot hear, so it learns which mode it landed in; this gives it a way not to
    land in the wrong one at all. Neither makes the other redundant, because
    hearing the tone still leaves the toggle non-idempotent, and a setter still
    leaves every other earcon inaudible. Decide them together; they should not be
    built by two people who have not read both. Ask 2 of
    [0027](specs/0027-the-first-external-run.md).
    `NVDA+space` is a toggle and
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
    NVDA.
    Spec: [0033-a-toggle-with-no-setter.md](specs/0033-a-toggle-with-no-setter.md)
    (drafted 2026-08-20, **agreed 2026-08-20** — all three open questions settled
    there) — written alongside 0024's re-cut so the pair could be decided in one
    conversation, which is what this entry asked for from the day it opened. It
    carries a membership rule of its own (*a mode may be set only where the reader
    already gives its user a command for it — idempotence, never capability*),
    `browseMode` alone in the first cut with `speechMode`/`sleepMode` held back
    because those two can leave a human unable to hear their own machine, a result
    carrying the state AFTER plus `changed`, and setting-what-is-already-set doing
    literally nothing so a precondition costs the human no tone. This entry's
    set-domain asymmetry and its compare-inside-NVDA requirement are carried
    through verbatim.
    **The one question left for the conversation went the other way from the
    spec's own recommendation.** `setState` joins the `state` capability rather
    than taking its own, because the repo had already answered it: `getConfig` and
    `setConfig` both gate on `config`, and splitting the analogous pair would make
    an agent learn which pairs split. The asymmetry that is real here is PER FIELD
    — four modes reported, one settable, `"none"` readable and not settable — which
    a capability string cannot express and the set-domain rejection already does.
    A separate `StateWriter` port is still handed out, on that one announcement: a
    port called *inspector* that mutates is a mislabelled role.
    **One thing the spec did not anticipate, found while building:** `from_dict`
    IGNORES an undeclared field, so `setState {speechMode: "off"}` would have come
    back `changed: []` — indistinguishable from "it was already so". The three
    withheld modes are now refused BY NAME with the reason each is withheld.
    **Shipped as ONE PR with 11.11**, deliberately and for the reason the pairing
    exists: the two remedies are complementary, the live-mode question was settled
    once across both, and the second half of each is only judgeable at a real
    NVDA — two PRs would have bought shorter diffs at the price of two live
    sessions.
11.18. **E, the board is not self-enforcing** (neither lane; CI). Five
    consecutive entries merged without the Done mark their own PR was supposed to
    apply: 11.4 (#46) read "Next.", 11.5 (#48) "Implemented", 11.7 (#49) carried
    its spec as "not agreed" two weeks after shipping, and 11.8 (#51) merged
    reading "Implemented on this branch" — a branch that no longer existed —
    **on the very next merge after the board recorded that the next merge should
    be watched for exactly this.** Then 11.15 (#60) did it again, in the first
    merge after *this entry was written to record the pattern*: the whole
    implementation landed — bridge, server, wire, conformance, spec 0028 marked
    agreed — while the entry kept its unfinished heading, kept "awaiting
    agreement" in its Spec field, and stayed in the open list above, whose own
    count read twelve against a list of thirteen. Corrected 2026-08-16 by a
    direct push to main. That is the evidence that ends the "be more
    careful" remedy: the rule is load-bearing (a fresh session's first question is
    "what is next?", answered from this file) and it is not self-enforcing.
    Proposal: a CI job in the shape of the existing `no unchecked checkboxes`
    gate. A PR that touches `ROADMAP.md` fails while an entry whose text it
    changed neither carries a Done mark nor states why it does not — a spec-only
    entry, a deferral, a renumber. The escape hatch has to exist, because
    bookkeeping and renumbering PRs legitimately touch entries they are not
    completing; making it *stated* rather than *absent* is the whole point.
    Open question for the spec conversation: whether the check can be made
    precise enough to avoid crying wolf, since a false failure on a docs PR would
    train everyone to bypass it — which is worse than no gate.
    **On hold as of 2026-08-16: the remedy above is being reconsidered, and this
    entry may be replaced rather than specified.** A CI gate checks that a human
    performed the bookkeeping. GitHub's `Closes #n` makes the status change a
    side effect of merging instead — nothing to remember, nothing to verify, no
    false failures to train anyone to bypass. The direction under discussion is
    to move the *status bit* to issues while the *argument* stays in this file,
    reviewed and in git, still the answer to "what is next?"; the two are then
    reconciled by a drift gate of the same shape as `gate-schema` and
    `gate-binding`, which cannot cry wolf because both sides are machine-readable.
    That is a next-phase conversation. Do not build the gate above without
    revisiting this first. Spec: none yet.
11.21. **Done (PR #64, 2026-08-18)** — E, the settle answers about emission, not
    about audio (lane 1, bridge; small). Found live on 2026-08-18 running 11.12's
    checklist. Spec 0025 narrowed
    `waitForSpeechToFinish` to "a long deliberate announcement or a say-all, where
    *is it still going?* is genuinely the question" — and the live run found that
    it cannot answer that either. In LIVE mode NVDA queues a say-all in bursts:
    the whole first chunk was captured by 11:10:40.611 and nothing more was
    emitted, while the synthesizer was still reading it aloud for several seconds.
    The buffer's heuristic measures the gap since the last CAPTURE, and capture
    happens at `pre_speechQueued`, so the tool reported `finished: true` while
    the user could plainly hear speech continuing.
    **Not a regression, and not caused by 11.12** — it is the "emitted is not
    heard" caveat (protocol.md §7.1) reaching the one tool whose entire job is to
    answer a question about audio. What 11.12 changed is that the caveat now
    matters more: with the settle no longer the universal second step, its
    remaining use case is precisely the one it is worst at.
    **Shipped (a) and (c) together**, through a new `ContinuousRead` port named
    for the general property rather than for NVDA's command: **nothing above the
    bridge learns that say all exists.**
    (c) took two attempts, and the first is worth recording because it passed
    every automated tier. `SayAllHandler.isRunning()` is the obvious call and is
    the wrong one: it is `bool(self._getActiveSayAll())`, a **weakref to the
    reader object**, assigned when a read starts and never reset — so it answers
    "has the reader been garbage-collected yet?", and `_Reader` inherits
    `garbageHandler.TrackedObject`, which is expressly about objects reclaimed by
    the *cyclic* collector rather than by refcounting. Live, that settle went on
    answering "not finished" after the document ended and after a keypress that
    stopped the read: **a settle that never settles, which is worse than the
    imprecision it replaced.** The unit tests all passed, because the fake
    answered honestly and the flaw was in what the real signal MEANS — so the
    adapter now has tests of its own, against a stubbed `speech.sayAll`, holding
    the state that broke it: a reader object present but stopped.
    What it reads instead is the reader's own guard field — `_TextReader.reader`,
    `_ObjectsReader.walker`, each nulled by its own `stop()` and checked by it on
    entry — set on both routes out, normal completion and interruption. Private
    attributes, but they fail closed: a rename returns None and the settle falls
    back to the pre-11.21 heuristic. A rename cannot produce the hang.
    The buffer also caps how long a claimed read may hold the settle open with
    nothing arriving (`CONTINUOUS_READ_STALE_SECONDS`, 6 s), because we have now
    shipped one wrong version of a port that speaks for a reader we do not
    control: a wrong answer that expires is an imprecision, one that does not is
    a hang. No tool, no parameter, nothing on the wire names it — an agent
    still starts one by pressing the reader's own key, and only the ANSWER to a
    question the wire already asked gets better. A bridge whose reader has no
    such notion returns False and keeps today's behaviour exactly.
    Two further traps, both silent, both now covered: `SayAllHandler` is a module
    attribute REBOUND by `initialize()`, so importing the name by value captures
    `None` for the life of the process; and it is `None` before initialize runs.
    **Measured live, and it makes the original bug bigger than this entry first
    recorded**: chunks arrive **1.8–2.0 s apart, for every one of thirty lines**
    under ibmeci. So the 1 s rule did not misfire once at the start of a say all
    — it misfired on every gap in it, and a whole document could be reported
    finished at line 1.
    (a) shipped alongside, because (c) fixes continuous reads and nothing else:
    the description now says the tool measures speech ARRIVING rather than audio
    playing, and that any other bursty producer will still read as finished. (b)
    stays rejected — spec 0008 gave up the spy synth deliberately, and this
    closes the gap without it. Spec: none needed.
11.22. **Done (PR #65, 2026-08-19)** — E, an agent cannot see the tools it is
    allowed to call (server lane, docs + resource). From the **second external
    run**, 2026-08-18 — see
    [0030](specs/0030-the-second-external-run.md), ask 1b. The gated tools exist
    after `connect_reader` and can be called, but the agent has no authoritative
    list of their names, parameters and return shapes in front of it. The
    reporter's account of what that costs is the entry's whole justification:
    **it read the Go source**, and says so plainly — *"fix that and I won't"*.
    Proposes a single `screenreader://tools` resource: every tool, the capability
    that gates it, its parameters and what it returns, reader-agnostic, served
    for reading. Distinct from 11.6, which is about the CLIENT's tool list going
    stale; this is about the SERVER publishing the same information as a document,
    which works no matter what any client does with `tools/list_changed`. That
    independence is the argument for doing this one first. The obvious hazard is
    drift — a hand-written cheat-sheet that disagrees with the registry is worse
    than none — so it should be composed from `tools.BuildRegistry()` the way
    `screenreader://guidance` composes persona profiles from the domain, and
    guarded by the same kind of test. **Taken before 11.6 on 2026-08-18** — see
    the reprioritisation note under Convergence. Spec:
    [0031-the-tools-describe-themselves.md](specs/0031-the-tools-describe-themselves.md)
    (**agreed 2026-08-18**). The spec's one real design decision is that
    *"what it returns"* cannot be composed from anything that exists: the `Tool`
    interface describes its input and says nothing about its result, so the
    schemas are hand-written behind a new `OutputSchema()` the compiler forces
    every tool to answer — and the same method feeds the SDK declaration, so the
    document and the client's tool list cannot disagree. **Ships as one PR**, not
    the two the spec first proposed: the ask is one ask, the second half would
    rewrite the first, and the bulk is compiler-forced and mechanical (0031
    Part 6). Headless throughout — no add-on rebuild, so no live-NVDA checklist.
    **Shipped as specified.** `screenreader://tools` is composed at read time
    from the registry the server is actually running, with the gate read from
    `Catalog()` — so the hazard the entry named is answered by construction, and
    three tests hold it there: the frame names no tool, every tool appears
    exactly once with the capability the catalog gives it, and both schemas in
    the document equal the tool's own. `Capability.Meaning()` puts the
    capability's one-line gloss on the entity, and `output_schema_test.go` walks
    every declared output schema against the result struct it describes. **It
    does not close 11.6**, which remains open with all four options untouched:
    this publishes the information as a document, and what a client does with its
    own tool list is still that entry's question. Spec amended in the same PR
    (5.4): two small layout departures, `AllCapabilities()` and a new rather than
    modified `tool_binding_test.go`.
11.23. **E, a session dies while the agent is thinking, and nothing says so**
    (both lanes). From the second external run, ask 2. The ~120s inactivity
    watchdog dropped a live silent session while the agent was reasoning between
    tool calls; it learned only when the next call failed with "needs a connected
    reader", and the recovery cost a reconnect and a hand-off to the human.
    **The reporter explicitly agrees the policy is right** — `ping` proving
    liveness without resetting the watchdog is what protects a human from being
    left mute by a wedged agent (the reason the watchdog exists at all). So this
    is about VISIBILITY, not about relaxing the timeout: an agent's idle time
    between calls is exactly when it reasons, and the clock runs invisibly
    through it. Three candidates offered, not yet weighed: `status` reports
    seconds remaining; the bridge warns once before dropping; or an explicit
    `keepalive` whose absence is cheap to notice. Note the tension to resolve
    before choosing — a `keepalive` an agent may send at will is a watchdog it
    can defeat, which is the thing the current policy deliberately prevents.
    Spec: none yet.
11.24. **Done (PR #69, 2026-08-20)** — E, two small promises the caller cannot check (both lanes, small).
    From the second external run, ask 3. Two unrelated defects, kept together
    because both are about a caller being able to trust what it was told.
    (a) `press_gesture`'s description spells a gesture `"NVDA+f7"` while
    `screenreader://reader-guidance` correctly gives the literal form as
    lower-cased and sorted (`"nvda+tab"`). The lower-cased form works; the two
    documents simply disagree, and the one an agent is likelier to copy is the
    wrong one. A documentation defect of exactly the class an outside reader
    finds and an inside one cannot. (b) `announce` on `press_gesture`/`type_text`
    returns nothing acknowledging that the announcement was made, so an agent
    narrating to a human it cannot hear is assuming rather than confirming —
    which matters most in the silent sessions where narration is the human's
    only channel. An `announced` field in the result would close it.
    **What such an ack must not overclaim**, measured 2026-08-18 and recorded in
    protocol.md §7.1: emission runs **two to three utterances, about five
    seconds, ahead of audio**. So an ack can honestly say the announcement was
    *made*, never that it was *heard*, and an agent that narrates then acts at
    once is acting ahead of its own narration. Whether the remedy is a field or a
    way to wait for the listener to catch up is the thing to settle rather than
    assume.
    **(a) folded into 11.6 on 2026-08-19** and is no longer part of this entry:
    spec 0022 A.6 makes it an instance of a rule — the server names no reader's
    syntax in the text an agent reads — rather than a spelling to correct, and
    A.7 adds the test that enforces it. **What remains of 11.24 is (b) alone.**
    **(b) Done 2026-08-20.** `announced` echoes the narration back on both
    mutating results, omitted when none was asked for, so "you did not narrate"
    stays distinguishable from "your narration vanished". The half nobody had
    named closed with it: a whitespace-only `announce` was dropped by the
    bridge's own `strip()` and reported nowhere, so an agent that MEANT to
    narrate got the exact outcome of one that did not — it is now refused, before
    dispatch, exactly as the `announce` tool has always refused it. The ack says
    the announcement was *made* and never that it was *heard*, in those words, in
    both schemas and in `screenreader://guidance`. The alternative remedy this
    entry left open — a way to wait for the listener to catch up — is **named and
    not built**: the bridge captures before the synthesizer, so it has no view of
    audio at all, and that needs NVDA's synth index callbacks, its own spec and
    its own measurement.
    Spec: no new one — [0025](specs/0025-one-round-trip-per-intention.md)
    Part 3.4 gave the announcement its ride and owed it an answer; the amendment
    of 2026-08-20 rides in this PR.
11.25. **Done (PR #68, 2026-08-20)** — E, the silence cap did not hear the
    announcements it was built to notice (lane 1, bridge; small). Found live on 2026-08-20, the day after
    11.10 merged, in a silent session driving acter. The session narrated
    constantly and was warned at 45 s and un-muted at 90 s anyway.
    `nvda.log` dates every cue tone, so the run is unambiguous: announce's 660 Hz
    pairs at 09:56:19, :27, :37, :42, :59 and 09:57:07, the cap's 880 Hz pair at
    09:56:34 and again at 09:57:19. The clock had been reset exactly once, by a
    standalone `announce` at 09:55:49, and the warning landed 45.0 s after it to
    the tenth of a second.
    **A gap between two specs rather than a fault inside either.** Spec 0032
    Part 2 defines the resetting set as "exactly the set of things that get past
    the suppression" and names three: the start cue, `announce`, `askUser`. By
    then 0025 had added a fourth — the announcement carried on the command that
    acts — and `setLogLevel` a fifth. All of them reach the synth through
    `Announcer.announce`, so the human hears them; none of them told the cap. The
    definition was right and only two of its five members were wired up.
    **The harm is worse than a bound that fails to bind.** An agent that narrates
    the way the guidance tells it to — say what you are about to do, on the
    command that does it — was the one the cap fired on, while the notice it
    heard ("speech will be restored shortly") contradicted the narration it was
    hearing at the same time. A safeguard that misfires on good behaviour teaches
    the human to distrust it.
    **Remedy: make the definition mechanical rather than remembered.**
    `SessionContext.announce_to_human` speaks and notes the reset in ONE call,
    and every announcement site goes through it. Behavioural tests cannot see the
    difference — a handler that spoke past the funnel would pass all of them — so
    an AST check over the commands package fails the build if one ever does
    again, in the shape of `test_buffer_purity.py`.
    Spec: none — 0032 Part 2 already decided this; the code did not implement what
    it decided.
11.26. **Done (PR #71, 2026-08-21)** — E, the schema the client holds (server
    lane; no live NVDA, and the first entry in a while with no live checklist).
    **Two of the draft spec's four ship items were already built**, which is the
    part worth carrying forward: 0031's `screenreader://tools` has published
    every tool's full input AND output schema, composed from the registry, since
    PR #65, with an integration test asserting per tool that the published schema
    equals the tool's own. The draft proposed adding a parameter summary to
    `ToolGate` and was written from the board entry rather than from the code. It
    was withdrawn on agreement as a second publisher of a published fact, and
    what shipped in its place is one paragraph of the frame: the document never
    said the property that makes it worth reading at the moment of a puzzling
    argument error — **a resource is read live, a tool list is cached**.
    So what shipped is the hint (`params.go`, type mismatches only), the frame
    paragraph, and three corrected texts: `redeploy.py`, `AGENTS.md` and
    `sdk_server.go`. The scope of the hint shrank too, and for a fact rather than
    a preference: `decodeParams` uses a plain `json.Unmarshal`, so unknown and
    missing fields never produce an error at all — **type mismatch and malformed
    JSON are the only two errors it can return**, and `params_test.go` pins the
    silence so the limit is a property of the code.
    The original finding, kept because it is the argument: Found
    during the 11.11/11.17 live run (PR #70), and not by looking for it: a
    checklist item could not be performed. The server gained ONE optional
    parameter, `normalize` on `connect_reader`, and was redeployed; the next call
    sent `"normalize": "true"` — a **string** — and failed on unmarshalling. The
    client was serialising against the `inputSchema` it had cached, which did not
    declare the field at all. `/mcp reconnect` fixed it immediately.
    **This is not 11.6 again, and the difference is the entry.** Spec 0022 (c)
    made the tool LIST a constant, which removed every reason it could change
    *within a build* — but `poe redeploy` replaces the build, and a schema inside
    an unchanged list went stale. `sdk_server.go` currently claims 0022 (c)
    "closes board entry 11.6 for BOTH of the failures wearing its symptom",
    naming `poe redeploy` first; that claim is half wrong and is corrected by
    this entry rather than left for a future session to trust.
    **It is worse than a missing tool, because it fails quietly.** An invisible
    tool cannot be called, so the agent notices. A stale schema lets the call
    happen and fails *typed*, in the vocabulary of JSON rather than of staleness.
    The dangerous case fails not at all: a parameter the client does not know
    about is simply never sent, the server applies its default, and a successful
    call means both "the caller chose the default" and "the caller could not have
    chosen anything else".
    A server cannot refresh a client's cache and cannot tell staleness from a
    plain mistake, so what ships is legibility, not a cure: correct the
    `redeploy.py` instruction (which currently says, in the imperative, to
    reconnect ONLY for an added or removed tool — the advice that would have cost
    this session), attach an honest hypothesis to a **type-mismatch** decode error
    only, and publish each tool's parameters in `screenreader://tools` — a
    RESOURCE is read live and never cached, so it is the one channel that always
    describes the running build.
    Spec: [0034-the-schema-the-client-holds.md](specs/0034-the-schema-the-client-holds.md)
    (agreed 2026-08-21, amended in place on agreement — the amendments are marked
    and every one of them makes the spec smaller).
11.27. **Done (PR #72, 2026-08-21)** — E, attendance is declared, not derived (both lanes; small). From a
    question asked during the same run — *is the agent warned whether the machine
    is unattended?* — whose answer is **yes, already** (spec 0032 ships it at
    connect in a required field, in all three states). Finding out WHY produced
    this entry.
    The bridge's setting is `unattended`; it computes `enabled = not unattended`;
    **the wire carries only the derived `enabled`**; and the server renders
    "UNATTENDED" by inverting it back. That is lossless today — a bijection — so
    **nothing is broken, and this entry must not be read as a bug report.**
    It is fragile in one direction, and it is the harmful one. The inversion holds
    only while `unattended` is the SOLE input to `enabled`. A user who turns the
    cap off because the 90-second lift disrupts them is sitting right there and
    would be reported as an empty room; a JAWS or TalkBack bridge with no cap
    machinery must either claim a cap it does not run or have every session told
    nobody is listening. Wrong towards "attended" costs round trips; wrong towards
    "unattended" tells a well-behaved agent to STOP NARRATING to a blind person
    who is there — the harm 0032 exists to prevent, reached from the other end.
    The bridge already reasons from that asymmetry when it READS the setting
    (defaulting to attended, and logging when it cannot parse it) and then
    discards the reasoning when it TRANSMITS it.
    Ships `attended` as a sibling of `silenceCap` at `hello`, absent as a third
    answer, with today's inference kept as an explicit COMPATIBILITY path for an
    older bridge. Not inside `SilenceCapInfo`: nesting the cause in the effect is
    the belief being corrected. Read-only, for 0032's reason, and no new
    capability, following 0033's precedent.
    Spec: [0035-attendance-is-declared-not-derived.md](specs/0035-attendance-is-declared-not-derived.md)
    (drafted 2026-08-21, **agreed the same day**, and landing with this PR — it
    had spent a day on a branch, because AGENTS.md says a spec merges with the PR
    that implements it and 11.26 was implemented first, so the branch the two were
    drafted on became 11.26's).
    All three of its open questions closed on agreement: **`attended`** on the wire
    rather than `unattended` (a positive assertion makes a forgotten field arrive
    as *absent* rather than as an accidental empty room); **connect only**, since
    attendance is fixed for the session like mode and persona; and the cap's
    `enabled` **stays derived** from the one setting, because splitting it is a
    second checkbox in the control dialog and that is a config decision for the
    human at the reader.
    Two amendments rode the implementation, both in the spec's own layout table.
    The negation moved to **`plugin.py`** rather than being carried out of the cap
    entity — reading `unattended` once into a local and using it twice, side by
    side, instead of putting a fact inside a structure named for something else,
    which is the shape the entry exists to reject. And the value has to cross four
    hops, not two, so `wiring.py`, `session.py` and `session_context.py` joined the
    table.
    `SilenceCap.Sentence` now **takes attendance as an argument**, so a caller
    cannot render the sentence without having considered the fact; the compiler
    found every call site. The five-row table is pinned in unit tests, including
    the row that could not be expressed before — **attended but uncapped**.
    The conformance tier declares the one pair that discriminates (a human present
    at a machine that bounds nothing) and was **verified non-vacuous**: flipping
    the harness's declaration fails it. An agreeing pair would have passed under
    either implementation.
    **What the live run added, and it is the half no automated tier reaches**:
    `attended = not unattended` lives in `plugin.py`, which imports NVDA and so is
    exercised by nothing headless. Checked against NVDA 2026.1.1 through the
    control dialog's own checkbox, in both directions, and the compatibility path
    was checked against a **genuinely older bridge** — the pre-0035 build still
    installed at the start of the run, whose `HelloResult` has no such field.
11.28. **Done (2026-08-27)** — E, a flaky integration test — the named-pipe
    roundtrip times out under full-suite load (neither lane; bridge tests). Observed once on 2026-08-21,
    during the `poe dev` run that gated the AGENTS.md split:
    `tests/integration/test_named_pipe_session_roundtrip.py::test_a_whole_session_over_a_real_named_pipe`
    failed with `AssertionError: no reply from the bridge within timeout`. It then
    passed **2/2 in isolation** and in **three later full `poe dev` runs** on the
    same checkout. It is unrelated to the pyright work that landed in 10477fd and
    to the documentation split that opened this entry; **it is recorded rather
    than fixed**, because that PR is documentation-only and a timing fix is code.
    **What is known, and it is deliberately little.** The helper is
    `_read_reply(agent, timeout=5.0)`, which sets a deadline from
    `time.monotonic()` and reads past poll-timeouts until the bridge answers. That
    is a **wall-clock budget**, so it is spent by anything that delays the reply,
    including the machine being busy with the rest of the suite — which is the
    one condition under which it has ever failed. The same helper, with the same
    5.0s default, is duplicated in `test_socket_session_roundtrip.py` and
    `test_wire_session_roundtrip.py`, so whatever this is, it is a property of the
    **shape all three share** and not of the pipe leaf. Neither has been seen to
    fail.
    **What is NOT claimed.** That the product is fine. A single failure that will
    not reproduce is exactly as consistent with a real race in the connection
    stack — accept, handshake or dispatch — as with a starved test process, and
    nothing gathered so far separates the two. The reason to write it down is the
    asymmetry: an intermittently red gate teaches people to re-run it, and the
    next occurrence will be read as "that flaky one" by whoever has read this
    entry, which is how a real bug gets to hide inside a known-flaky test.
    **What would settle it**, roughly in cost order: capture WHERE the budget goes
    (log the elapsed time and the last message on the failing path, so a failure
    says whether the bridge answered late or not at all); decide whether a
    fixed wall-clock deadline is the right instrument for a test whose subject is
    a real OS IPC leaf, or whether these three tests should share one helper with
    a load-tolerant budget; and only then consider whether anything in the
    connection stack can actually lose or delay a first reply.
    **What shipped, and what deliberately did not.** The flake is not fixed; it
    is made diagnosable, which is all spec 0039 claims. `_read_reply` was
    BYTE-IDENTICAL in all three roundtrip tests, so it became one
    `tests/support/roundtrip.py` — and its budget stopped being wall clock. It
    now counts **polls that returned `Timeout`**: the question a test asks is
    "how many chances did the bridge have to answer", and that coincides with
    elapsed time only while this process is scheduled, which is the one
    condition in doubt. The budget is the same size (100 polls at 0.05 s is the
    5.0 s it replaced) because **making it more generous is the single change
    that could hide a real fault**. A 60 s wall-clock backstop remains, since a
    poll budget can never expire if nothing polls, and hitting it reports as a
    different finding — the transport stopped answering, not the bridge stayed
    silent. No production code was touched, no retry or skip was added, and the
    connection stack was not audited: that is the entry's third step and it
    waits for a failure that names its own site.
    **Two things the implementation settled.** A dropped first reply is ruled
    out by construction, not by argument — `read_message` drains buffered lines
    before touching the transport and `_LineReader` keeps a partial across
    polls — which removes the most attractive "real race" candidate. And the
    eight exchanges in the failing test are not equally at risk: seven expect a
    sub-millisecond answer, while `waitForSpeechToFinish` blocks bridge-side for
    `SPEECH_FINISHED_SECONDS` (1.0) on a real clock, so it is the only one where
    a scheduling delay compounds with a genuine wait. It is the one to bet on
    and was deliberately not "fixed", since betting is what this closes.
    Spec: [0039](specs/0039-a-flake-that-says-where-it-went.md)
    (**agreed 2026-08-27**; rides in this entry's PR, with one amendment made
    while implementing — the promised "was a message skipped?" element does not
    exist, because `read_reply` returns the first non-`Timeout` message, and the
    per-poll average took its place as the load discriminator).
11.29. **Done (2026-08-23)** — E, `wait_for_speech`'s `after_index` is exclusive
    where every other index in this system is an inclusive left edge (lane 1; the
    bridge). Shipped in ONE PR with 11.30, at the maintainer's request: two
    unrelated defects from the same live run, each a handful of lines, neither
    worth holding a lane open for. Found by
    11.16's live checklist on 2026-08-22 against NVDA 2026.1.1, and **not
    introduced by it**: 11.16 only made the boundary reachable, by having a plan's
    trigger match from the plan's own start mark.
    **Measured, three calls, one session.** `get_speech(since_index=22)` returns the
    utterance sitting AT index 22. `wait_for_speech(after_index=22, "Log")` does not
    see that same utterance and answers `found: false`. The same wait with
    `after_index=21` finds it, reporting `index: 22`. So the wait scans history
    correctly and the left edge is the one thing wrong: it matches `index >
    after_index` where `get_speech` matches `index >= since_index`.
    **Why this is its own entry rather than a note on 11.16.** It bites the ordinary
    documented pattern, with no sequence involved. `get_next_speech_index` is "the
    index the NEXT captured utterance will take", and every description teaches:
    bookmark, act, pass that bookmark as `after_index`. Under an exclusive edge that
    silently discards **the first utterance the action caused** — precisely the one
    being waited for. It fails as a TIMEOUT rather than an error, so it reads as
    "the reader never said it" and points nowhere near the boundary.
    Inside `run_sequence` the same off-by-one costs the amendment its exact case: a
    plan whose trigger arrives as the plan's FIRST utterance cannot match, which is
    the "arrived a fraction of a millisecond early" case the amendment exists for.
    Observed live — a plan pressing the report-title command and then waiting for a
    word of that title answered `trigger_not_found`, with the matching utterance
    sitting in its own merged window.
    **Which side drifted is not in doubt; the fix is not therefore obvious.** The
    repo's convention is a half-open `[from, to)` window with an inclusive left
    edge, and the tool description says "at or after this index", so the bridge is
    wrong rather than the document. What needs deciding is whether to change the
    comparison in a shipped command — any caller that has been compensating for it
    would feel that — or to change every description and the documented pattern to
    say "strictly after"; and, if the former, whether `wait_for_log` shares the
    shape and should move with it.
    **Decided 2026-08-23: the comparison moves.** Two things found while writing
    the spec settled it. The server's own fake ALREADY implements the inclusive
    edge — `fakes/speech_reader.go` loops from `*wait.AfterIndex` — so every
    server-side unit test has been asserting inclusive behaviour against an
    inclusive double while the real bridge was exclusive. That is `AGENTS.md`'s
    stated limit of hand-written fakes, *"what they cannot prove is that the real
    adapter behaves like the fake"*, happening for real, and it means the fix
    makes the bridge agree with what the server was already tested against. And
    the conformance test COULD NOT have caught it: it asserted only
    `waited.Index >= before.Index`, which passes under both edges, while its own
    header claimed to be "the one place index arithmetic crosses the language
    boundary". That assertion is now the discriminating one — it waits for the
    FIRST line the gesture caused, which sits exactly at the bookmark.
    **`wait_for_log` does NOT share the shape and did not move**: `find_since` is
    already inclusive (`first = max(start, self._oldest_position)`) and is reached
    by a differently-named `sincePosition`. So the entry was speech-only and
    smaller than this board allowed for.
    Spec: [0037](specs/0037-the-inclusive-left-edge.md) (**agreed 2026-08-23**).

11.30. **Done (2026-08-23)** — E, attendance is stated once, at connect, and can
    never be asked for again (lane 2; the server). Shipped in one PR with 11.29;
    see that entry. Opened 2026-08-22 by the conversation following
    11.16's live run, from the question "can the agent know whether the machine is
    attended?".
    **It can, and only there.** `connect_reader`'s `silenceCap` is the single place
    an agent learns whether a human is at the reader. It is deliberately one
    sentence rather than a flag — the struct says why, and that decision is not
    what this entry questions — and it gives three answers: attended, unattended,
    or a reader too old to declare it (which resolves towards narrating). `status`
    does not carry it: `suppressing` answers a different question, whether speech
    is being withheld right now. `screenreader://info` does not carry it either.
    **Attendance is fixed for the session, but the agent's memory of it is not.**
    Spec 0035 made it connect-only for a good reason — it cannot change while a
    session lives, so there is nothing to re-read *in the reader*. What can change
    is who is holding the fact: a context that has been compacted, a sub-agent
    handed a live session, a session picked up after a restart. None of them can
    recover it, and the only route back is to disconnect and reconnect — throwing
    the session away to ask a question about it.
    **Why this fact rather than any other the connect result carries.** Losing it
    fails towards silence at an occupied machine. An agent that cannot remember
    whether anyone is listening, and reasons carefully from what it has, concludes
    it should not waste round trips narrating — which is exactly the wrong answer
    for a blind person sitting in front of a reader that has gone quiet. Every
    other field in that result fails towards an ordinary mistake.
    **No wire change is needed**, which is what makes this small: the server
    already holds the sentence in its own `ReaderSession` for the life of the
    session, so re-publishing it costs no traffic to the bridge.
    Open for the spec conversation: **where it belongs.** `status` is the obvious
    home and may be the wrong one — a resource is read live and never cached, and
    `screenreader://info` already exists to answer "what is true of the session in
    front of me", which is precisely this question; an agent can read a resource
    without spending a tool call or asking the human for anything. Whether it
    should be the same prose in both places, or whether one of them wants a
    shorter form, is the other half of the same question.
    **Decided 2026-08-23: `screenreader://info`, and the same sentence.** The
    resource's own header already argued this case for a different fact — a
    resource was chosen over `initialize.instructions` because *"instructions are
    frozen at handshake time… a resource is read when the agent wants it and
    always describes the session that exists now"* — and an agent recovering from
    a compaction is that argument a second time. It also sits with `persona`,
    which is there because "what am I driving" and "what am I standing in for" are
    one question; "is anybody listening" is its third form. `status` was weighed
    and lost: its fields are per-moment (`suppressing` is the one that already
    attracts this confusion) where attendance is fixed for the session, so a
    constant beside live readings invites re-polling. The honest counter — that a
    lost agent reaches for a tool sooner than a resource URI — is recorded in the
    spec's limits as a GUIDANCE question, not a reason to duplicate the fact.
    Both surfaces render through the one `SilenceCap.Sentence`, with an
    integration test as the tripwire.
    Spec: [0038](specs/0038-attendance-you-can-ask-for-again.md)
    (**agreed 2026-08-23**).
11.31. **Done (2026-08-27)** — E, the READMEs describe a server we stopped
    shipping (neither lane; documentation). An audit of all four READMEs against
    the running surface — the 26 tool controllers in
    `server/domain/controllers/tools/`, the 5 resource adapters in
    `server/adapters/mcp/`, and the bridge's own command registry and dialog —
    found them behind by between one entry and the entire Go rewrite.
    **The worst of it was not an omission but a retired rule still taught as the
    headline.** Both the root and the server README described capability-gated
    tool *visibility*: four tools before a session, the rest appearing on
    connect, withdrawn on disconnect. Spec 0022 retired that on 2026-08-19 —
    every tool is advertised from startup and nothing is withdrawn — and the
    server README carried it under a section header calling it *"the single most
    confusing thing about the server"*, which is exactly how confidently wrong
    documentation reads. This is the misconception AGENTS.md records as having
    cost one session an entire live checklist and trapped a second, external
    agent; leaving it in the two documents a new reader meets first was the
    single highest-cost thing in the repo that nobody had noticed.
    **`connect_reader`'s documented signature was wrong**, which is worse than a
    gap because it fails on first contact: the root README named the reader, the
    capture mode and an optional log level, while `persona` has been **required**
    since 11.19 (spec 0029, 2026-08-17). `normalize` was undocumented too.
    **What had shipped and was never written down**, per document:
    - root README: `get_document_snapshot` (11.13), `set_state` (11.17),
      `screenreader://tools` (11.22 — it said "four documents", there are five),
      personas at all beyond one passing mention, the silence cap and attendance
      (11.10, 11.25, 11.27, 11.30), and the fact that `press_gesture` and
      `type_text` return their own speech window (11.12). That last one made its
      worked example *wrong*, not merely dated: it taught press → settle → read,
      the three-call loop 11.12 replaced, while `wait_for_speech_to_finish`'s own
      description says in capitals that it is not the step after every action.
      `get_next_speech_index` was described by the job it no longer has.
    - server README: `screenreader://reader-guidance` and `screenreader://tools`
      (it said "three documents"), persona, and the schema half of the reconnect
      rule (11.26 / spec 0034) — including that an agent can read
      `screenreader://tools` itself rather than asking the maintainer.
    - bridge README: personas and the resolved-from-NVDA gesture tables (11.19,
      11.20), `set_state` (11.17), the document snapshot (11.13), channel
      normalisation (11.11), and the silence cap entire (11.10, 11.25, 11.27).
      It also said the control dialog *"has four things in it"* when it has
      seven, and that *"both preferences"* are stored when there are five. This
      is the document that ships into the `.nvda-addon` as the Help an NVDA user
      reads in the Add-on Manager, and the omission was the one thing a blind
      user most needs to know before installing: that the silence has a ceiling,
      what it is, and that they set it.
    - `shared/README.md`: untouched since the first commit. It described the
      server as *"desktop CPython"* — Go since spec 0013, 2026-07-22 — and rested
      the contract on *"both sides run the exact same bytes"*, a guarantee that
      stopped existing when the Go binding started being generated from
      `specs/wire/v1/schema.json`. It named neither the two drift gates nor the
      conformance tier that replaced it.
    **Why this happened, and it is 11.18's shape rather than carelessness.**
    Every PR flips its own ROADMAP entry because a rule says to and a reviewer
    can see it; nothing says to update the README, and no gate can see that one
    was not. So the board stayed accurate on main while the prose drifted for
    three weeks, entry by entry, each PR leaving a gap too small to be worth its
    own objection. **Recorded rather than remedied here**, because a remedy is a
    gate and this PR is documentation: whether it can be a check at all is the
    same open question 11.18 is on hold over, and the two should be settled
    together rather than one inventing a mechanism the other is reconsidering.
    Spec: none — a correction to documentation against the shipped surface,
    adding no design decision. The audit that scoped it is in the PR body.

11.34. **Done (2026-08-28)** — neither lane (dev tooling, tests, CI), the server
    is everywhere and a bridge is somewhere. Opened on 2026-08-28 by the first
    attempt to work this repo from macOS, and closed in the same session.
    **What was actually broken was small, and what was WRONG was larger.** Of the
    whole task list, exactly one thing failed: `poe bridge` aborted during
    collection, because `test_named_pipe_session_roundtrip.py` and
    `test_live_nvda_pipe_e2e.py` import an adapter whose module body calls
    `ctypes.WinDLL`. `shared`, `types`, `lint`, `go` (including `-tags
    integration`), `gates`, `conformance` and even the `.nvda-addon` build were already
    green on macOS — the Go half had been written portable on purpose, with
    `//go:build conformance && windows` and a `py`-launcher candidate added only
    `if runtime.GOOS == "windows"`. What was wrong was the PYTHON tooling's
    silent Windows assumptions: the doctor warned about `pwsh` (a Windows
    PowerShell 5.1 concern), and warned that the conformance tier would fail for
    want of a `py` launcher **while the tier itself passed** — the Go probe finds
    the workspace venv's 3.13 on `PATH`, so the doctor was speaking for a tier
    without asking that tier's question. `redeploy.py` enumerated processes with
    `Get-CimInstance` and killed with `taskkill`, so on macOS it silently killed
    nothing and reported success.
    **The most expensive finding was the one nobody could have seen from
    Windows.** The repo-root `pyrightconfig.json` — the file whose entire job is
    to give an editor or LSP the same view the gates have — reported **331
    errors** on macOS where the gates report none, in two independent ways.
    First, its `extraPaths` named `.venv/Lib/site-packages`, the Windows venv
    layout; both layouts are now listed, and the doctor FAILS when no
    `site-packages` path in an execution environment resolves on this machine,
    because "pyright ignores an extraPath that does not exist" is precisely what
    let this rot unseen. That took it to 132 — all of them `ctypes.WinDLL` and
    `ctypes.WinError` in the two Win32 adapters. The cause of those: **an
    `executionEnvironment`'s `pythonPlatform` does not drive the `sys.platform`
    narrowing typeshed gates those symbols on; only the top-level one does.** The
    config had said `"pythonPlatform": "Windows"` in the `bridges/nvda`
    environment, where it did nothing, and on Windows the top-level default is
    Windows anyway, so the dead setting was invisibly redundant. Setting it at the
    TOP level does give 0 errors, and was **rejected**: the root config covers
    `shared/` too, and a file saying "analyse this whole repo as Windows" makes a
    claim about the repo that is not true. The two Win32 leaves joined the root
    config's `ignore` list instead — beside the NVDA edge already there for the
    same kind of reason — and lose no coverage, since the bridge's own config
    still analyses them under its own (top-level, and correct) Windows setting.
    Root **0 errors**; `poe bridge-types` unchanged at 0. The doctor check that
    guards this was itself **too strict on its first push**, turning both the
    `nvda-bridge` and the new `portable` job red: a CI job builds only the
    project venvs its own task needs, so `shared/.venv` does not exist while the
    bridge job runs, and "no site-packages resolves" is not a config error there.
    It now asks the question only where a venv exists — which is the first thing
    the new macOS job earned, three minutes after it was added.
    **The structure, which is the part that outlives macOS.** The organising rule
    is that **the server is built and tested on every host unconditionally** —
    a requirement, not an observation — while **a bridge works where its reader
    does and declares that itself**, in its own `pyproject.toml`, split into
    `headless` / `package` / `live` tiers with a `reason` the doctor prints when
    it skips one. NVDA declares "tests anywhere, package anywhere, live on
    Windows"; only the last is genuinely Windows-bound. The doctor gained a
    fourth status, `SKIP`, because a check silently omitted cannot be read as a
    statement about the machine. `poe bridges` prints the registry; `poe live`
    refuses where no selected bridge has a live tier instead of matching no tests
    and reporting green; `BRIDGES=nvda` narrows deliberately.
    **The tasks are dispatched, not hard-coded** — which reverses what the spec
    first said. `poe bridge-types` named `bridges/nvda` in its own command
    string, so on a host where nobody is working the NVDA bridge it type-checked
    it anyway: "the NVDA bridge" and "a bridge" were the same thing, which is the
    conflation the entry exists to remove. So each tier declares its own
    COMMANDS too, and `scripts/bridge_task.py` runs them for every selected
    bridge that can, `SKIP`ping the rest. The commands can only live with the
    bridge, because a bridge is not necessarily a uv project — a VoiceOver bridge
    in Go or Swift will be neither pytest nor uv. Doing nothing is a SUCCESS for
    `test`/`types`/`lint` (you are not working that bridge here) and a FAILURE
    for `live` alone, which is why only `live` passes `--require`.
    `build-addon` became `build-bridge`: "addon" is NVDA's word for its own
    artifact.
    **Measured on macOS 15, x86_64** — doctor 6 warnings → **0 warnings and 2
    skips**; `poe bridge` collection error → **588 passed, 3 skipped**; root
    pyright **331 → 0**. CI gained a `portable` matrix job running `uv run poe
    ci` on `macos-latest`, whose first run is also this repo's first evidence
    about Apple Silicon; the four Windows job names and their runner are
    untouched, so branch protection is unaffected and making `portable` required
    is a separate, later settings edit. **Adding Linux is one word in that
    matrix** — that claim is the structure's own test, and it is a claim rather
    than a measurement: no Linux run has happened.
    **Measured on Windows 11 25H2, NVDA 2026.1.1** — all eight checklist
    items pass: `poe dev` green, `poe bridges` showing all three NVDA tiers
    RUNS, the doctor at 30 PASS with `pwsh` checked rather than skipped,
    `server/screenreader-mcp.exe` and the `.nvda-addon` both built, a dry-run
    `redeploy` naming seven live processes by resolved path, and root pyright
    at **223 files, 0 errors**. The Windows run also surfaced a defect macOS
    could not: **both live-NVDA modules still asserted `pressGesture == {"ok":
    True}`**, the reply shape spec 0025 retired when the gesture reply started
    carrying `pressed` and `speech`. Only `poe live` reaches those modules and
    it is opt-in, so no gate had run the assertion since 0025 landed — and the
    TCP twin's copy is latent besides, because nothing listens on TCP. Both
    now assert what the reply actually carries, and the tier is green at 13
    passed, 7 skipped. The fix rides in this PR rather than a follow-up: it is
    two lines, and a live tier that fails for a known reason is one nobody
    reads.
    Spec: [0042](specs/0042-the-server-is-everywhere-a-bridge-is-somewhere.md)
    (**agreed 2026-08-28**; rides in this entry's PR, with two amendments made
    while implementing — the `live` guard asks the bridge registry for a tier
    rather than `platforms.py` for an OS name, and decision 7 gained the
    top-level `pythonPlatform` finding, which was not known when it was written).
11.35. **Done (2026-08-29)** — E, the local endpoint was named after the
    mechanism Windows happens to use (lane 2; opens lane 3, and 13.4 waits on
    it). Shipped in ONE PR with 11.36, at the maintainer's request: both are
    lane-2 work that exists to unblock lane 3, and both touch
    `specs/wire/v1/protocol.md`. **Spec
    [0044](specs/0044-the-local-endpoint-off-windows.md)**, whose nine decisions
    are the ones summarised below plus three the implementation needed: the
    POSIX derivation lives in the DOMAIN (pure, so it is tested on the Windows
    leg of CI where the POSIX leaf is not compiled at all), only a BARE NAME is
    judged for liveness (an absolute-path override reports unknown rather than a
    confident wrong "not listening"), and the TCP leaf generalised to
    `net_transport.go` so `unix` and `tcp` share one wrapper.
    **What it is worth, measured**: before, on macOS, the shipped default set
    was one dead entry (`pipe endpoint "nvdaMcpBridge": named pipes are
    Windows-only`) and one live one, and every endpoint reported liveness
    `unknown` by construction. After, a session is established over a real Unix
    socket and the probe reports it listening — four new integration scenarios
    that could not have been written before, on the macOS leg of CI.
    **No live-NVDA checklist**, decided 2026-08-29: nothing on the NVDA path
    changes but the spelling of one shipped default, and the pipe leaf and the
    pipe scan are exercised against a real namespace by the Windows integration
    scenario. What no automated tier proves is that `local:nvdaMcpBridge`
    reaches a real NVDA; that is stated in the spec's Honest limits and is for
    the next live run on Windows.
    The reasoning as it stood when the entry was opened: [Spec
    0010](specs/0010-named-pipe-transport.md) wanted "a local endpoint that is
    not the network", and got it on Windows as a named pipe. There is no macOS
    equivalent of `\\.\pipe\nvdaMcpBridge` and there is not going to be one;
    the macOS answer to the same requirement is a **Unix domain socket** — a
    filesystem path with filesystem permissions, which is the property spec 0010
    was actually asking for rather than the mechanism it happened to use.
    **The server keeps exactly two transports, and the local one is resolved per
    platform — Decided 2026-08-29 (Marlon).** Not a third kind. A caller asks
    for the local endpoint or for loopback TCP, and *which* local mechanism that
    means is the leaf's business: a named pipe on Windows, an `AF_UNIX` socket
    on POSIX. **The code is already shaped for this** — `DialerFor` selects
    between two leaves, and `pipe_transport_other.go` is today a refusal stub
    (*"named pipes are Windows-only; configure a loopback tcp endpoint
    instead"*) sitting in the exact position the real POSIX leaf belongs. That
    stub stops refusing and starts dialing; nothing above it changes shape.
    **The address stays a bare NAME in everything we ship, and that is the
    load-bearing part.** It is what keeps `server/config/defaults.json`
    host-independent: one entry per reader that works on every host, resolved to
    `\\.\pipe\<name>` on Windows and to a socket path on POSIX. **An absolute
    path is still accepted as an override** — that loses nothing, because what
    would fork the shipped config per host is a path in the *defaults*, not a
    path being expressible. The derived location is pre-configured; someone who
    wants a different one can say so.
    **Where that derived location is — Decided 2026-08-29:**
    `$XDG_RUNTIME_DIR/screenreader-mcp/<name>.sock` when that is set, otherwise
    `~/.screenreader-mcp/<name>.sock`, directory mode `0700`, which is where the
    filesystem-permission property actually comes from. `sun_path` is **104
    bytes** on macOS and `$TMPDIR` alone spends 49 of them, so a `$TMPDIR`-based
    path was rejected as too tight to be safe on a machine nobody has seen; the
    length is checked at endpoint *construction* regardless, since a long
    username still exists somewhere. The bridge unlinks before binding, because
    unlike a pipe the file outlives the process.
    **None of the socket half reaches the NVDA bridge.** It is Windows: its
    local endpoint resolves to a named pipe exactly as it always has, and no
    socket path is ever computed for it. The one thing that changes for the NVDA
    reader is the spelling — `local:nvdaMcpBridge` where the config used to say
    `pipe:nvdaMcpBridge`, resolving to the same `\\.\pipe\nvdaMcpBridge`.
    **The name `pipe` changes with it — Decided 2026-08-29: `local`.** It is
    Windows-flavoured, and once half the hosts resolve it to something that is
    not a pipe the name is simply false. `local:nvdaMcpBridge` is
    mechanism-neutral, contrasts cleanly with `tcp`, and says what spec 0010
    meant. (`ipc` was the runner-up; `socket` was rejected because TCP is a
    socket too.) **`pipe:` is kept as a parsed alias** rather than removed,
    because it appears in shipped defaults, in `--reader` help text, in
    `specs/wire/v1/protocol.md` and in whatever config files people already
    have.
    **The discovery seam generalises the same way, and macOS gains something by
    it.** `PipeDirectory` lists the named-pipe namespace on Windows and returns
    an empty list everywhere else, so every endpoint on macOS reports liveness
    *unknown* by construction. A directory of socket files answers the same
    question honestly, so the probe starts working on the host lane 3 runs on.
    Blast radius, small and contained: `domain/entities/endpoint.go` (the kind,
    its parsing, its error text), `adapters/bridge/endpoint.go`,
    `pipe_transport_other.go`, `adapters/discovery/` (the seam and both leaves),
    `domain/entities/reader_listing.go`, `config/loader.go`, `defaults.json`,
    `cmd/screenreader-mcp/main.go`'s help text, and `testsupport/`.
    **Windows keeps named pipes — Decided 2026-08-29**, even though Windows 10
    1803+ has `AF_UNIX`: the shipped NVDA add-on listens on a pipe, and changing
    that would break every installed copy for no gain. If it is ever revisited
    that is a new decision, not this one.
    Still a contract change, not only a server refactor: the resolution rule is
    the *rendezvous*, so `specs/wire/v1/protocol.md` carries it and every bridge
    implements it. Nothing about the NVDA add-on's behaviour changes, but the
    document it is written against does. §1 is rewritten around the local
    endpoint and §8 records the amendment; `PROTOCOL_VERSION` does not move,
    because no frame, field, command or value changes shape.
    Spec: [0044](specs/0044-the-local-endpoint-off-windows.md).
11.37. **E, the endpoint name can be overridden on one side only** (both lanes
    and lane 3; **not** on lane 3's critical path). Raised by Marlon on
    2026-08-29 while 11.35 was being written, and recorded rather than
    remembered.
    **The server half already exists.** `--reader nvda=local:someOtherName` and
    a `--config` file both reach `config/loader.go`, so the dialing side can be
    pointed anywhere. **The bridge half does not.**
    `adapters/build_listener.py` builds its listener from
    `protocol.DEFAULT_PIPE_NAME`, a constant, and the control dialog ([spec
    0011](specs/0011-bridge-control-ui.md)) selects the *kind* — pipe or TCP —
    and never the name.
    So the override that exists today is, in practice, **a way to make the two
    sides disagree silently.** The server dials a name nothing is listening on
    and reports the endpoint as not listening, which is true and useless: the
    real fault is that somebody configured a name the bridge was never able to
    use, and nothing says so.
    What it needs, in both bridges: a config key plus a dialog field for the
    endpoint *name*, alongside the kind. And on the POSIX side the same field
    accepts an absolute socket path, which 11.35 already decided the server
    would honour — so this entry is what makes that override reachable from the
    listening end rather than only the dialing one.
    **Lane 3 gets it cheaply if it is designed in rather than added.** Lane 3
    builds its control dialog from scratch; a name field costs nothing there and
    costs a revision later.
    **Half of lane 3's half is Done (2026-08-30).** 13.10 made the endpoint name
    a persisted SETTING rather than a constant -- `BridgeConfig.endpointName`,
    stored, read by the launcher, and accepting an absolute socket path on POSIX
    exactly as 11.35 decided the server would honour. What is still owed there is
    the FIELD: a way for a human to edit it without a `defaults` command, which
    belongs to the control dialog (13.14). Lane 1 owes both halves still.
    Why it is wanted at all, beyond symmetry: more than one reader on a machine,
    more than one NVDA profile, and per-user isolation on a shared host — none
    of which the single shipped default can express.
    **Not blocking.** The default name works, and lane 3 can be built and
    demonstrated on it. This is a gap in the configuration surface, not in the
    connection.
    Spec: none yet.
11.36. **Done (2026-08-29)** — E, the wire module was named after the only
    reader it used to serve (both lanes; **gated lane 3's 13.3**). Shipped in
    one PR with 11.35; see that entry for why the two travelled together.
    **Spec [0045](specs/0045-a-wire-module-named-after-the-contract.md).**
    73 occurrences across 43 files, all mechanical, all gated. The package moved
    with `git mv` so history follows, the distribution became
    `screenreader-wire`, and `schema.json` came out byte-identical — which the
    drift gate proves and is the whole claim that nothing changed. Nothing in
    the add-on package moved: `sync_shared.py` copies one file to `protocol.py`
    and the bridge imports it as `from . import protocol`, so only the source
    path changed. Specs that named the old path were rewritten, because a
    document pointing at `shared/nvda_mcp_wire/protocol.py` now points at
    nothing; the places that recorded the DECISION rather than the path keep the
    old name, and spec 0005's deferral gained a dated line saying it happened.
    The reasoning as it stood when the entry was opened: `nvda_mcp_wire` was named when NVDA
    was the identity rather than the first bridge, and [spec
    0005](specs/0005-multi-reader-direction.md) deferred renaming it until the
    repo name settled. The repo is `screen-readers-mcp`, and a **Swift** binding
    of a module named `nvda_mcp_wire` is not merely untidy, it is misleading
    about what the contract is.
    **Decided 2026-08-29: `screenreader_wire`**, distribution
    `screenreader-wire`, imported as `screenreader_wire.protocol` — so both
    halves still address the contract through a module named `protocol`, which
    is the rule AGENTS.md states.
    **`screenreader` rather than `screen_readers`**, because it is the
    identifier the product surface already uses: the binary is
    `screenreader-mcp` and every MCP resource is `screenreader://guidance`,
    `screenreader://tools`, `screenreader://reader-guidance`. The repo and Go
    module are plural, so the two conventions were already inconsistent and one
    had to win.
    **What ruled out the obvious short names** is hard invariant 1: this module
    is copied verbatim into the add-on and runs inside NVDA's interpreter,
    sharing `sys.modules` with every other add-on. `wire` and `protocol` are
    collision bait there, and a collision inside NVDA is not a name clash, it is
    somebody's screen reader.
    **Taken before 13.3 deliberately.** 13.3 writes the Swift binding; renaming
    afterwards means paying for the rename twice, once in each binding.
    Blast radius, all mechanical and all gated: `shared/` (the package
    directory, `pyproject.toml`, `schema.py`, both test modules, `README.md`),
    `bridges/nvda/sync_shared.py` and its gitignored copy path,
    `bridges/nvda/tests/conftest.py`, the three `pyrightconfig.json` files,
    `scripts/doctor.py` and `scripts/drift.py`, and roughly twenty specs plus
    `AGENTS.md`, `shared/AGENTS.md` and `CONTRIBUTING.md`. **No behaviour
    changes and `PROTOCOL_VERSION` does not move** — the wire shape is
    untouched, so this costs no version bump under the policy in
    `shared/AGENTS.md`.
    Spec: [0045](specs/0045-a-wire-module-named-after-the-contract.md).
11.19. **Done (PR #61, 2026-08-17)** — E, personas — the persona exists and
    travels (both lanes). Live-checked against NVDA 2026.1.1 in both capture
    modes: the declaration reached `status`, `screenreader://info` and the
    bridge's own transcript on disk, an unknown persona was refused naming all
    three, and the spoken persona was **heard after the tones in silent mode** —
    the one claim no automated tier can make, and the one 4.7 rests on, since a
    wrong route would have produced tones followed by silence in exactly the mode
    where the human at the machine most needs telling.
    **Re-scoped 2026-08-17**, from *the server half*. The old boundary was the
    lane: server first, reader second. That was right while the server owned the
    ordinary vocabulary and stopped being right when TalkBack moved it to the
    bridge (see the scope amendment below) — a server-only ship would tell a
    `user` session its vocabulary is bounded and give it no way to learn what is
    in it. The seam is now **mechanism, then document**: this entry makes the
    persona exist, travel in `hello`, be recorded everywhere and be spoken at
    session start; 11.20 gives the reader its own document. Both touch both lanes
    and both need an add-on rebuild. This entry promises no document that does
    not exist when it ships, which is the property the lane split lost.
    Designed in conversation
    2026-08-16. An agent connects **as somebody**: a *normal user*, an
    *accessibility validator*, or an *expert*. The persona says what the agent is
    standing in for, and therefore what a finding from that session means.
    **The personas are NOT nested, and any design that models them as a ladder
    gets them wrong.** Each asks a different question: `user` *can I do this?*,
    `validator` *is this right?*, `expert` *how does this actually work?*
    **AMENDED 2026-08-17, in the sentence this entry was built on.** It read: *a
    blind user with a task succeeds when the task is done, so a workaround is a
    legitimate win and object navigation is exactly what a competent user reaches
    for.* **That is wrong.** A normal user is not a screen reader expert. Their
    whole vocabulary is what the ARIA authoring practices assume of the person at
    the keyboard — Tab, the arrows, Space for a checkbox, arrows for radio
    buttons and list items, alt+down/alt+up for a combo, typing into edit fields,
    first-letter and single-letter navigation, browse and focus mode — and **if a
    task needs object navigation, the review cursor or a simulated click, the
    task has failed**, because this persona does not have those commands. The run
    may say another stance could investigate; it may not borrow that stance's
    result and call the task done. The validator drives with the **same**
    vocabulary, so that *reachable* means the same thing in both reports, and
    what it gains is observation (`getFocusInfo`, `getState`) rather than
    latitude — it may step outside only to characterise a failure it has already
    found, and must say so. The `expert` is the only stance for which nothing is
    off limits: it reads the reader's event log, tracks what happened around a
    keystroke, and takes the mechanism apart. So **observation power rises user →
    validator → expert while action latitude does not rise between the first two
    at all** — the original formulation, which only became true once the user's
    latitude was corrected downwards.
    **Also widened 2026-08-17: the third persona is `expert`, not `add-on
    developer`.** The developer debugging their own add-on is one instance; an
    accessibility expert taking a site apart to find out why it behaves as it
    does is the same stance with a different subject.
    **Instruction only — no tool gate. Decided.** The central restriction — that
    `user` and `validator` may not leave the ordinary keyboard vocabulary —
    cannot be enforced by the server: object navigation is `pressGesture` with the
    reader's own keys, and the server cannot recognise it without learning that
    key map, which is what `ToolCatalog` says it could not express even if
    somebody wanted it to. A gate would therefore be **partial enforcement that
    reads as total** — withholding `getFocusInfo` while the validator
    object-navigates its way to a false pass, buying nothing where the risk is and
    costing an 11.6-shaped confusion where it is not. Instruction-only is uniform
    and honest, and it keeps something a gate destroys: an agent that steps
    outside its persona *and says so* has produced evidence, where an agent that
    hits a wall has produced a failed run. The deliverable is the report.
    **The trigger that would reopen this, stated 2026-08-17:** deliver the right
    information to the agent according to its persona, and **if violations then
    turn out to be common, gate.** Worth recording because a *bridge* could gate
    exactly — it knows its own key map, and NVDA can resolve a gesture to the
    script it is bound to — so "cannot be enforced" is true of the server and not
    of the system. What makes the trigger checkable is 11.20: once a bridge names
    the out-of-vocabulary gestures, the session record can simply be read for
    them.
    **Chosen before connecting**, so the documents are static and server-owned —
    the persona determines what the run means and cannot be retrofitted onto a
    session that already ran. (Not because the human is unreachable mid-session:
    `announce` and `ask_user` exist. It is the wrong moment, not an impossible
    one.)
    Scope, **amended 2026-08-17**: the entry said *three static resources holding
    each persona's stance and success criterion*. It is now **one** general
    resource — the existing `screenreader://guidance`, absorbing what a screen
    reader is, how this MCP is meant to be used, and a profile of each persona,
    composed from the domain so a persona cannot exist without one. **TalkBack is
    why**: a server-owned document that stated a persona's *vocabulary* could only
    ever be written for one platform, and TalkBack has neither a keyboard nor
    Windows, so Tab, alt+down and windows+tab would be instructions that do not
    exist on the reader being driven. Every concrete list moves to the bridge
    (11.20); the server keeps the **rule** — the ordinary user's vocabulary is
    whatever the platform's accessibility contract assumes, and a command that
    re-reads what is already there is inside it while a command that reaches what
    focus cannot is outside. Plus a `persona` argument on `connect_reader` beside
    `mode`, and the declaration recorded in `status`, `screenreader://info` and
    the session record — so a finding carries the stance that produced it.
    *Reachable* from a user session and from an expert session are different
    claims. **Plus, after the re-scope**, the wire's `persona` field, the bridge
    recording it in its context and transcript, and the spoken persona after the
    session-start tones — so this entry now carries a wire change and an add-on
    rebuild that the original did not. What it does **not** carry is the
    `guidance` capability, `getGuidance`, the reader-guidance resource or NVDA's
    concrete document: those are 11.20, which is where the list of what a `user`
    may actually press now lives.
    Two things the spec settled that this entry left open: **`persona` is
    required, with no default** — a defaulted `user` session makes a claim nobody
    knows was made — and **the short stance rides back in `connect_reader`'s
    result**, because the first external run is evidence that an agent does not
    necessarily read a resource it was not pointed at. It also amends 0023 — more
    than a pointer: the shipped guidance document states one persona's stance as
    everyone's, and since there is no separate persona resource to delegate to,
    guidance **absorbs** the stance. Its method sections are untouched (they never
    varied by persona), its introspection section gains the `expert`'s exception,
    and it still names no reader's keys, which after the scope amendment above is
    the entire reason the bridge's document exists.
    **No fourth persona for the inexperienced user**, which was briefly proposed
    and is unnecessary after the amendment above: `user` *is* that user. The
    objection raised against it is worth keeping anyway, because it explains why
    naming the vocabulary was the right move — an agent cannot honestly simulate
    *not knowing* a command, so a persona resting on pretended ignorance would
    produce a guess about a hypothetical person. Naming the vocabulary dissolves
    that: nothing is forgotten, the commands are simply **out of scope**, and the
    task that then fails is a fact about the interface rather than a performance.
    Spec: [0029-connecting-as-somebody.md](specs/0029-connecting-as-somebody.md)
    (agreed 2026-08-17; covers 11.20 as well, and records two amendments made
    during this entry's implementation).
11.20. **E, personas — the reader says what its vocabulary is** (both lanes).
    **Done (PR #63, 2026-08-17.)** The `guidance` capability, `getGuidance`,
    `screenreader://reader-guidance` with its lazy per-session cache, and NVDA's
    own documents — the ordinary vocabulary on this reader, the desktop's keys,
    its reading commands, and the object-navigation, review-cursor and
    simulated-click commands that fall outside the boundary.
    **The gesture tables are RESOLVED FROM THE READER, not documented.** The first
    implementation transcribed NVDA's defaults out of `globalCommands.py`, and that
    was wrong in the unsafe direction: NVDA lets anyone remap, a remapped gesture
    does not fail but quietly does something else, so a `user` session would be
    warned off a harmless key and told nothing about the one that now reaches past
    focus. The bridge now asks `inputCore.manager.getAllGestureMappings()` — the
    same question the Input Gestures dialog asks — keyed on NVDA's own script
    CATEGORIES rather than a script list, so it is self-maintaining and picked up
    16 object-navigation commands where the transcription had 9. It also caught the
    transcription being wrong on the very machine it was tested on:
    `toggleSimpleReviewMode` is unbound here, while the hand-written table claimed
    `NVDA+numpad1` — which this machine binds to `reviewMode_previous`.
    **One trap found by looking rather than assuming:** NVDA stores identifiers
    alphabetically sorted and `fromName` reads the LAST token as the key, so
    "read the whole window" comes out as `b+nvda` and pressing it verbatim presses
    NVDA with B held. `press_order` hoists the key last; the live checklist proves
    it by pressing `speakForeground`, the case that was broken, rather than `title`,
    which sorts correctly by luck.
    **And the bridge's documents ship as files read at run time**
    rather than compiled in, which needed `buildVars.bundledDataSources` — without
    it scons reports "up to date" over an edited document and the add-on ships the
    previous text. Same class of silent staleness as `//go:embed` on the server
    side, opposite mechanism; AGENTS.md invariant 9 now carries both.
    **Re-scoped 2026-08-17** from *the reader half*: the wire's `persona` field
    and the bridge's recording of it moved into 11.19, so what is left here is
    exactly the document and the machinery that serves it — the `guidance`
    capability, `getGuidance`, the session-scoped resource with its cache, and
    NVDA's own text. **After the TalkBack correction this entry carries more than
    it used to**: not only which of a reader's commands are out of bounds, but the
    ordinary vocabulary itself, because no server-owned document can state a list
    that is keystrokes on Windows and touch gestures on Android.
    **The server defines the personas; each bridge defines
    what that persona should and should not use on its reader.** The rule is
    reader-agnostic and belongs to the server ("do not route around the problem");
    the instances are reader-specific and only the bridge author knows them —
    NVDA's escape hatches are object navigation, the review cursor and simulated
    clicks, JAWS's is the JAWS cursor. **After the 2026-08-17 correction to 11.19
    this list stops being advisory:** the ordinary keyboard vocabulary is
    reader-agnostic and the server states it, but *which of a reader's own
    commands fall outside it* is the bridge's to say, and it is exactly the list a
    `user` session needs in order to recognise what it must not reach for — named
    as gestures, in both keyboard layouts. The same document must say what is
    **not** outside it and would otherwise be assumed to be: browse mode and
    single-letter navigation are how a user reads a document, not a way around a
    broken one. Neither document works alone, which is the evidence the split
    is real rather than convenient.
    This also answers a gap 11.14 could only flag: **readers differ in what they
    offer, not merely in which keys they use for it** — JAWS has a native way to
    list open windows and NVDA has none — so "the agent already knows" is not a
    safe assumption, and a static reader-agnostic document has no way to say so.
    A bridge-supplied document does, and it ships with the reader it describes, so
    it cannot rot in the one place nobody checks.
    Scope sketch: a `getGuidance` command behind its own capability (lazy, so a
    session that never asks never pays; and a bridge that does not implement it
    simply does not advertise it, degrading to the server's documents alone), the
    persona declared in `hello` so it lands in the bridge's transcript too, and
    the result served opaquely as a session-scoped resource the server never
    parses. **Three things to settle before it is buildable:** unknown personas
    must degrade rather than error, and that must be designed in on day one or
    adding a persona becomes a synchronised release across every bridge;
    precedence must be explicit when server and bridge disagree (the server's
    definition is normative, the bridge instantiates and may not redefine); and
    the timing must be written down — the persona is chosen before connecting but
    its reader-specific instantiation can only arrive after, which is coherent but
    surprising.
    **The payoff beyond documentation:** once a bridge *names* its escape hatches,
    a validator run becomes auditable after the fact against the session record,
    which already stores every call with its params. The rule stays unenforced —
    no gate, no partial fence — but stops being unverifiable, which for a
    validator is worth more than a wall. Note also that if the object-navigation
    tool [0023](specs/0023-drive-it-like-a-user.md) anticipates is ever built, the
    validator's central restriction becomes gateable; that is a reason to build it
    as its own tool rather than as more `pressGesture`.
    **The three things to settle are settled.** Unknown personas degrade because
    `persona` crosses the wire as a plain **string**, not an enum — a closed enum
    would make `from_dict` reject an unrecognised value and fail the *handshake*,
    so a newer server could not connect to any existing bridge the day a fourth
    persona is added; a bridge must not reject one (the same carve-out §4 already
    gives unknown capability strings), and `getGuidance` reports `recognised:
    false` with its general text. Precedence is stated in the wire contract and
    restated in the frame the server wraps around the bridge's text, which is how
    it is enforced without the server ever parsing a document it did not write.
    Timing is written down, and `connect_reader`'s result names the resource at
    the first instant it exists. **One addition the entry did not have: the human
    at the machine hears the persona.** The bridge already plays two ascending
    tones when a session establishes — they say something has taken the reader,
    and cannot say what it is standing in for — so `session_started` carries the
    persona and the NVDA adapter speaks one line after the tones, through the
    live synth so it is heard in silent mode too. Bridge-side rather than
    server-side because the tones are bridge-side, because an add-on string can
    be localised and nothing the server speaks can be, and because building it in
    11.19 would mean building it twice.
    Spec: [0029-connecting-as-somebody.md](specs/0029-connecting-as-somebody.md)
    (agreed 2026-08-17; shared with 11.19, which is Done — this is the half that
    remains).
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
