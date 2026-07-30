# 0020 — log slices on demand

Status: **drafted, awaiting review**. Board entry **11.4** (proposed).

This finishes what [0009](0009-nvda-log-capture.md) started. That entry set out to
automate the debugging ritual — *"place a marker in NVDA's log, run the repro,
place another marker, copy the slice out"* — and it narrowed the haystack from
"everything since NVDA started" to "this session". Then it stopped: what the agent
receives is a **path**, at `hello`, and reading it means reading the whole file.

This entry narrows it one step further, to **one command's window**, and lets the
agent filter that window before it crosses the wire.

## Goal

An agent that has just pressed a key, or just had a command fail, can ask what
NVDA logged *while that command ran* — and can say "at info level, but without
the speech output, because I already know what was spoken".

## The problem, stated exactly

Three facts, each verified on 2026-07-30:

- `LogCapture` is `path` / `start` / `stop`. There is no way to read the capture
  back through the bridge at all, and no command in the contract returns log
  content: only `logPath` and `nvdaLogPath` (strings) ever cross the wire.
- So an agent reads the file itself. During the 11.2 review session that meant
  three separate `nvda.log` reads of 40–130 KB, each one truncated by the
  harness, to answer one question ("why did the listener stop?"). The answer was
  in a handful of lines.
- Reading the file also assumes the agent and the reader share a filesystem.
  Nothing else in this project assumes that: the bridge exists precisely because
  the reader's environment is reachable only through it.

The cost is not the transport. Measured on the real pipe, a command round trip is
**0.2–0.5 ms**; what is slow is moving tens of thousands of tokens of log into a
model's context to find four lines.

## Decided

### The unit is one command's window, bracketed by the dispatch loop

The Session already knows exactly when a command starts and finishes — it is the
one place that dispatches. So it records the journal position either side of
`_dispatch()`, giving every request an exact `[start, end)` window, and keeps the
last **50** of them.

```mermaid
sequenceDiagram
    accTitle: How a command's log window is bracketed and later read
    accDescr: The agent sends pressGesture with request id 7. The bridge records the log journal position, dispatches the command, and records the position again, so entries NVDA logged during that command form a window. NVDA's main thread writes log records throughout. Later the agent sends getLog for command id 7, and the bridge returns only the records inside that window, after applying the requested filters.
    participant Agent
    participant Session as Bridge session
    participant Journal as Log journal
    participant NVDA as NVDA main thread
    Agent->>Session: pressGesture { id: 7 }
    Session->>Journal: mark start (position 412)
    Session->>NVDA: inject the keystroke
    NVDA->>Journal: IO speech.speak "Elements list"
    NVDA->>Journal: DEBUGWARNING IAccessible COMError
    Session->>Journal: mark end (position 415)
    Session-->>Agent: { pressed: [...] }
    Agent->>Session: getLog { commandId: 7, minLevel: "info" }
    Journal-->>Session: entries 412..415, filtered
    Session-->>Agent: { text, entries, matched, truncated }
```

Windows are disjoint by construction, so "the log for command 7" is never
contaminated by command 8.

### Slices are anchored by request id, not by "N commands back"

The obvious ergonomic shape is `HEAD~2`, and it is a trap: it is *relative*, so it
means something different the moment another command runs. An agent that presses a
key, reads focus, then asks for `HEAD~2` gets the keypress window only by luck,
and a debugging loop is exactly where extra commands appear between the failure
and the question.

The agent already knows the id it sent. So:

- `commandId` — the anchor. Defaults to the most recently marked command.
- `windows` — how many command windows to include, counting **back** from the
  anchor. `windows: 3` is the `HEAD~2` idea with an absolute anchor.

### The journal holds structured records, not formatted bytes

Byte offsets into the capture file were the first sketch and are worse in three
ways: the end offset races the handler's flush; filtering by level or module means
re-parsing text the logger had already structured; and the file is formatted, so
nothing else can be recovered.

