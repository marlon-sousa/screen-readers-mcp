# 0039 — a flake that says where it went

Status: **agreed 2026-08-27.** Board entry **11.28**,
neither lane (bridge tests). Opened on 2026-08-21 by the `poe dev` run that
gated the AGENTS.md split, and deliberately left unfixed there because that PR
was documentation-only and a timing fix is code.

This spec does **not** claim to fix the flake. It claims that the flake cannot
currently be diagnosed, makes it diagnosable, and stops there on purpose.

---

## Part 1 — the evidence

### What happened, and how little it tells us

`tests/integration/test_named_pipe_session_roundtrip.py::test_a_whole_session_over_a_real_named_pipe`
failed once with:

```
AssertionError: no reply from the bridge within timeout
```

It then passed 2/2 in isolation and in three later full `poe dev` runs on the
same checkout. It has not been seen since.

That message is the whole problem. The test makes **eight** `_read_reply`
calls across its two sessions, and the assertion names none of them. It does not say
how long it actually waited, how many times it asked, whether the channel was
still open, or whether anything at all had been received. A failure that
reproduces once every few hundred runs and reports nothing is a failure that
cannot be worked on, only re-run.

### What the read path cannot be

One attractive hypothesis is ruled out by construction rather than by argument,
and ruling it out is worth stating because it narrows what is left.

`JsonLinesChannel.read_message` drains any already-buffered line **before**
touching the transport, and `_LineReader` keeps a partial line in its buffer
across polls. So a reply that arrived split across a poll boundary is not lost,
and a reply that arrived while the caller was elsewhere is not lost either. The
docstring says so and the code does so. **A dropped first reply is not the
explanation.**

### The budget is far larger than "the machine was busy" accounts for

`_read_reply` spends a 5.0 s wall-clock budget against a 0.05 s poll timeout —
about **100 consecutive polls** in which the bridge returned nothing. The
operation underneath is a local named pipe against `FakeAdapterFactory`, which
is sub-millisecond work.

For load alone to explain that, the test thread has to have been descheduled for
five seconds. That is not impossible on Windows — an antivirus pass over a
freshly built binary will do it, and `poe dev` builds one — but it is a much
stronger claim than "the machine was busy with the rest of the suite", and it is
worth noticing that nobody has actually established it. The entry's own warning
applies to its own most comfortable theory.

### The eight calls are not equally at risk, and one differs in kind

Seven of the eight expect a sub-millisecond answer. One does not:

```python
agent.write(_request(4, "waitForSpeechToFinish", timeout=3.0))
assert _read_reply(agent, timeout=6.0)["result"]["finished"] is True
```

`waitForSpeechToFinish` blocks **bridge-side** until `SPEECH_FINISHED_SECONDS`
(1.0) of quiet has passed since the last utterance, polling a **real** clock
every `POLL_INTERVAL` (0.03). So this is the only call in the test with a real
second of wall clock inside it, the only one whose budget was deliberately
raised, and the only one where a scheduling delay compounds with a genuine wait
rather than standing alone.

It is the one to bet on. It is not the one to fix, because betting is what this
spec exists to stop doing.

### The helper is triplicated, exactly

`_read_reply` is **byte-identical** in
`test_named_pipe_session_roundtrip.py`, `test_socket_session_roundtrip.py` and
`test_wire_session_roundtrip.py`. `_request` and `_wait_until` are duplicated
too, the latter in two of the three.

That matters for more than tidiness: it means whatever this is, it is a property
of the **shape all three share**, not of the pipe leaf — and it means a
diagnostic added to one copy would leave the other two silent about the same
failure. Only the pipe test has ever failed; the other two have the same blind
spot and have simply not exercised it yet.

`tests/support/` already exists and is where AGENTS.md puts scaffolding that is
not a port double.

---

## Part 2 — the shape

### Decision 1: the failure says where the budget went — **agreed in conversation, 2026-08-27**

The assertion becomes a report. On failure it states:

- **which exchange** — the request id and command the caller was awaiting;
- **how it was spent** — polls consumed, wall-clock elapsed, and the **per-poll
  average**, against the 0.05 s the transports promise;
