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
7. **Server** — `get_log_position` and `wait_for_log` tools, gated on `log`; the
   `LogReader` port and the bridge client gain both.

## Tests

8. Journal: `slice_since`, `slice_last_seconds`, an aged-out `sincePosition`
   reporting truncation, epoch time surviving the ring.
9. `GetLogHandler`: each anchor, and that supplying two is refused.
10. `WaitForLogHandler`: a match, a timeout, and that a long wait does not trip the
    watchdogs.
11. Session: spans are contiguous with no gaps; a span extends to the next marking
    command; `getLog` does not close the span it reads.
12. Go tool tests and conformance for both new commands.
13. **Live** — the two shapes this entry exists for, which is where 11.4's model
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
7. On a busy `io` session, poll slower than the ring turns over: `truncated: true`
   rather than a silent gap.

## Out of scope

- Pushing or tailing without being asked. `waitForLog` blocks on a request; nothing
  in this protocol pushes, and 0020's reasoning stands.
- Absolute timestamp queries. `lastSeconds` covers the case without a clock-format
  agreement; positions cover everything needing precision.
- Regular expressions, still. Substrings cover the cases and cannot hang the reader.
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