The tee is a `logging` handler on `log.root`, so it sees `LogRecord` objects
**before** formatting — level, module, thread, message, timestamp, all exact. It
therefore keeps a bounded in-memory journal of records alongside the file, and
formats only what a `getLog` actually returns.

Costs, stated rather than discovered later:

- **Memory.** Bounded ring, **5 000 records** or **2 MB**, whichever comes first.
- **Slices expire.** A window whose records have aged out returns what survives
  plus `truncated: true`. At `io` level on a busy session that can be seconds, and
  it is the right trade: an unbounded journal inside NVDA is a memory leak in a
  screen reader.
- The file from 0009 is **unchanged**. It stays the human artifact, and `logPath`
  keeps its contract.

### Filters compose, and both directions matter

Three knobs, evaluated in this order, all optional:

| Filter | Meaning |
|---|---|
| `minLevel` | drop records below this level (the `LogLevel` enum, extended with `warning` and `error`) |
| `contains` | keep only records whose message matches any of these substrings |
| `exclude` | drop records whose **module or message** matches any of these |
| `fields` | which fields of each record to render, defaulting to all four |

`fields` is what structured records buy beyond exact filtering, and it is a
bigger saving than it looks: dropping the timestamp and thread from 200 records
removes more characters than most `exclude` patterns do. `["level", "message"]`
is the compact form worth reaching for; the default stays `["time", "level",
"module", "message"]` so a slice pasted into an issue still reads like
`nvda.log`.

It also enables a cheap survey: `fields: ["module"]` with a high `maxEntries`
answers "what is flooding this window?" in a few hundred bytes, so the next call
can `exclude` precisely instead of guessing.

Marlon's case — *"level info, but not output speech, because that I already
know"* — is expressible two ways, and both should work:

- `minLevel: "info"` alone, because NVDA logs speech at `IO`, which is below
  `INFO`; or
- `minLevel: "debug"` with `exclude: ["speech.speech.speak"]`, when the IO-level
  detail is wanted for everything *except* speech.

`exclude` matches the module name as well as the message precisely so the second
form is exact rather than a guess at message wording.

### The level is the agent's to change, mid-session — and only forwards

`hello` fixing the capture level for the whole session was the wrong shape once
the bridge can be on another machine: the agent, not the connect call, is what
knows which level a given question needs. But there is a hard constraint that
decides the design:

**A level cannot be raised retroactively.** Python's logging decides at the
*logger* whether a record exists at all; a handler only ever sees what was
emitted. If NVDA's root is at `INFO`, `DEBUG` records were never created, so no
journal holds them and no filter recovers them. Of the two options considered —
"return what was captured" or "raise the level" — raising is the useful one, and
it is useful **forwards only**. The loop is: raise, re-run the command, read the
slice. That is the same loop as the F1 ritual, which also cannot see the past.

Downwards is free: the journal holds more than asked for and the filter shows
less.

So, three levels rather than one, which is the "parallel journal" idea made
explicit:

| | Set by | Purpose |
|---|---|---|
| NVDA's **logger** floor | `hello`, then `setLogLevel` | what NVDA emits at all — the only one that cannot be undone after the fact |
| the **file** handler's level | `hello`, unchanged from 0009 | keeps `logPath` the clean human artifact it is today |
| the **journal** handler's level | `setLogLevel` | what slices can see, independent of the file |

`hello` keeps its `logLevel` parameter: without it the *first* commands — the
handshake itself, whatever failed immediately — are unreachable, and those are
often the ones being debugged. It becomes the starting value rather than the
session's fixed one.

`setLogLevel` restores NVDA's own level at teardown, exactly as 0009's
hello-scoped change already does; the machinery is the same, only its trigger
moves.

Two costs, stated because a screen reader's user pays them:

- **NVDA at `debug`/`io` is slower for the human**, not just for us. Raising the
  floor is a real change to their reader, so it belongs in an explicit command
  they can see in the transcript, not as an implicit side effect of asking for a
  slice.
