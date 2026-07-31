# 0021 — observing the log, not just slicing it

Status: **drafted 2026-07-30**, awaiting review. Board entry **11.5**.

[0020](0020-log-slices-on-demand.md) answered *"what did command N log?"*. Running
it against a real NVDA showed that the question an agent actually has, most of the
time, is a different one: **"what has happened since I last looked?"** — and that
the command window is the wrong unit for answering it.

## What 11.4's live run exposed

Two facts, both measured on 2026-07-30 against NVDA 2026.1.1.

**A command window closes before the reader does the work.** The window brackets
`_dispatch`, which returns as soon as the handler does. NVDA carries on
afterwards, on its own thread:

```
IO - inputCore.executeGesture (18:47:56.033)   <- inside the window
IO - speech.speech.speak      (18:47:56.034)   <- one millisecond later
```

So a single window reliably contains NVDA's own `executeGesture` line and little
else. 0020's promise — "everything NVDA logged during the window" — is optimistic,
and its worked example (`exclude: ["speech.speech.speak"]`) had no speech record to
exclude until `windows` was widened past the gap.

**A command is a trigger, not a request/response.** Pressing Enter on a link can
be followed by fifteen seconds of events. The agent issues nothing during those
fifteen seconds, so there are no new windows — one span grows, and every poll
re-returns everything already read. That is the token cost 0020 exists to remove,
reappearing in the case that matters most.

## The two shapes 0020 does not serve

### Trigger, then observe

The agent acts once and watches the consequences arrive. Ordinary, and entirely
outside 0020's model after the first millisecond.

### Observe me — the human is driving

*"Watch what I do. In a few seconds a bug will appear."* Here the agent issues **no
commands at all**; every interesting record comes from the human's keystrokes. The
span model collapses to a single open span, `windows: N` means nothing, and there
are no request ids to anchor on, because a keystroke by the user is not a command.

```mermaid
sequenceDiagram
    accTitle: How an agent observes a user-driven session and finds the moment a bug appears
    accDescr: The agent asks for a log position to mark the present moment, and receives position 412. The human then works unaided, and NVDA writes records into the journal throughout. The agent polls with getLog since position 412 and receives only the new records plus a new position, 480, so nothing already read is sent twice. When the human says the bug just happened, the agent asks for the last ten seconds at error level and receives the failing records, which it can then widen around using the positions it already holds.
    participant Agent
    participant Bridge
    participant Journal as Log journal
    participant Human as Human at the reader
    Agent->>Bridge: getLogPosition
    Bridge-->>Agent: { position: 412, time }
    Human->>Journal: works; NVDA logs throughout
    Agent->>Bridge: getLog { sincePosition: 412 }
    Bridge-->>Agent: records 412..480, nextPosition 480
    Human->>Agent: "it just happened"
    Agent->>Bridge: getLog { lastSeconds: 10, minLevel: "error" }
    Bridge-->>Agent: the failing records
```

## Decided

### The mark is the F1 ritual, made programmatic

0020 opens by describing the manual ritual: *place a marker in NVDA's log, run the
repro, place another marker, copy the slice out.* The first marker is the piece it
never built. `getLogPosition` is exactly that: it returns the journal's current
position and the wall-clock time, **and no records**.

A separate command rather than reading the cursor off a `getLog` response, because
at the moment you decide to start observing you specifically do **not** want the
backlog — paying for a large slice to learn a single integer defeats the purpose.
This is the shape `getNextSpeechIndex` already has, for the same reason.

The `time` in the answer is what lets a slice be lined up against the session
transcript, NVDA's own `nvda.log`, and the human saying "around then".

### Reads never consume — the cursor belongs to the caller

`getLog` gains `sincePosition`, and every `getLog` result gains `nextPosition`.
Polling is: read from your last `nextPosition`, keep the new one.

The alternative — letting an unanchored read close the current span and open a
fresh one, so the next read is automatically a delta — is **rejected**, for three
reasons that only appeared once the observation cases were written down:

1. **It breaks 0020's own survey loop.** The spec teaches `fields: ["module"]` with
   a high `maxEntries` to see what is flooding, then a precise `exclude` on the
   next call. Both are unanchored reads; under close-on-read the second one reads
   a new, empty span and returns nothing — and `entries: 0` reads exactly like
   "my filter worked". A silent wrong answer in the loop the spec recommends.
2. **It reintroduces relative addressing.** A span minted by a *read* has no
   request id, so a span from three polls ago is reachable only as `windows: 4` —
   which shifts with every subsequent poll. 0020 rejected `HEAD~k` for precisely
   this, and the polling case is where it would bite hardest.
