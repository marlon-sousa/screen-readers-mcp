# 0028 — when was that said

Status: **agreed 2026-08-16, implemented in the same PR.** Board entry **11.15**.
Ask 1 of [0027](0027-the-first-external-run.md), and the strongest of the five.

**Amended during implementation, in one place** (Part 4's bridge layout), and the
amendment is worth reading because the code found something the spec had not:
`IndexedBuffer` gains a protected `_record(entry, log_position)` and the three
`append` implementations call it. The bookkeeping — the entry, the journal
coordinate, now the wall clock, and the heuristic's monotonic mark — was
**duplicated in three places**: `SpeechBuffer`, `BrailleBuffer`, and the test
double in `test_indexed_buffer.py`. Adding one field to all three missed one, and
five tests failed with an `IndexError` rather than anything that named the cause.
That is precisely the argument for the method: subclasses decide *whether* and
*what* to record; the base decides what recording entails, so the parallel lists
cannot fall out of step again.

---

## Part 1 — the measurement that could not be made

From the first external run:

> *"The single most valuable piece of evidence in the whole run — that the stop
> woke a sleeping script in 63 ms — I could not get from the MCP. `get_speech`
> gives `logPosition` but no time, so I read `session-*.log` off disk and diffed
> timestamps by hand."*

An assertion of the form **"X happened promptly after Y"** is a large fraction of
what accessibility testing is: did the reader respond to the keystroke, did the
announcement follow the focus change, did stopping actually stop it. Today none
of those can be stated in numbers through this interface. The agent's workaround
— reading the bridge's transcript off the reader's own disk and diffing by hand —
is not available at all to a remote bridge, and it is not available to any agent
that has not been told the file exists.

**The data is not missing. It is computed and discarded.**
[`IndexedBuffer.__init__`](../bridges/nvda/addon/globalPlugins/nvdaMcpBridge/domain/entities/indexed_buffer.py)
takes a `Clock`, and both `SpeechBuffer.append` and `BrailleBuffer.append`
already call it on every capture — into `self._last_time`, a single scalar
overwritten by the next entry, existing only to drive the "is it still speaking"
elapsed-time heuristic.

So this spec is not new instrumentation. It is **keeping a value we already take**.

## Part 2 — why `logPosition` does not already answer it

Every captured entry carries `logPosition` (spec 0021), and the obvious question
is why that is not enough. Two reasons:

**It is an ordering, not a clock.** `logPosition` places an utterance *relative
to everything else in the journal*. Recovering a wall clock from it costs a
`getLog` round trip per entry — and under [0025](0025-one-round-trip-per-intention.md)
a round trip is the expensive thing, so answering "how many milliseconds" would
cost more than the thing being measured.

**In a silent session there is often nothing to land on.** The bridge empties the
sequence before NVDA reaches its own `log.io("Speaking %r")` line, so the journal
holds no speech record at all. The coordinate still points at the surrounding
events, which is what 0021 designed it for, but there is no speech record whose
timestamp could be borrowed.

## Part 3 — the decisions

### 3.1 Wall clock, and monotonic stays where it is

The `Clock` port already exposes both, and they keep different jobs:

- **`monotonic()` stays** as the buffer's "still speaking" heuristic. It is
  immune to clock adjustments, which is exactly what a duration needs.
- **`time()` is what goes on the entry.** Its own docstring says why it exists:
  to line up against records stamped elsewhere — NVDA's log, the session
  transcript, and a human saying "around then".

A monotonic stamp would be more correct for a pure difference and joinable to
nothing. Since half the value of this field is cross-referencing artefacts that
already exist, **wall clock wins**, on the same reasoning that gave
`getLogPosition` a wall-clock `time` field.

### 3.2 It is the moment the reader **emitted** the utterance, and must not be named for speaking

The two capture modes hook different extension points:

| mode | hook | what it means |
|---|---|---|
| live | `pre_speechQueued` | the sequence is about to be **queued** for the synth |
| silent | `filter_speechSequence` | inside `speak()`, before the synth |

**Neither is audio.** In live mode especially, a long utterance already in flight
can leave seconds between this instant and the human hearing anything.

So the field is named for emission — `emittedAt` — never `spokenAt`. If it is
named for speaking, somebody will eventually build a latency claim on it that is
wrong by however long the synth queue was.

This is also the **better** number for the measurement that motivated the spec: a
"did the app respond promptly" figure should not include synth queueing and audio
latency, which belong to the synthesizer and would be noise.

One consequence to record rather than let someone rediscover: because the two
modes hook different pipeline stages, a live stamp and a silent stamp are **not
strictly comparable to each other**. At millisecond resolution against the
effects being measured this does not matter, but it is true.

### 3.3 Format: the convention already in the tree

`"%Y-%m-%d %H:%M:%S.%f"` truncated to milliseconds — exactly what
`getLogPosition` returns and exactly what `FileTranscript` writes. Same string
shape as NVDA's own log, so a stamp can be pasted into a search of `nvda.log`.

An agent computing a delta parses two of these. That is a real cost, and an epoch
float would avoid it — but it would be a second time format in a protocol that
already has one, unreadable to the human reading the same transcript, and
un-joinable to the artefacts this exists to join. Consistency wins; see *What is
deliberately not built*.

### 3.4 Braille rides along

`BrailleBuffer` is the same `IndexedBuffer`, so the field costs nothing extra
there, and "what was brailled, and when" is the same question. 0021 settled the
matching precedent for `logPosition`: braille yes, transcript no.

### 3.5 Every read that already carries `logPosition` carries this too

`getSpeech`, `getBraille`, `getLastSpeech`, and `waitForSpeech`'s match. The rule
is simply: **wherever an entry already says where it sits on the journal, it now
also says when it was captured.** Anywhere that pairing is broken, an agent has
to go back for a second read, which is the cost this spec exists to remove.

## Part 4 — class and file layout

Nothing new is created except one small pure function; this is a field added
along a path that already exists.

### Shared wire contract

| File | Role | Change |
|---|---|---|
| `shared/nvda_mcp_wire/protocol.py` | the contract | `SpeechEntry`, `BrailleEntry`, `LastSpeechResult`, `SpeechMatchResult` each gain `emittedAt: str` |
| `specs/wire/v1/schema.json` | generated, CI drift gate | regenerated |
| `specs/wire/v1/protocol.md` | hand-written prose | §7 gains the field and §3.2's warning about what the instant means |

Pre-release v1 permits the shape change; both implementations are in-tree and the
`conformance` job covers them.

### Bridge (lane 1)

| File | Role | Change |
|---|---|---|
| `domain/entities/indexed_buffer.py` | entity | `_times: list[float]` beside `_log_positions`, seeded `[0.0]` for the sentinel; `time_at(index)` mirroring `log_position_at`; `entries_since` yields 4-tuples `(text, index, logPosition, time)`; **and `_record`, per the amendment above** |
| `domain/entities/speech_buffer.py` | entity | `append` delegates its bookkeeping to `_record` |
| `domain/entities/braille_buffer.py` | entity | same |
| `domain/controllers/commands/wallclock.py` | **new** — a pure function | `format_wallclock(epoch: float) -> str`, extracted from `get_log_position.py`'s private `_wallclock` so both formats are one definition rather than two that can drift |
| `domain/controllers/commands/get_log_position.py` | controller | uses the extracted helper |
| `domain/controllers/commands/get_speech.py` / `get_braille.py` / `get_last_speech.py` / `wait_for_speech.py` | controllers | render the stamp into their result DTOs |

The buffers store an **epoch float** and the controllers render the string. The
entity keeps a number; presentation stays in the controller.

### Server (lane 2)

| File | Role | Change |
|---|---|---|
| `adapters/wire/wire.gen.go` | generated binding | regenerated; CI diffs it |
| `domain/ports/speech_reader.go` / `braille_reader.go` | ports + DTOs | `EmittedAt string` on the entry types |
| `adapters/bridge/json_lines_client.go` | adapter | `speechEntries` / `brailleEntries` map the field through |
| `domain/controllers/tools/get_speech.go` | controller | `capturedEntry` (shared with braille) gains `emittedAt`; descriptions say what the instant is and is not |
| `domain/controllers/tools/get_last_speech.go` / `wait_for_speech.go` / `get_braille.go` | controllers | same |

No new capability, no new tool, no gate change.

### Tests

| File | Tier | Asserts |
|---|---|---|
| `bridges/nvda/tests/unit/domain/entities/test_indexed_buffer.py` | unit | the stamp is per entry, survives the empty-render skip, and the sentinel reads back the seeded value — driven by the existing fake clock, so it is exact rather than approximate |
| `bridges/nvda/tests/unit/domain/controllers/commands/` | unit | each of the four reads carries the stamp |
| `bridges/nvda/tests/unit/domain/controllers/commands/test_wallclock.py` | unit | the extracted formatter, including the millisecond truncation |
| `server/domain/controllers/tools/speech_tools_test.go` | unit | passthrough, and that an absent stamp does not crash an older bridge |
| `server/tests/conformance/real_bridge_session_test.go` | conformance | the field survives the real Python bridge over a real pipe — the only tier where both bindings are real |

**Live-NVDA checklist** (small, and this is the entry's whole live risk): stamps
are present in both capture modes; they are non-decreasing across a sequence of
gestures; and one stamp matches the corresponding transcript line to the
millisecond, which is the claim that the field means what it says.

## What is deliberately not built

- **An epoch-float field, or both formats.** Part 3.3. One time format.
- **A duration or delta field.** Two stamps subtract; a server-computed delta
  would have to choose which two, and the choice is the caller's.
- **A stamp on command results** (`pressGesture` returning when it dispatched).
  Tempting, and it would complete the "X after Y" pair without a separate mark —
  but [0025](0025-one-round-trip-per-intention.md) is about to change what those
  results carry, and designing a field into them twice is exactly the waste 11.16
  was resequenced to avoid. Revisit after 11.12. Until then `getLogPosition`
  already returns a wall clock, so the "before" mark exists.
- **Backfilling the field for entries captured before this ships.** There is
  nothing to backfill from; a session's ring does not outlive it.

## Honest limits

- **It is emission, not audibility.** Part 3.2. The gap is unbounded in live mode
  and the field cannot express it.
- **Live and silent stamps are taken at different pipeline stages** and are not
  strictly comparable to each other.
- **Wall clock can step.** An NTP correction mid-session moves it. This is the
  accepted cost of being joinable to `nvda.log`; the buffer's own heuristic keeps
  using `monotonic()` precisely because it must not be affected.
- **The resolution is milliseconds**, which is what the format carries and enough
  for the 63 ms class of claim, but not for anything finer.

## Open questions

None. The shape, the clock, the naming and the format were settled in
conversation on 2026-08-15 and 2026-08-16; this document records them rather than
reopening them.

## Not in scope

Reducing the *number* of round trips ([0025](0025-one-round-trip-per-intention.md)),
and making capture itself complete ([0024](0024-a-session-the-agent-can-hear.md)).
This spec makes what is already captured answerable about time; it does not change
what is captured or how often it is asked for.
