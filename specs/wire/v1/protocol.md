# nvda-mcp wire protocol — v1

The published contract between an **MCP server** and a **screen-reader bridge**.
This is the human half of the contract; [`schema.json`](schema.json) beside it is
the machine half, generated from the reference Python implementation
(`shared/nvda_mcp_wire/protocol.py`) so shapes and prose cannot disagree.

A bridge author in any language implements this document plus the schema. The
NVDA bridge (`bridges/nvda/`) is the reference implementation; JAWS and TalkBack
bridges are anticipated (see
[spec 0005](../../0005-multi-reader-direction.md)) and would speak this same
contract with reader-specific values.

`protocolVersion` for this document is **1**. It is a pre-release version with no
external consumers yet, so it may still be amended in place; once a non-Python
bridge depends on it, changes go through a version bump.

## 1. Transport and framing

- The bridge **listens**; the server **dials**. The connection is always
  local-machine-only — never a routable interface. (An Android TalkBack
  bridge is the anticipated exception, reached over an `adb`-forwarded or
  Wi-Fi socket; it is still the listener.) A Windows bridge may offer either
  (or both, config-selectable) of:
  - a **TCP socket** bound to loopback (`127.0.0.1`) only. Default port:
    **8765** (`DEFAULT_PORT`).
  - a **Windows named pipe** (spec 0010), rejecting remote clients
    (`PIPE_REJECT_REMOTE_CLIENTS`) and restricted by DACL to the owning
    user — the pipe analogue of the loopback-only bind. Default name:
    `\\.\pipe\nvdaMcpBridge` (`DEFAULT_PIPE_NAME`).
  Either way the framing and every command below are identical: the choice of
  transport is a connection-establishment detail, invisible once `hello` has
  completed.
- **Pipe naming convention.** A bridge offering a named pipe SHOULD name it
  `<reader>McpBridge`, where `<reader>` is the same value the bridge sends as
  `hello`'s `reader.name`. The convention exists so that a server can ship a
  sane default endpoint for a reader, and a user can predict the name when
  configuring one by hand. It is a naming rule only: it confers no trust, a
  server never infers an endpoint from the namespace, and `hello` remains the
  sole authority on which reader actually answered. The NVDA bridge already
  satisfies it (`\\.\pipe\nvdaMcpBridge`, `reader.name = "nvda"`).
- Framing is **JSON Lines**: each message is one JSON **object**, UTF-8 encoded,
  serialized without embedded newlines, terminated by a single `\n`. A reader
  reassembles chunks into newline-delimited frames and must drain any complete
  buffered lines before polling the socket again, so a message that already
  arrived is never lost to a later idle timeout.
- One object per line. A line that is not a JSON object (a JSON array, scalar,
  or malformed text) is a protocol fault — see §2.

## 2. Envelope

Two frame types cross the wire.

A **request** (server → bridge):

- `id` (int, required) — correlation id chosen by the server; the matching
  response echoes it.
- `cmd` (string, required) — the command name (§5). An unknown name is **not** a
  framing fault: the bridge replies with an error response and the session
  continues.
- `params` (object, optional) — command parameters; defaults to `{}`.

A **response** (bridge → server):

- `id` (int, required) — the request's id.
- Exactly **one** of:
  - `result` — the command's result payload (shape per §5), or
  - `error` — an object `{ "message": string }`.

Fault handling, all of which keep the session alive once established (§3):

- Unknown `cmd` → error response.
- A malformed line, a non-object line, or params that fail validation → error
  response (the reference implementation raises `ValidationError`, reported as an
  error message).
- Extra, unrecognized object fields are **ignored**, so a newer peer may add
  fields without breaking an older one.

## 3. Handshake and session lifecycle

1. The server sends `hello` **first**. It is the only command accepted before the
   handshake completes; any other command pre-handshake ends the connection.