3. **Bug hunting is retrospective.** *"That COMError twenty seconds ago — show me
   around it again without the speech."* Consumed records have left the default
   view, and the spans holding them have no id to ask for. A caller-held cursor
   can simply be re-issued with a different filter.

The cost is one integer threaded through the loop. It is the same integer the
agent already threads for speech.

### "It just happened" needs time, not a position

A position only answers questions about marks you had the foresight to take. The
observe-me case has the opposite shape: the human notices the bug *after* it
happens. If the agent was not already polling, it has no position to look back
from.

So `getLog` also gains **`lastSeconds`** — relative to now, deliberately, rather
than an absolute timestamp: it needs no agreement on a clock format and no
tolerance for skew, and "the last ten seconds" is what a human actually says.

This looks like the relative addressing rejected above, and the difference is worth
stating. `HEAD~2` is a trap because its meaning changes as a **side effect of
something else happening** — another command runs and the same call means something
new. `lastSeconds` changes only because time passed, which is the very axis being
asked about. The expected use is one `lastSeconds` call to find the moment, then
positions to pin it down.

### Blocking beats polling — `waitForLog`

Polling every few seconds is a workaround for not being able to say *"wake me when
something interesting appears"*. The protocol already has that shape:
`waitForSpeech` blocks until matching text arrives or a timeout expires.

`waitForLog { minLevel?, contains?, timeout }` is the same thing for the journal,
and it is **pull, not push** — the agent asks and waits — so 0020's rejection of
tailing and of pushed log lines stands unchanged. For "observe me, a bug is about
to happen", the agent blocks at `minLevel: "error"` and gets the moment it happens,
with the position to widen around, instead of choosing a poll cadence and hoping.

It reuses `waitForSpeech`'s established manners: a caller-supplied timeout, a
`found: false` answer rather than an error when nothing matched, and the
Session's post-dispatch heartbeat refresh so a long wait does not kill the session
(spec 0016).

### A command's span runs to the *next* command

The window stops being `[dispatch start, dispatch end)` and becomes
`[dispatch start, next marking command's dispatch start)`. The timeline is then
fully partitioned: every record belongs to exactly one command — the one most
recently issued when it was logged.

This is what makes `windows: 1` mean something again, and three things fall out of
it:

- **The span-versus-concatenate question disappears.** Spans are adjacent, so "one
  range from the first start to the last end" and "slice each and join" are the
  same interval. 11.4 shipped the first of those after live testing refuted the
  second; under this model there is nothing left to choose.
- **`capturedAtLevel` stops being approximate.** `setLogLevel` is itself a command,
  so it closes the old span and opens a new one — the level is constant within a
  span by construction. 0020's "if a window straddles a level change" caveat, and
  11.4's "report the oldest window's floor" compromise, both go away.
- **The stored end disappears.** Span *i*'s end is span *i+1*'s start, or the
  current journal position for the open one. `SessionContext.command_windows`
  becomes `(command_id, start, level)` and `Session._close_window` has nothing to
  close.

The cost, stated: a span now means "from this command until the next", not "while
this command ran". Think for thirty seconds after a keypress and those thirty
seconds land in that keypress's span. That is the same chatter 11.4's concatenation
tried to exclude — but it is now *attributed* rather than orphaned, and still
bounded by `maxEntries` and the ring. Given the alternative is losing the records
that matter, it is the right trade, and the documentation should say plainly that
attribution is by most-recent-command, not by causation.

`getLog` still sets `marks_log = False`, and under this model that flag is
load-bearing rather than merely tidy: a read must not close the span it is reading.

### Reading an open span is fine

The last span has no end yet; it is sliced to the journal's current position.
Re-reads are monotonic supersets, never contradictory, which is what a tail should
be. An agent that reads too early gets a partial answer and more on the next call.

### Silent mode blinds the log, and that is our own doing

Measured 2026-07-30, identical browsing of one site for twenty seconds:

| session | records journalled |
|---|---|
| `debug`, live | 1368 |
| `io`, live | 64 |
| `io`, silent | 39 |

The silent figure is low because of **us**, not NVDA. `NvdaSilentSpeechSource`
registers on `filter_speechSequence`, which NVDA applies at `speech/speech.py:1096`
and empties; `speak()` then returns before reaching its own
`log.io("Speaking %r")` at line 1165. So a silent session removes NVDA's speech
records from the log entirely — including from the user's own `nvda.log`.