- **The ring fills faster**, so windows expire sooner. At `io` on a busy session
  that is seconds, and `truncated: true` is how the agent finds out.

`setLogLevel` sets `mutates_reader = True`, consistent with `setConfig`: it is a
temporary but real change to the reader. **Open question for 11.3** (observe-only)
— an observe-only session arguably still wants to raise its own log level, since
nothing about it moves the user's machine. Flagged rather than decided here.

### The payload is bounded, and says so when it truncates

`maxEntries` defaults to **200**. The result carries `entries` (how many are in
the text), `matched` (how many passed the filters before the cap), and
`truncated`. An agent that sees `matched: 4000, entries: 200` knows to filter
harder rather than to page blindly.

Returning **formatted text**, not structured records, is deliberate: it is what
the F1 ritual produces, what a human pastes into an issue, and by far the most
compact form. An agent that wants structure can filter more narrowly instead.

### `getLog` does not mark itself

Otherwise the default anchor is always the `getLog` that just ran, whose window is
empty. `CommandHandler` gains `marks_log: bool = True`, and `GetLogHandler` sets
it `False` — the same shape as `resets_inactivity`, which `ping` introduced for
the same class of reason.

### It is one new capability, `log`

A reader whose bridge cannot reach its diagnostic log never announces `log`, and
the `get_log` tool is never advertised — the structural gate braille and
`interact` already use. `PROTOCOL_VERSION` stays 1: this adds a command and a
capability, and an older bridge simply does not advertise it.

### What a slice contains, honestly

**Everything NVDA logged during the window**, not everything the command caused.
NVDA logs from its main thread while the bridge dispatches on the session thread,
so focus events, other add-ons, and unrelated chatter land in the same window.
That is usually what a debugger wants, and saying it here stops the first
surprising slice reading like a bug.

For the same reason a window can be *large* for a deliberately blocking command:
`waitForUserReply` with a 110 s poll brackets everything NVDA did for those two
minutes.

### Pull, not push — **rejected: attaching slices to error replies**

Stapling the slice onto every error reply is tempting and wrong: it makes every
error unbounded, for the majority of errors where nobody wants the log. The agent
asks when it wants it.

Also rejected: pushing log lines as they happen. Nothing in this protocol pushes,
and a log tail is the last thing that should be the first exception.

## Wire contract changes

```python
class Capability(StrEnum):
    LOG = "log"

class Command(StrEnum):
    GET_LOG = "getLog"
    SET_LOG_LEVEL = "setLogLevel"

@dataclass
class GetLogParams:
    commandId: int | None = None   # default: the most recently marked command
    windows: int = 1               # how many windows, counting back from the anchor
    minLevel: LogLevel | None = None
    contains: list[str] | None = None
    exclude: list[str] | None = None
    fields: list[str] | None = None   # default: time, level, module, message
    maxEntries: int = 200

@dataclass
class SetLogLevelParams:
    level: LogLevel                # raises NVDA's own floor; forwards only
    fileToo: bool = False          # leave logPath's file at the session level

@dataclass
class LogLevelResult:
    level: LogLevel                # now in force
    previous: LogLevel

@dataclass
class LogSliceResult:
    text: str          # formatted like nvda.log, newline-joined
    entries: int       # records in `text`
    matched: int       # records that passed the filters, before maxEntries
    truncated: bool    # matched > entries, or the window had aged out of the ring
    fromCommandId: int
    toCommandId: int
    capturedAtLevel: LogLevel  # the floor in force while this window was recorded
```

`LogLevel` gains `WARNING` and `ERROR` (it exists today to *request* a capture
level, where those are useless; as a filter they are the common case).
`COMMAND_SHAPES` gains two rows; the schema and the Go binding are regenerated.