- **that the channel never reached EOF**, so the bridge was connected and quiet
  rather than hung up.

**Amended while implementing.** The draft also promised to report "whether some
other message arrived and was skipped". Nothing is skipped: `read_reply` returns
the *first* non-`Timeout` message, so on the failure path every poll was a
`Timeout` by construction and saying so adds nothing. The per-poll average
replaces it, and is the better element anyway — it is the one figure that
separates "the bridge was silent while this process ran normally" (near 50 ms)
from "this process was not being scheduled" (well above it), which is the
distinction Part 1 could not make. Likewise the EOF fact is a *consequence* of
reaching that path rather than something to test for: `ChannelClosed` propagates
out of the helper, so a hang-up never becomes this assertion.

Polls **and** wall clock, not one or the other. The budget is polls (Decision 2)
but the elapsed time is what separates "the bridge was silent for 100 polls that
took 5 s" from "the bridge was silent for 100 polls that took 47 s because this
process was not running" — which are different diagnoses and the current message
conflates them completely.

### Decision 2: the budget counts polls, not seconds — **agreed in conversation, 2026-08-27**

A wall-clock deadline measures the wrong thing. It answers "how much time
passed", when the question the test is asking is "how many chances did the
bridge have to answer". Those coincide only while the test process is actually
scheduled, which is exactly the condition in doubt.

So the budget becomes a **count of polls that returned `Timeout`**. A starved
process then takes longer to spend the same budget instead of failing on a
shorter one, and a failure means the bridge really did decline 100 opportunities
to answer.

**The budget is not made more forgiving.** 100 polls at 0.05 s is the same 5.0 s
of *bridge silence* the wall-clock budget nominally bought — the size is
preserved and only the instrument changes. Raising it is the single change that
could hide a real fault, and this PR does not make it.

### Decision 3: a wall-clock backstop, whose expiry is a different failure — **agreed in conversation, 2026-08-27**

A poll budget alone can never expire if `read_message` stops returning — a
transport that blocks forever would hang the suite rather than fail it. So a
generous wall-clock backstop stays, at 60 s: far above any plausible slow
answer, low enough that CI fails instead of timing out.

Hitting the backstop and spending the polls are **different messages**. One says
the bridge was silent; the other says the transport stopped answering the test
at all. Reporting them identically would recreate the problem this spec is
about.

### Decision 4: one helper, three tests — **agreed in conversation, 2026-08-27**

The helper moves to `tests/support/roundtrip.py` and all three roundtrip tests
use it. `_request` and `_wait_until` move with it, for the same reason.

`_dial` does **not** move. It differs per transport — a pipe name in one, an
endpoint in the other — and forcing those into one signature would invent a
shared abstraction where the tests genuinely differ. What is common moves; what
differs stays.

### What does NOT change

- **No production code.** Nothing under `addon/globalPlugins/` is touched. The
  connection stack is not audited, not instrumented, not adjusted.
- **No timeout is raised**, in the helper or in any caller. The
  `waitForSpeechToFinish` call keeps its larger budget, which is now expressed
  in polls and is justified in a comment naming `SPEECH_FINISHED_SECONDS` as the
  reason.
- **The test is not quarantined, skipped, retried or marked flaky.** An
  auto-retry is precisely the mechanism by which a real bug hides inside a known
  flake, which is the risk 11.28 was written to name.

---

## Part 3 — what ships

1. `tests/support/roundtrip.py`, holding `request`, `read_reply` and
   `wait_until`.
2. The three roundtrip tests importing them and deleting their private copies.
3. Board entry 11.28 flipped to Done, and this spec's status flipped to agreed.

The flake stays open as a *phenomenon*: this PR does not close the question of
whether the connection stack can delay a first reply. It makes the next
occurrence answer it.

## Class/file layout

One new file, three changed. No new classes and no domain role, because nothing
here is production code — the helper is test scaffolding, which is why it lives
in `support/` rather than `fakes/` (it is not a port double) and why it has no
port, controller, entity or adapter role to name.