This matters beyond a missing convenience: 0020 justified deleting 0009's capture
file on the grounds that *"the level raise is global, so NVDA's own nvda.log
already holds identical records"*. In a **silent** session that is partly false,
and false because the bridge is standing there. The fallback 0020 leans on is
degraded by the very session most likely to need it.

Two things follow, and one of them is a refusal.

**Do NOT synthesise the record into NVDA's log.** Writing `Speaking [...]` when
nothing was spoken makes a shared artifact — the file the user reads and pastes
into issues — assert something untrue. A bridge that leaves a gap in that file is
better than one that fills the gap with fiction.

**Do NOT duplicate the speech content into the journal either.** It is already
captured, in a better place: every suppressed sequence goes into the
`SpeechBuffer` and is readable through `getSpeech`, indexed and ordered, which is
strictly more structured than a formatted `Speaking %r` line.

### What the agent wants is a shared coordinate, not a second copy

Asked directly which surface an agent would rather read speech from — the log or
the speech ring — the honest answer is **both, because they answer different
questions**, and the split is sharp:

- The **ring** answers *what was said*. It is the oracle: indexed, deterministic
  under silent capture, and already served by `waitForSpeech` without polling.
- The **log** answers *when it was said relative to everything else*. Its unique
  value is adjacency, not content — 11.4's central finding was legible only as
  `executeGesture (…56.033)` followed by `speech.speak (…56.034)`, and no speech
  buffer could ever have shown that one-millisecond gap.

Which means duplicating speech text into the journal would buy the *less* useful
half. What is actually missing is the ability to place a ring entry on the log's
timeline. So: **speech buffer entries carry the journal position captured at the
moment they were appended.** One integer per utterance, no fiction in anyone's
log, and it makes the join exact rather than eyeballed — read the ring for what
was said, the journal for what surrounded it, and the position to line them up.

An **open question** deliberately left for review: whether the same coordinate
should be added to braille entries and to transcript lines. It is the same idea
and probably the same integer, but nothing has demanded it yet.

### Three surfaces, and what each is actually for

Written down because this got confused twice in one review conversation. A
session produces three records of what happened, and they are not
interchangeable:

| surface | answers | addressed by | lifetime |
|---|---|---|---|
| **speech ring** | *what was said* | index (`sinceIndex`) | dies at teardown |
| **transcript** | *what the session did*, one ordered narrative | line / position | **survives on disk** |
| **journal** | *what the reader did internally* | position, time, command span | dies at teardown |

The ring is the oracle — append-only and **unbounded** within a session
(`IndexedBuffer`), so nothing ages out of it while the session lives. The journal
is the diagnosis, and the only one that is a bounded ring. The transcript is the
narrative, in the bridge's own vocabulary, and the only one that outlives the
session.

The temptation each time is to copy content between them. Resist it: the ring
already holds every utterance in better shape than a log line, and the transcript
already interleaves gestures with speech on the **same clock** the journal stamps
with, so `GESTURE tab` at `09:02:58.612` and `SPEECH '...'` at `09:02:58.626`
already correlate without anyone duplicating anything. What is missing is never
content — it is a shared coordinate, which is why speech entries gain
`logPosition` above rather than the journal gaining speech text.

### Two records, not one — and the transcript stays where it is

`connect_reader` hands the agent `logPath` and nothing else, which is verbatim
0020's opening complaint about `nvda.log`: *"what the agent receives is a path,
and reading it means reading the whole file"*, and *"reading the file also assumes
the agent and the reader share a filesystem"*. The obvious conclusion is that the
transcript should cross the wire too. **It should not**, and working out why
settles what the agent actually needs.

**The MCP server runs on the agent's side.** It is spawned by the MCP client, so
its filesystem is already the agent's filesystem. A record the *server* writes
needs no transmission at all — no new command, no paging, no ordering constraint
on teardown, no guard against a half-finished transfer. And the server can build
it from what already passes through its hands: it sent every command and saw
every response. It also survives a bridge that dies abruptly, where a bridge-side
file is stranded on a machine nothing can reach any more.

**But it cannot replace the reader-side transcript**, for three reasons, the last
of which is decisive:

1. **Speech completeness.** The bridge sees every utterance; the server sees only
   what the agent fetched. `Transcript`'s own docstring is explicit that it is
   written bridge-side so it is *"complete even if the agent never fetched some
   speech"* — and in a silent run, where nobody heard anything, that record is
   the tester's only reconstruction of what was said.
2. **The audience is the human at the reader.** A blind tester looking for what
   happened looks on their own machine, with their own tools. A file on the
   agent's machine may be on a different computer entirely.