`capturedAtLevel` earns its place: once the level is dynamic, an empty slice is
ambiguous between "nothing was logged" and "you were not capturing that", and the
agent cannot tell which without being told. Reporting the floor that was in force
turns a confusing retry loop into one obvious next call.

## Class/file layout

### Bridge — domain (strict-checked)

1. **`domain/entities/log_journal.py`** — the bounded ring of records and the
   window marks. Pure: takes records as `(level, module, message, timestamp)`
   tuples, knows nothing about `logging`. Owns the caps and the formatting.
2. **`domain/ports/log_capture.py`** — gains `position() -> int` and
   `slice(start, end, *, min_level, contains, exclude, max_entries)`.
3. **`domain/controllers/commands/get_log.py`** — `GetLogHandler`, `marks_log =
   False`, resolves the anchor and the window count, delegates filtering to the
   journal.
4. **`domain/controllers/session.py`** — records the journal position either side
   of `_dispatch()` for handlers whose `marks_log` is True, keeping the last 50.
5. **`domain/controllers/commands/command_handler.py`** — the `marks_log` flag.
6. **`registry.py`** — the handler, plus `Capability.LOG` in `NVDA_CAPABILITIES`.

### Bridge — adapters (NVDA edge, pyright-ignored)

7. **`adapters/nvda_log_capture.py`** — the existing `FileHandler` gains a sibling
   handler that appends to the journal. Both attach to `log.root`; the file keeps
   0009's behaviour exactly.

### Server

8. **`domain/ports/log_reader.go`** — the `log` capability port.
9. **`domain/controllers/tools/get_log.go`** — the `get_log` tool, gated on `log`,
   with the level/filter parameters and the "capture level is fixed at connect"
   warning in its description.
10. **`fakes/log_reader.go`**, `testsupport/connection.go` — the double and its
    wiring.

### Tests

11. Journal unit tests: window bracketing, the ring aging out, each filter, the
    filters composed, the cap and `truncated`.
12. `GetLogHandler` tests: default anchor, `windows` > 1, an unknown id, and that
    `getLog` does not become its own anchor.
13. Go tool tests: gating, parameter pass-through, bounds.
14. Conformance: `exerciseGetLog` — a real slice over a real bridge.
15. Live: that a gesture's window really contains NVDA's own records, and that
    excluding `speech.speech.speak` at `debug` removes speech and keeps the rest.

## Live-NVDA checklist

1. Press a gesture, then `get_log` for that command: the slice contains NVDA's own
   lines for it and nothing from before it.
2. `minLevel: "info"` on a session captured at `debug` drops the speech records.
3. `exclude: ["speech.speech.speak"]` at `debug` drops speech and keeps the
   IAccessible/UIA chatter.
4. `windows: 3` returns three commands' worth, in order.
5. On a session captured at `info`, `minLevel: "debug"` returns nothing and says
   `capturedAtLevel: "info"`; then `set_log_level("debug")`, re-run the command,
   and the same slice request has the debug records. Raising is forwards only, and
   this is the check that says so out loud.
7. `set_log_level` restores NVDA's own level at teardown -- verify in NVDA's
   General settings that it reads what it did before the session.
6. A slice from a busy `io` session reports `truncated: true` rather than
   returning megabytes.

## Out of scope

- Reading the log of a *previous* session. The journal is session-scoped, like
  the buffers; the file at `logPath` remains for post-mortems.
- Regular expressions. Substrings cover the cases and cannot hang the reader.
- Structured records on the wire (see above).
- Pushing or tailing.
- Any change to the `logPath` file from 0009.

## Definition of done

The bridge advertises `log`; `get_log` appears only when it does; a command's
window is exact and disjoint from its neighbours; filters compose in both
directions; payloads are bounded and honest about truncation; the file from 0009
is byte-for-byte unaffected; every gate green (`doctor`, `shared`, `bridge`,
`types`, `gates`, `go`, `conformance`); the live checklist run with the tester at
the machine.