2. `hello` params carry the server's `protocolVersion` and the requested capture
   `mode` (§4). The bridge requires `protocolVersion` to **equal** its own; a
   mismatch fails the handshake with an error response and the session ends.
   An optional `logLevel` (one of `debug`, `io`, `debugwarning`, `info` —
   NVDA's own valid logging levels) temporarily raises the reader's log
   verbosity for the session; omitted or absent leaves it unchanged. **This is
   a real, if temporary, change to the reader's own diagnostic logging, not a
   filter private to the capture file** — a logger only hands a record to any
   handler once it has decided to emit the record at all, so a bumped level
   is visible in the reader's own log too, for the session's duration. It is
   always restored at teardown, on every exit path.
   An optional `persona` (string) declares **what the agent is standing in for**
   this session — `user`, `validator` or `expert` (spec 0029) — and like `mode`
   it is fixed for the session's whole lifetime. The bridge records it (in its
   transcript, and wherever it tells the human that a session has begun) and may
   use it to decide what guidance to serve. **It is a plain string, not a closed
   enumeration, and a bridge MUST NOT reject a value it does not recognise** —
   see §4, which states the rule and why. Omitted or empty means the server did
   not declare one, which an older server will not; a bridge treats that exactly
   as it treats an unrecognised value.
3. On success the bridge replies with `HelloResult`:
   - `protocolVersion` (int) — the bridge's version.
   - `reader` (object `{ name, version }`) — **which** screen reader answered
     (§6). The NVDA bridge sends `name = "nvda"`.
   - `capabilities` (array of strings) — what this bridge supports (§4).
   - `mode` — the capture mode now in effect.
   - `synth` — the name of the reader's current speech synthesizer.
   - `logPath` — absolute path to this session's human-readable transcript
     (the bridge's own record of session events — gestures, speech, open/close).
     **A convenience, not a contract an agent should depend on** (spec 0021): it
     names an artifact for the *human at the reader*, on the reader's disk, and
     for a remote bridge that is a file the agent cannot open. An agent wanting
     its own complete record of what was said calls `getSpeech` with
     `sinceIndex: 0` — the ring is unbounded within a session, so that returns
     everything, at any point before `bye`. There is deliberately no
     `getTranscript`: transmitting the file would buy nothing that command does
     not already give, and the transcript's value is its capture-time timestamps,
     which only the bridge can write.
   - `bridgeVersion` (string, optional) — the BRIDGE add-on's own version, not
     the reader's. Absent from a build predating the field.
   - `guidance` (object, optional) — **this reader's own written guidance for
     the persona this session declared**, in exactly the shape `getGuidance`
     answers with (`{ persona, recognised, text }`). Spec 0022 A.5.

     Sent in the handshake because the persona arrived in `HelloParams`, so the
     bridge already knows which document is wanted, and this reply was already
     being written: the document therefore costs **no additional round trip**,
     and connect stays one (spec 0025).

     `getGuidance` is unchanged and remains, for a re-read and for a bridge that
     would rather answer on demand. **A server that receives this field MUST NOT
     also call `getGuidance` for the same session**; one that does not receive it
     falls back to calling it, which is how a bridge predating this field keeps
     working. Both routes describe one document, so a bridge that sends this
     field MUST compose it the same way it composes `getGuidance`'s answer.

     Omitted means this bridge publishes no guidance of its own — a supported
     configuration, not a failure. A bridge that does not announce the `guidance`
     capability (§4) MUST omit it.
4. After a successful handshake the session is **tolerant**: a failing command
   yields an error response and the session keeps running. Only the conditions in
   §6 (teardown) end it.

## 4. Capture modes and capabilities

**Capture mode** is chosen once, at `hello`, and fixes how speech is captured for
the whole session:

- `silent` — the reader's speech is intercepted *before* it reaches the
  synthesizer and captured there, so the user hears nothing. The real synth stays
  loaded and active throughout: nothing is swapped, renamed or terminated, so the
  reader and every add-on running inside it continue to see their configured
  synth, valid and in use. The bridge **must** lift the interception on every
  teardown path (§6). (The NVDA bridge does this at
  `speech.extensions.filter_speechSequence`; see spec 0008, which replaced an
  earlier design that swapped in a bundled spy synthesizer.)
- `live` — the real synth keeps speaking; speech is captured by observation.
  Ordering/timing is best-effort rather than exact.

**The trade-off has to be stated, because it has already caused one wrong
conclusion** (spec 0021): **`silent` buys deterministic capture and costs log
fidelity; `live` buys a faithful log and costs determinism.** Intercepting speech
before the synthesizer also means the reader never reaches its own "speaking"
log line, so a silent session's `getLog` holds far fewer records than the same
work done live — measured on NVDA, twenty seconds of identical browsing at `io`
gave 64 records live against 39 silent. An agent debugging *"why did it say the
wrong thing?"* may well want `live` for exactly that reason. A bridge that
suppresses speech **should** write one marker into the reader's own log when it
starts doing so and one when it stops, so a human reading that log later is not
baffled by a stretch with no speech in it.

A bridge may still offer a human-facing channel that is audible in `silent`
mode — see the `announce` capability below. It bypasses the interception rather
than defeating it: the point of `silent` is that the *reader's* output is
captured, not that the machine is mute.

**Capabilities** announce which command groups this bridge can serve. Each value
names one group:

| Capability | Commands it covers |
|---|---|
| `speech` | `getSpeech`, `getLastSpeech`, `getNextSpeechIndex`, `waitForSpeech`, `waitForSpeechToFinish` |
| `braille` | `getBraille` |
| `gestures` | `pressGesture` |
| `typing` | `typeText` |
| `focus` | `getFocusInfo` |
| `state` | `getState` |
| `config` | `getConfig`, `setConfig` |
| `interact` | `announce`, `askUser`, `waitForUserReply` |
| `log` | `getLog`, `getLogPosition`, `waitForLog`, `setLogLevel` |
| `guidance` | `getGuidance` |

Rules:

- A consumer **must ignore an unknown capability string**, so the set can grow
  without breaking older peers. (This is the one forward-compatibility carve-out
  beyond "ignore unknown fields".)
- **A bridge must not reject an unrecognised `persona`** (§3), for the same
  reason and with the same shape. The set of personas is defined by the server
  (spec 0029) and can grow; if adding one could fail a handshake, adding one
  would mean a synchronised release across every bridge that exists. A bridge
  that does not know a persona serves whatever it would serve generally and says
  that it did not recognise it — degrade, never error. This is also why the field
  crosses the wire as a plain string: a closed enumeration would make the
  validator reject the value before any bridge logic could degrade.
  `getGuidance`'s `recognised` is where a bridge says so out loud.
- **`guidance` is the first capability that gates something other than a tool.**
  Every other one names commands an agent calls; this one exists because the
  bridge is the only party that can write down what a persona's vocabulary IS on
  its own reader (§3, spec 0029) — the server's own documents state the rule and
  cannot state the instances, since they are keystrokes on one platform and touch
  gestures on another. A bridge with nothing reader-specific to say simply does
  not announce it, and the agent falls back on the server's documents alone.
- A command whose group is **not** in the announced set may be rejected with a
  normal error response. The NVDA bridge announces `speech`, `braille`,
  `gestures`, `typing` and `announce` today; `focus`, `state` and `config` are
  defined by this contract and served by no bridge yet, so it does not announce
  them.
- `hello`, `ping`, `echo`, and `bye` are lifecycle/diagnostic commands and belong
  to no capability group; they are always available once the session permits them
  (§3).

## 5. Commands

Every command's `params` and `result` shapes are defined in
[`schema.json`](schema.json) under `commands.<name>`. A `null` `params` there
means the command takes no parameters. Summary:

- `hello` — handshake (§3).
- `ping` → `{ ok: true }` — liveness only; see §6.
- `echo` `{ payload }` → `{ payload }` — returns the payload unchanged, for any
  JSON value; a whole-stack round-trip check.
- `pressGesture` `{ gestures: [string], graceMs?, announce? }` → `{ pressed:
  [{ gesture, speechFrom, speechTo }], speech: [SpeechEntry], speechFrom,
  speechTo, state? }` — press the given reader gesture ids in order, blocking
  until each is processed, then report what was said. Gesture id
  syntax is **reader-specific** and passes through opaquely: it is the reader's
  own **user-facing command notation**, as its documentation writes it — for
  NVDA, the key-combo form from the User Guide (`"NVDA+f7"`, `"control+l"`,
  `"escape"`), not an internal identifier. The reader-specific bridge maps it to
  a keypress; an NVDA bridge tolerates a legacy `"kb:"` inputCore prefix but the
  documented form is prefixless.
  - `graceMs` (default **100**, `0` to opt out) is the **grace window** of §7.3:
    after each gesture the bridge waits up to that long for the speech it
    caused, and returns as soon as any arrives.
  - `announce` is spoken to the **human at the reader** before the first gesture
    is dispatched, on the same side channel as `announce` — audible even in a
    silent session. Empty means say nothing.
  - Each entry in `pressed` carries the half-open span `[speechFrom, speechTo)`
    the ring stood at either side of **that** key's dispatch, so a batch stays
    observable and a **silent key is visible rather than inferred** (an empty
    span). Attribution is by dispatch-time coordinate, **not causation**: speech
    caused by gesture *n* can land after gesture *n+1* went out and is then
    credited to *n+1*.
  - `state` is `getState`'s four fields sampled at the close of the last window.
    Deliberately **not** focus information: see §7.3.
- `typeText` `{ text, graceMs?, announce? }` → `{ typed, speech: [SpeechEntry],
  speechFrom, speechTo, state? }` — insert literal text at whatever
  currently holds system focus, layout-independent Unicode injection rather
  than a sequence of key commands. `text` is opaque content, routed without
  interpretation exactly as a gesture id is; it does **not** interpret control
  characters, newlines or Enter, and does not submit anything — compose that
  from `typeText` and `pressGesture`. Mutates the reader's machine the same way
  `pressGesture` does. `typed` is the length of what was **sent**, never the
  text — this is exactly how a secret is entered. `graceMs` defaults to **0**
  here: with "speak typed characters" on, typing emits one utterance per
  character and none is worth waiting for.
- `getSpeech` `{ sinceIndex }` → `{ entries: [{ text, index, logPosition,
  emittedAt }],
  fromIndex, toIndex }` — captured speech since an index (§7). **One entry per
  utterance**, not a joined string (spec 0021): a blob has nowhere to put a
  per-utterance coordinate, and the join cannot be recovered by the caller, since
  entries that render empty are omitted while `fromIndex`/`toIndex` span the whole
  range — so entry *i* is **not** at index `fromIndex + i`. Each entry therefore
  carries its own `index`, and `logPosition`, the journal position it was captured
  at (see `getLog`'s `sincePosition`), and `emittedAt` (§7.1).
- `getLastSpeech` → `{ text, index, logPosition, emittedAt }`. `emittedAt` is
  empty for the sentinel returned when nothing has been said.
- `getNextSpeechIndex` → `{ index }` — the index the next captured speech will
  occupy.
- `waitForSpeech` `{ text, afterIndex?, timeout? }` → `{ found, index, text,
  logPosition, emittedAt }`. On a miss `logPosition` is the journal's *current*
  position, so it is still a usable "from here" mark — the same convention
  `index` follows. `emittedAt` is **empty on a miss**, deliberately: nothing was
  emitted, and reporting the current instant would read as a match that happened.
- `waitForSpeechToFinish` `{ timeout? }` → `{ finished }`.
- `getBraille` `{ sinceIndex }` → `{ entries: [{ text, index, logPosition,
  emittedAt }],
  fromIndex, toIndex }` — the same entry shape as `getSpeech`, for the same
  reason. It matters more here: this is the only braille fetch, so it is the sole
  route to a braille update's coordinate.
- `getFocusInfo` → `{ name, role, states, value, appModule }` — the focus
  object. `role`/`states` strings are reader-specific and pass through opaquely.
- `getState` → `{ browseMode, speechMode, sleepMode, inputHelp }` — queryable
  state that a reader may signal by sound rather than words; diff two snapshots
  across a gesture to assert a toggle. Values are reader-specific.
- `getConfig` `{ keyPath: [string] }` → `{ value }` — read a reader config value;
  `keyPath` is an opaque path into the reader's config tree.
- `setConfig` `{ keyPath: [string], value }` → `{ value }` — write one.
- `announce` `{ text }` → `{ ok: true }` — speak `text` to the **human** at the
  reader. A bridge→human hint channel, not agent-facing data: it is audible even
  in `silent` mode (§4), which is its whole purpose, because that is the mode in
  which the person can otherwise hear nothing. The bridge acknowledges that it
  spoke, never that anyone listened. There is no reply channel in v1.
- `bye` → `{ ok: true }` — the server asks to end the session (§6).
- `getLog` `{ sincePosition?, lastSeconds?, commandId?, windows?, minLevel?,
  contains?, exclude?, fields?, maxEntries? }` → `{ text, entries, matched,
  truncated, nextPosition, fromCommandId?, toCommandId?, capturedAtLevel }` —
  return a filtered, formatted slice of the reader's diagnostic log (specs 0020,
  0021).

  There are **three mutually exclusive anchors**, resolved in this order:
  `sincePosition`, then `lastSeconds`, then `commandId`/`windows`. Supplying more
  than one is an **error** rather than a precedence puzzle.

  - `sincePosition` reads forward from a mark the caller holds — taken with
    `getLogPosition`, carried over from a previous call's `nextPosition`, or read
    off a speech or braille entry's `logPosition`. **Reading never consumes**, so
    re-issuing the same position with a different filter returns the same records
    re-filtered. This is the anchor for observing rather than acting: watching a
    human drive the reader issues no commands, so the command anchor has nothing
    to anchor on. A `sincePosition` below the ring's oldest surviving record
    reports `truncated: true`, which is how a poll loop learns it fell behind — a
    real possibility at `io`, where ten thousand records is a minute or two.
  - `lastSeconds` reads back from now, for "that just happened" when no mark was
    taken beforehand.
  - `commandId`/`windows` is the command anchor, and the default. Anchored by
    request id (defaults to the most recently marked command); `windows` counts
    back from the anchor.

  `windows` belongs to the command anchor and is **rejected** alongside either of
  the other two, for the same reason an unknown field name is: the other anchors
  already say how far back to read, so accepting `windows` there would answer a
  different question from the one asked and give the caller no way to tell.

  `nextPosition` is always returned: pass it back as `sincePosition` to continue
  the tail with no gap and no repeat. `fromCommandId`/`toCommandId` are **absent**
  for a position or time anchor, because such a read spans whatever commands fall
  in it and is attributable to none.

  Filters compose: `minLevel` drops records below a level,
  `contains` keeps only matching messages, `exclude` drops matching modules or
  messages, all case-insensitive. `fields` projects which columns to render
  (default: time, level, module, message); an unknown field name or level is
  **rejected**, never silently dropped, so a typo cannot return a slice that
  merely looks filtered.

  **A command's span runs from when it was dispatched until the NEXT command was
  dispatched** (spec 0021), so the timeline is fully partitioned and every record
  belongs to exactly one command. That is what makes `windows: 1` mean something:
  the work a command *caused* arrives after its handler returned — measured live
  on NVDA, `speech.speak` landed one millisecond past the old end mark — and under
  this model it is attributed to the command that caused it rather than falling
  into a gap. **Attribution is by most-recent-command, not by causation**: think
  for thirty seconds after a keypress and those thirty seconds land in that
  keypress's span. Spans are adjacent, so `windows` > 1 is simply one continuous
  range. Bounded by `maxEntries` (default 200); reports `matched` (before the
  cap), `truncated` (when capped or the range aged out of the ring), and
  `capturedAtLevel` (the floor in force for the span — an empty slice at
  `capturedAtLevel: "info"` with `minLevel: "debug"` means the records were never
  emitted, not that none exist). `capturedAtLevel` is **exact** for a command
  anchor, since `setLogLevel` is itself a command and opens a new span, but
  **approximate** for a position or time anchor, which may straddle one and then
  reports the level currently in force. Over several command spans it reports the
  **oldest** one's floor, so it never claims to have captured more than the
  earliest part of the range did. Every marked command has a span, including one
  that **failed** — "show me the log for the command that just errored" is the
  case this exists for. `getLog` itself does not mark, so a read can never become
  its own anchor, nor close the span it is reading.
- `getLogPosition` → `{ position, time }` — mark the journal at this instant and
  return the mark: `position` is the current append position, `time` is wall
  clock, for lining a mark up against the session transcript or a human's account
  of when something happened. Returns **no records**: paying for a slice to learn
  a single integer defeats the purpose of marking the moment you begin observing.
  It is `getNextSpeechIndex` for the log, and separate from `getLog` for the same
  reason that one is separate from `getSpeech`.
- `waitForLog` `{ timeout?, minLevel?, contains? }` → `{ found, position, text }`
  — block until a matching record is journalled, or the timeout elapses. **Pull,
  not push**: the agent asks and waits; nothing in this protocol tails or streams
  unasked. Only records journalled **after the call begins** can match, so an
  error from earlier in the session never satisfies "wait for the next error".
  Not matching is `found: false`, **not an error** — `waitForSpeech`'s manners,
  for the same reason: a wait that expires is an ordinary outcome an agent
  branches on, and it is also how "nothing went wrong in that interval" is
  asserted. `position` is one past the match, so it feeds straight back in as
  `getLog`'s `sincePosition` and reads what followed the trigger without
  repeating the trigger itself; on a miss it is the journal's current position,
  still a usable mark.
- `setLogLevel` `{ level }` → `{ level, previous }` — raise or lower the
  reader's diagnostic logging floor for the rest of the session. Forwards only:
  Python's logging decides at the *logger* whether a record exists, so a level
  that was never emitted cannot be recovered. Downwards is free. This is a real
  (if temporary) change to the reader; the level is restored at teardown on every
  exit path (spec 0020, superseding 0009's hello-only level change).
  Only `debug`, `io`, `debugwarning` and `info` may be **set** — the same four
  `hello`'s `logLevel` accepts. `warning` and `error` exist in `LogLevel` as
  `getLog` `minLevel` filters, where they are the common case; setting the
  reader's own floor to either would silence warnings in the **user's** nvda.log
  for the rest of the session, so both commands reject them.

- `getGuidance` → `{ persona, recognised, text }` — the bridge's own written
  guidance for **this session's persona** (§3, spec 0029): what the ordinary
  vocabulary is on this reader, and which of its commands fall outside it.

  **Takes no parameters.** The persona was fixed at `hello`, and this answers for
  it and for nothing else. A `persona` argument would let an agent fetch one
  stance's instructions from a session standing in another, which quietly undoes
  what the declaration is for, and it would raise a question about what happens
  when the two disagree.

  `recognised` is `false` when the bridge had no persona-specific instruction for
  the declared value — a newer server's fourth persona meeting an older bridge.
  That is a real answer and the text is still worth having, because most of what
  an agent needs here (the ordinary vocabulary, the desktop's own keys, the
  reader's reading commands) does not vary by stance. Silence would instead leave
  the agent believing it had been instructed when it had not.

  `text` is **opaque markdown**, composed by the bridge as one document: the
  server transports and frames it and never parses it. That is what lets a bridge
  author write for their own reader without negotiating a schema — and it is why
  there is no second call and no structure to reassemble. A server **should**
  state, in whatever it wraps around the text, that the stance itself is
  normative and the bridge instantiates it: a bridge may name its reader's escape
  hatches and the commands that constitute them; it may not redefine what a
  persona is for or what counts as success.

Reader-specific vocabulary — gesture ids, roles, states, config key paths, state
values — is **opaque payload**: the server routes it without interpreting it, and
only the agent (which knows the reader) and the bridge understand it.

## 6. Liveness and teardown

The bridge runs two independent watchdogs while a session is established:

- **Heartbeat** — proves the server process is alive. Any message resets it,
  including `ping`.
- **Command inactivity** — proves the agent is still working. Only a real command
  resets it; `ping` deliberately does **not**, so a keepalive cannot mask an
  abandoned session.

A session ends on any of: `bye`, the peer closing the connection (EOF), either
watchdog firing, or an out-of-order pre-handshake command (§3).

On **every** teardown path the bridge must run its restoration: in `silent` mode
that means lifting the speech interception, so the reader speaks again. A crashed
or disconnected server must never leave the reader mute — this is the contract's
single most important invariant, and a bridge should arrange its interception so
that losing the bridge *itself* lifts it. (The NVDA bridge gets this from NVDA
holding extension-point handlers weakly: if the add-on dies, the filter drops
with it.)

## 7. Index semantics

Captured speech and braille each form an append-only log with **monotonically
increasing integer indices**.

- Ranges are **half-open**: `getSpeech`/`getBraille` return
  `[fromIndex, toIndex)`, i.e. `fromIndex` inclusive, `toIndex` exclusive, so
  `toIndex` is exactly the `sinceIndex` to pass next with no overlap or gap.
- The range is not the entry count. Items that render empty are **omitted from
  `entries`** while `fromIndex`/`toIndex` still span the whole range requested, so
  `len(entries)` ≠ `toIndex - fromIndex` and entry *i* is not at index
  `fromIndex + i`. Each entry carries its own `index` for exactly that reason.
- The speech and braille rings are **unbounded within a session**: nothing ages
  out of them while the session lives, so `getSpeech { sinceIndex: 0 }` returns
  everything that was said, at any point before `bye`. The log journal is the only
  one of the three session records that is a bounded ring.

### 7.1 `emittedAt` — when, not merely in what order

Every captured entry carries `emittedAt`: wall clock at the moment the reader
**emitted** it, formatted `YYYY-MM-DD HH:MM:SS.mmm`. That is the same shape
`getLogPosition` returns and the same shape the bridge's own session transcript
writes, so a stamp can be pasted straight into a search of either, or of the
reader's own log.

It exists because `logPosition` answers *in what order* and nothing answers *how
long*. Recovering a clock from a journal position costs a `getLog` round trip per
entry, and in a silent session the journal holds no speech record to land on at
all — the coordinate points at the surrounding events, which is what it was
designed for, but there is no timestamp to borrow. Two `emittedAt` values
subtract, which is what an assertion of the form "X happened promptly after Y"
needs.

**Emitted is not heard.** A bridge captures before the synthesizer speaks — for
NVDA, at the point the sequence is queued in live mode and inside `speak()` in
silent mode. Neither is audio, so an utterance queued behind a longer one can be
seconds from audible.

**Measured, so the size of that gap is not left to imagination.** NVDA 2026.1.1,
`ibmeci`, live mode, a say-all over a document of numbered lines, cut with a
keystroke at a known instant. At the moment of the cut the bridge had captured
through **line 16**, while the listener was part-way through hearing **line 14** —
a line emitted 5.4 s earlier. The lead is steady rather than growing (both sides
run at ~1.8 s per line, so it is a fixed lookahead: NVDA keeps lines in flight and
the synthesizer's own buffer adds more), and it is worth stating as a number
because it is much larger than the word "queued" suggests: **an agent reading
captured speech is routinely holding two to three utterances, around five
seconds, that the human at the machine has not heard yet.**

Two consequences follow, and neither is a defect to be fixed here. A tool that
reports speech has *settled* is reporting about arrival, not about audio, and
cannot honestly claim otherwise. And an agent that narrates to a human and then
acts immediately is acting ahead of its own narration — the human's objection,
when it comes, is a reaction to something several seconds stale.

This makes `emittedAt` the right number for *did the
application respond promptly* (synthesizer queueing belongs to the synthesizer
and would be noise in that figure) and the wrong number for *when did a person
hear it*, which this protocol does not answer.

The field is **optional**: a bridge that does not supply it omits it, and a
consumer must treat an absent or empty value as "no instant was recorded" rather
than as an epoch. The value is empty, never `0`-as-a-date, wherever nothing was
emitted — the speech ring's sentinel entry, and a `waitForSpeech` miss.

### 7.2 Coordinates

- A **journal position** (`logPosition`, `sincePosition`, `nextPosition`) is a
  different coordinate space from an index, and the two are never
  interchangeable: an index addresses the speech or braille ring, a position
  addresses the log journal. `logPosition` exists precisely to join them.
- `getNextSpeechIndex` returns the index the next captured item will take, so a
  test can note "now", act, then read only what its action produced. Since §7.3
  it is **no longer part of the ordinary loop** — `pressGesture` and `typeText`
  take their own bookmarks — but it remains the only way to mark a moment when
  the **agent is not the one acting**: a human driving while the agent watches.
- `waitForSpeech` blocks until a matching item appears or `timeout` seconds
  elapse; `found` says which. `afterIndex` restricts the match to items at or
  after that index.
- `waitForSpeechToFinish` blocks until speech settles or `timeout` elapses. It
  is **not the step after every action** — see §7.3, which measured that in that
  role it observes nothing at all. What is left for it is a **long deliberate
  announcement** or a say-all, where the question really is "is it still going?"
- All timeouts are in **seconds** (number; defaults live in `schema.json`).

### 7.3 The grace window — what a result may claim

`pressGesture` and `typeText` wait `graceMs` after dispatching and report the
speech that arrived. The contract that makes that safe is one sentence:

> **A result says what had arrived by a stated instant, and where to resume. It
> never says that is all there is.**

So there is **no `complete` and no `finished`** on either result, and there will
not be one: an empty `speech` list means *nothing had arrived by then*, which is
a fact, not *nothing happened*, which would be a claim no bridge can support.
A caller that reads an empty list waits a little and reads again from
`speechTo`, or calls `waitForSpeech` for a specific phrase.

The window replaces a **different question**, and the difference is the whole
point. `waitForSpeechToFinish` asks *has speech stopped?* — unanswerable at the
moment it is asked, because silence before speech starts and silence after it
ends are the same observable. The grace window asks *has speech started?*, which
is answerable at a known instant with no claim beyond what was seen.

The default of 100 ms is a **heuristic, not a constant to trust**. It was chosen
against a single measurement — one machine, one synthesizer, one reader version:
speech was produced ~124 ms after a keystroke while an agent's round trip cost
~2.6 s, so the window costs ~4% of a trip already being paid. A slower machine or
a heavier document moves that, which is why `graceMs` is a parameter.

**Slow effects still cost a second call.** A window opening, a page loading, a
dialog appearing — none of those land inside the grace, by design; collapsing
them would need an "await this phrase" parameter whose failure answer would
conflate *not yet*, *worded differently* and *never*.

**`state`, and why not focus.** The snapshot is `getState`'s four mode fields and
never focus information. A browse/focus toggle is synchronous with the script
that performed it and is already complete when the window closes — and it is the
one thing a silent session cannot hear. Focus movement is asynchronous, so a
sample taken now reports the place the user **left**, confidently and wrongly, in
exactly the case a caller cares about. Speech remains the observable for "did the
effect land".

## 8. Versioning policy

- Compatibility is decided by **exact `protocolVersion` equality** at `hello`
  (§3). There is no negotiation yet.
- Two forward-compatibility rules soften that: unknown **object fields** are
  ignored (§2), and unknown **capability strings** are ignored (§4).
- `protocolVersion` 1 is pre-release: it may be amended in place until an external
  (non-Python) bridge depends on it. After that, an incompatible change bumps the
  version and ships a new `specs/wire/vN/` directory.

**Amendments made in place under that rule**, newest first:

- **2026-08-19** — `HelloResult.guidance` added (§3, spec 0022 A.5). Additive and
  optional, so it needed no version bump under either forward-compatibility rule
  above: a newer bridge sending it to an older server has the field ignored, and
  a newer server receiving nothing from an older bridge falls back to
  `getGuidance`. Both directions degrade, which is what the rule is for.