3. **Timestamp fidelity.** The bridge stamps speech at capture. A server could
   only stamp it at *fetch* — batched, later, in fetch order — which destroys the
   adjacency that makes the file worth reading. `09:02:58.612 GESTURE tab`
   followed by `09:02:58.626 SPEECH` is the whole value; a server-written timeline
   would carry accurate gesture times beside fictional speech times, which is
   worse than not having it.

So there are **two artifacts with two audiences**, and conflating them was the
error:

| record | audience | written by | how it is reached |
|---|---|---|---|
| session transcript | the human at the reader | bridge, at capture time | `logPath`, on the reader's disk |
| session record | the agent | server, from its own traffic | already on the agent's filesystem |

**`getTranscript` is therefore rejected.** The single case for transmitting was
"the agent wants the complete record, including speech it never fetched" — and
that already has a cheaper answer with a command that exists today:
`getSpeech(sinceIndex: 0)` returns the entire ring, unbounded and indexed, at any
point before `bye`. An agent that wants a complete record can complete its own,
with no new wire surface at all.

What changes is documentation, not protocol: **`logPath` is demoted** to what it
is — a convenience naming the human's artifact on the reader's machine — and
explicitly *not* a contract an agent should depend on, since for a remote bridge
it names a file the agent cannot open. The server-side session record is the
agent's answer, and it costs nothing to build.

### A single marker explains the silence in the user's own log

Independent of everything above, and cheap: emit **one** record into NVDA's log
when a silent session starts, and one when it ends —
`nvdaMcpBridge: speech suppressed for this session` / `restored`. Zero
per-utterance cost, honestly attributed to us, and it means a human opening their
own `nvda.log` next week is not baffled by a stretch with no speech in it. Right
now that gap is unexplained and reads like an NVDA fault.

This is the *only* thing this entry writes into NVDA's log, and it is deliberately
about the session, not about any utterance.

### The mode trade-off has to be said out loud

`connect_reader`'s mode description, and 0020's, should state it plainly, because
it is a trap that has already cost one wrong conclusion: **silent buys
deterministic capture and costs log fidelity; live buys a faithful log and costs
determinism.** An agent debugging *"why did it say the wrong thing?"* may well
want live for exactly that reason.

### Records carry epoch time

`lastSeconds` needs a numeric time to compare against, and the journal currently
keeps only NVDA's formatted string — which is **time-only, no date**
(`18:47:56.034`), so it cannot be compared across midnight or subtracted at all.
Records gain `record.created` (a float) alongside the formatted timestamp. One
float per record; `_estimate_size`'s accounting barely notices.

## Wire contract changes

```python
class Command(StrEnum):
    GET_LOG_POSITION = "getLogPosition"
    WAIT_FOR_LOG = "waitForLog"

@dataclass
class GetLogParams:            # 0020's, extended
    sincePosition: int | None = None   # read forwards from here; wins over commandId
    lastSeconds: float | None = None   # ...or from N seconds ago until now
    # commandId / windows / minLevel / contains / exclude / fields / maxEntries
    # are unchanged

@dataclass
class LogPositionResult:
    position: int              # the journal's current append position
    time: str                  # wall clock, for lining up against other artifacts

@dataclass
class LogSliceResult:          # 0020's, extended
    nextPosition: int          # pass as sincePosition to continue the tail
    # text / entries / matched / truncated / fromCommandId / toCommandId /
    # capturedAtLevel are unchanged

@dataclass
class SpeechEntry:             # existing; gains one field
    logPosition: int           # the journal position when this was captured

@dataclass
class WaitForLogParams:
    timeout: float
    minLevel: LogLevel | None = None
    contains: list[str] | None = None

@dataclass
class WaitForLogResult:
    found: bool
    position: int              # where the match landed, to widen around
    text: str                  # the matching record, formatted; empty when not found
```