| File | Role | Change |
|---|---|---|
| `bridges/nvda/tests/support/roundtrip.py` | **test support** (new) — module-level helpers, no class. Collaborators: `JsonLinesChannel` and the `Timeout` sentinel from `domain/ports/message_channel`, plus `protocol` for `Request`. Used by the three integration roundtrip tests; used by nothing in `tests/unit/`. | New. `request(id, cmd, **params)`; `read_reply(agent, *, awaiting, polls=DEFAULT_POLLS)` with the poll budget, the wall-clock backstop and the two distinct failure reports; `wait_until(predicate, *, awaiting, timeout=2.0)` — wall-clock on purpose, since it polls a local object rather than waiting on a peer, and it says what it was waiting for when it gives up. |
| `bridges/nvda/tests/integration/test_named_pipe_session_roundtrip.py` | integration test (existing) | Deletes `_request`, `_read_reply`, `_wait_until`; imports them from `support.roundtrip`; every call site passes what it is awaiting. `_dial` and `_unique_pipe_name` stay — they are the pipe's own. |
| `bridges/nvda/tests/integration/test_socket_session_roundtrip.py` | integration test (existing) | Same, keeping its own `_dial`. |
| `bridges/nvda/tests/integration/test_wire_session_roundtrip.py` | integration test (existing) | Same; it has no `_dial` and no `_wait_until` to keep. |

**`roundtrip.py` gets no test file of its own, and that is a statement rather
than an omission.** Every run of `poe bridge` exercises it through three
integration tests whose failure mode is loud, and the thing it would be tested
for — that it reports correctly when the bridge does not answer — is reachable
only by simulating the fault this spec exists to observe in the wild. A fake
channel that never answers would prove the formatting and nothing else. If the
helper grows a decision that is not visible from its callers, it has outgrown
`support/` and the test comes with that growth.

## What is deliberately not built

- **A retry.** The obvious way to make an intermittent test green, and the one
  the entry rules out in advance: an intermittently red gate teaches people to
  re-run, and a retry teaches the machine to. Either way the next real bug of
  this shape arrives pre-excused.
- **An audit of accept/handshake/dispatch.** It is the entry's third step and it
  is third for a reason: with no captured evidence it is a search of a
  connection stack for a fault nobody has localised, and the cheapest way to
  make that search unnecessary is to let the next failure name its own site.
- **A change to `SPEECH_FINISHED_SECONDS`, `POLL_INTERVAL` or any transport
  poll timeout.** These are production constants with their own reasons. Tuning
  a product constant to settle a test is the wrong direction of causation.
- **Parallelising or isolating the integration tests.** Running them in their
  own process would very likely make the symptom go away, which is the argument
  against it while the cause is unknown.

## Honest limits

- **This does not fix anything.** If the cause is a real race in the connection
  stack, the test will keep failing at the same rate. It will simply fail
  legibly. That is the whole of the claim.
- **It may never fire again.** One occurrence in a few hundred runs means the
  diagnostic could sit unused for months. The cost is one small module; the
  alternative is that the next occurrence is as uninformative as the first.
- **A poll budget is not immune to everything.** If the transport's own poll
  timeout drifts under load — `WaitForSingleObject` with a 50 ms timeout is a
  *minimum*, not a promise — then 100 polls is more than 5 s of wall clock. That
  is why the elapsed time is reported alongside the count rather than replaced
  by it: the two disagreeing is itself a finding.
- **The other two roundtrip tests have never failed.** Giving them the same
  helper is an assumption that they share the fault, justified by them sharing
  the shape. If the pipe test alone keeps failing after this, that asymmetry
  becomes evidence and this spec's Part 1 was wrong about where to look.

## Open questions

- **Is 100 polls the right size?** It preserves today's budget exactly, which is
  the conservative choice, but nobody chose 5.0 s on evidence either — it was a
  default. The first captured failure will say whether the bridge answers at
  120 polls or never, and that is when the number should be argued about.
- **Does `wait_until` belong in the same module?** It is wall-clock and the
  others are not, which is a slight incoherence. Kept together because splitting
  two small helpers across two files to honour a distinction no caller feels
  would cost more than it explains.

## Not in scope

- Board entry **11.18**. The pattern of a rule nothing enforces is shared, but a
  CI gate is that entry's open question and it is on hold.
- The Go side. `server/tests/conformance/` has its own harness and has not shown
  this shape.