The three anchors are mutually exclusive and resolved in one order:
`sincePosition`, then `lastSeconds`, then `commandId`/`windows` (0020's default).
Supplying more than one is an error rather than a precedence puzzle.

A `sincePosition` below the ring's oldest surviving record already reports
`truncated: true` — which is how a poll loop learns it fell behind, and is a real
possibility at `io`, where ten thousand records is a minute or two.

`PROTOCOL_VERSION` stays 1: two commands and three optional fields are added, and
an older bridge simply does not advertise them.

## Class/file layout

1. **`domain/entities/log_journal.py`** — records gain `created: float`; the ring
   gains `slice_since(position)` and `slice_last_seconds(seconds)`; `mark()` is
   already the position `getLogPosition` returns.
2. **`domain/controllers/commands/get_log_position.py`** — trivial handler,
   `marks_log = False`.
3. **`domain/controllers/commands/wait_for_log.py`** — blocks on the journal with a
   caller-supplied timeout, in the shape `wait_for_speech.py` established.
4. **`domain/controllers/commands/get_log.py`** — the three anchors and
   `nextPosition`.
5. **`domain/controllers/session.py`** — spans lose their stored end; `_close_window`
   goes, replaced by "opening a span closes the previous one".
6. **`domain/controllers/commands/session_context.py`** — `command_windows` becomes
   `(command_id, start, level)`; the accessors follow.
7. **`domain/entities/speech_buffer.py`** — each entry records the journal
   position it was captured at, so a ring entry can be placed on the log's
   timeline. The buffer takes the position as a value; it does not learn about
   the journal.
8. **Server** — `get_log_position` and `wait_for_log` tools, gated on `log`; the
   `LogReader` port and the bridge client gain both. Separately, and needing no
   wire change, the server keeps its own session record from the traffic it
   already handles, and publishes it beside the session info resource.

## Tests

9. Journal: `slice_since`, `slice_last_seconds`, an aged-out `sincePosition`
   reporting truncation, epoch time surviving the ring.
10. `GetLogHandler`: each anchor, and that supplying two is refused.
11. `WaitForLogHandler`: a match, a timeout, and that a long wait does not trip the
    watchdogs.
12. Session: spans are contiguous with no gaps; a span extends to the next marking
    command; `getLog` does not close the span it reads.
13. Go tool tests and conformance for both new commands.
14. Speech entries carry a journal position that actually falls inside the
    window the utterance belongs to, in **both** capture modes.
15. The server's own session record covers a whole session from its traffic
    alone, with no bridge call added.
16. **Live** — the two shapes this entry exists for, which is where 11.4's model
    failed: a trigger followed by a poll loop while the consequences arrive, and a
    human-driven session found via `lastSeconds`.

## Live-NVDA checklist

1. Press a gesture, then `getLog` for that command alone: the slice now contains
   NVDA's speech and event records, not just `inputCore.executeGesture`. This is
   the check 11.4 could not pass.
2. `getLogPosition`, then work the reader by hand for ten seconds, then `getLog`
   with that `sincePosition`: exactly the records from those ten seconds.
3. Poll three times with the previous `nextPosition`: no record is returned twice,
   and none is skipped.
4. Re-issue an identical `sincePosition` with a different `exclude`: the same
   records, re-filtered — nothing was consumed by the first read.
5. `lastSeconds: 10` right after something audible: the records for it, with no
   position taken beforehand.
6. `waitForLog { minLevel: "error", timeout: 30 }`, then provoke an error: it
   returns at the moment it happens, with a usable position.
7. On a busy session, poll slower than the ring turns over: `truncated: true`
   rather than a silent gap. Use `debug`, not `io` — at 12, `io` excludes the
   DEBUG records that actually flood.
8. NVDA's own log carries one `speech suppressed` marker at the start of that
   session and one `restored` at the end, and nothing per utterance.
9. In a **silent** session, take a speech entry's `logPosition` and read the
   journal around it: the surrounding events are there even though the
   `Speaking` record itself is not, which is the whole point of the coordinate.

## Out of scope

- Pushing or tailing without being asked. `waitForLog` blocks on a request; nothing
  in this protocol pushes, and 0020's reasoning stands.
- Absolute timestamp queries. `lastSeconds` covers the case without a clock-format
  agreement; positions cover everything needing precision.
- Regular expressions, still. Substrings cover the cases and cannot hang the reader.
- Moving the session transcript across the wire (see above). It stays the
  human's artifact on the reader's disk; the agent's equivalent is the
  server's own record, which needs no protocol.
- Cross-session history. The journal remains session-scoped; the answer for
  post-mortems is NVDA's own `nvda.log`, bracketed by the transcript's timestamps.

## Definition of done

A command's span reaches the next command, so one window holds what the command
actually caused; `getLogPosition` marks the present without returning records; a
poll loop driven by `nextPosition` neither repeats nor skips, and re-reading the
same `sincePosition` is idempotent; `lastSeconds` answers "it just happened" with
no prior mark; `waitForLog` returns at the moment a matching record appears;
falling behind the ring is reported rather than silent; every gate green
(`doctor`, `shared`, `bridge`, `types`, `gates`, `go`, `conformance`); the live
checklist run with the tester at the machine.
