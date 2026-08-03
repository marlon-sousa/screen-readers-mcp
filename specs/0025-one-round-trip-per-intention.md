# 0025 — one round trip per intention

Status: **drafted 2026-08-03, not agreed.** Board entry **11.12**. Implements the
two routes named in [11.9](../ROADMAP.md), whose measurements are the whole
argument for this spec.

---

## Part 1 — the only number that matters

Measured 2026-08-03, from the bridge transcript and a bracketed control:

| | |
|---|---|
| NVDA finishes producing a keystroke's speech | **~124 ms** (`GESTURE windows+d` 09:04:24.078 → last `SPEECH` 09:04:24.202) |
| one agent tool round trip | **~2.64 s** measured, **5–12 s** observed in a later live run |

So **NVDA is not the slow part, and it is not close.** In the run that produced
these numbers, ~30 calls spent roughly 78 s almost entirely on transport.

[0023](0023-drive-it-like-a-user.md) prescribes the loop the agent should run:
**act → settle → listen**. That is three round trips per intention, ~7.9 s, to
carry ~124 ms of reader work. And [11.9](../ROADMAP.md) established that one of
those three is pure waste:

> a settle timed against a **deliberately quiet** buffer took 8.293 s, and one
> immediately after real speech took 8.297 s — identical, because both returned
> instantly.

`waitForSpeechToFinish` returns `finished: true` off a stale `_last_time` having
observed nothing, because by the time the call arrives the 1 s quiescence window
has *always already expired*. The settle was never being paid; it was also never
doing anything.

### Why the settle was the wrong primitive, not just a mistuned one

`waitForSpeechToFinish` asks **"has speech stopped?"** That question is
unanswerable at the moment it is asked, and the reason is structural rather than
a matter of constants: silence before speech starts and silence after speech
ends are the same observable. Shortening the window makes the wrong answer
arrive sooner. Lengthening it makes the agent wait for a thing that already
happened.

The maintainer's proposal reframes it, and the reframing is the substance of
this spec:

> we can wait for say 100 ms after a gesture is pressed and return what is there
> in terms of speech. If nothing returns, you know you must wait a little and
> query state again, or even query speech again to see whether something else
> came.

That asks **"has speech started?"** — which *is* answerable, at a known instant,
with no claim beyond what was observed. And 100 ms is chosen against the 124 ms
measurement: it is where the common case already is. Against a 2.6 s round trip
it costs **~4 %**, versus the settle's nominal 38 % for an answer that was never
computed.

The two questions are not variations on each other:

| | `waitForSpeechToFinish` | the grace window |
|---|---|---|
| asks | has speech **stopped**? | has speech **started**? |
| empty answer means | *nothing* — the state is unobservable | "nothing had arrived by *T*" — a fact |
| cost | one round trip, ~2.6 s | ~100 ms inside a trip already paid |
| claims completeness | yes, falsely | **never** |

---

## Part 2 — what a result may claim

The grace window only helps if its empty case is honest. So, as a contract rule:

**A result says what had arrived by a stated instant, and where to resume. It
never says that is all there is.**

There is no `complete: true`. An agent that reads an empty speech list learns
*"nothing yet, as of 100 ms after dispatch"*, which is exactly what the
maintainer described doing about it: wait a little and ask again, or orient with
the reader's own report-focus command, or re-query speech. That is
[0023](0023-drive-it-like-a-user.md)'s loop — unchanged, but now entered **only
in the rare case** instead of on every single step.

This is also why this spec adds no `await` / expectation parameter; see *What is
deliberately not built*.

```mermaid
sequenceDiagram
    accTitle: How a grace window collapses act, settle and listen into a single round trip while keeping the empty case honest
    accDescr: Today the agent sends press gesture, gets an ok result, sends wait for speech to finish, gets a result that observed nothing, then sends get speech and finally receives the words. That is three round trips of about two point six seconds each to carry about one hundred and twenty four milliseconds of reader work. With a grace window the agent sends press gesture once. The bridge dispatches the gesture, waits one hundred milliseconds, and returns the speech that arrived in that window together with bookmarks and a state snapshot. If the window came back empty the agent knows only that nothing had arrived by that instant, not that nothing happened, so it waits and asks again. Slow effects such as a browser window opening still take a second call, which is the same cost as today rather than a new one.
    participant Agent
    participant Bridge
    participant NVDA
    Agent->>Bridge: pressGesture ["windows+d"]
    Bridge->>NVDA: dispatch
    NVDA-->>Bridge: speech arrives (~124 ms)
    Note over Bridge: grace window: 100 ms
    Bridge-->>Agent: { pressed, speech[], speechFrom/To, state }
    Note over Agent: one trip, not three
    Agent->>Bridge: pressGesture ["enter"] (opens Chrome)
    Bridge->>NVDA: dispatch
    Note over Bridge: grace expires, nothing yet
    Bridge-->>Agent: { speech: [], speechTo: 7 }
    Note over Agent: "nothing YET" — not "nothing"
    Agent->>Bridge: waitForSpeech "Chrome", after 7
    Bridge-->>Agent: found, at index 8
```

---

## Part 3 — what ships

### 1. A grace window on every mutating call

`pressGesture` and `typeText` take an optional `graceMs` (default **100**, `0`
to opt out) and return the speech that arrived during it.

```jsonc
{
  "pressed": [
    { "gesture": "control+home", "speechFrom": 59, "speechTo": 60 },
    { "gesture": "h",            "speechFrom": 60, "speechTo": 60 },  // silent
    { "gesture": "h",            "speechFrom": 60, "speechTo": 60 }   // silent
  ],
  "speech": [ { "index": 59, "text": "Skip to content link mesma página", "logPosition": 3329 } ],
  "speechFrom": 59,
  "speechTo": 60,
  "state": { "browseMode": "focus", "speechMode": "talk", "sleepMode": false, "inputHelp": false }
}
```

Read that against Part 1 of [0024](0024-a-session-the-agent-can-hear.md): the
five silent `h` presses and `browseMode: "focus"` are both **on the face of the
result**, in the call that made them. The live failure of 2026-08-03 could not
have survived its own first result.

### 2. Per-gesture bookmarks, so batching stops hiding things

A batch today returns `{"pressed": ["h","h","h","h","h"]}` and one blended speech
read; there is no way to tell which key produced what, or that four produced
nothing. The fix is **not** to un-batch — that costs a round trip per key — but
to carry a `speechFrom`/`speechTo` pair per gesture.

This is the same device [0021](0021-observing-the-log.md) already uses:
`SpeechEntry.logPosition` relates two timelines by *position at the moment of
capture* rather than by copying data across. Here the coordinate relates a
gesture to the speech ring. Two integers per gesture, no duplicated text.

The arithmetic, at today's rates:

| | today | with this |
|---|---|---|
| 5 gestures, individually observable | 5 trips ≈ 13 s | 1 trip + 500 ms grace ≈ **3.1 s** |
| 5 gestures, batched | 1 trip ≈ 2.6 s, **not observable** | as above, **and** observable |

Batching and observing currently trade off against each other. This is the
change that makes them compose, and it is the one worth the most.

### 3. A state snapshot on the result — for silent effects only

This spec must answer [0023](0023-drive-it-like-a-user.md) directly, because
0023 lists this under *What is deliberately not built*:

> **Returning focus in the gesture/type result.** Wrong by construction: the
> focus at handler-return time is *pre*-effect focus. It would report the
> document you were in, not the dialog that is about to open, and it would be
> reliably, confidently wrong in exactly the case the agent cares about.

**That objection stands, and this spec does not overturn it.** The snapshot here
is `getState`'s four fields — `browseMode`, `speechMode`, `sleepMode`,
`inputHelp` — and it is *not* `getFocusInfo`. The distinction is the whole
justification:

- **Focus movement is slow, asynchronous, and the thing 0023 is about.** A
  sample at window close is still probably pre-effect. Not returned. Speech
  remains the observable for "did the effect land".
- **A browse/focus toggle is synchronous with the script that performs it** and
  is *already complete* when the grace window closes. It is also the one thing
  the agent cannot hear, per 0024. It is returned.

So the field answers **0024's question** — *did something happen that this
session cannot hear?* — not 0023's. And it is sampled at window close, an
instant the caller knows, rather than at dispatch.

If a session runs with 0024's normalisation, the mode change *also* arrives as
words in the same result, and the two agree. That redundancy is deliberate:
0024 covers the sessions where the agent is listening, this covers the ones
where normalisation was declined.

### 4. `announce` riding along

An `announce` string on `pressGesture`/`typeText`, spoken before dispatch.

The justification is [11.10](../ROADMAP.md) and the live run that produced it.
Narrating each step to a human who is mute in a silent session is what keeps
them safe — and doing it properly **roughly doubled the call count**, which made
the session slower, which is what made narration feel expensive enough to skip.
The thing that protects the human must not be the thing that costs the most.
Riding along makes it free.

### 5. Stop calling the settle

Zero code, available on the current build, and already validated: every read in
the afternoon run of 2026-08-03 skipped `waitForSpeechToFinish` and the speech
was there each time. `waitForSpeechToFinish`'s description should say what it is
now for — long deliberate announcements and say-all — and stop presenting itself
as the step after every action, which is what 0023 promoted it to on the
strength of an assumption that has since been measured false.

That is a **change to 0023's published loop**, and it should be made in 0023's
own guidance resource rather than silently contradicted here.

---

## Class/file layout

Per AGENTS.md, "a spec MUST include the class/file layout".

| File | Role | Collaborators |
|---|---|---|
| `bridges/.../domain/entities/speech_buffer.py` | entity (existing) | Gains a bounded `collect_since(index, grace)` that returns entries arrived by a deadline. Uses the injected `Clock`; adds no new dependency. `SPEECH_FINISHED_SECONDS` and `wait_to_finish` stay for the narrowed use. |
| `bridges/.../domain/controllers/commands/press_gesture.py` | controller (existing) | Reads `next_index` before each gesture, dispatches, then collects across the grace; assembles per-gesture bookmarks; samples the state inspector at window close; speaks `announce` first. |
| `bridges/.../domain/controllers/commands/type_text.py` | controller (existing) | Same, with a single span rather than per-gesture. |
| `bridges/.../protocol.py` | wire (existing) | `PressGestureParams` gains `graceMs`, `announce`; new `GesturePress` (gesture + bookmarks); `GestureResult` gains `pressed: list[GesturePress]`, `speech`, `speechFrom`, `speechTo`, `state`. `TypeParams`/`TypeResult` likewise. |
| `server/domain/controllers/tools/press_gesture.go` | controller (existing) | Params and result pass-through; description rewritten to state the grace, and that an empty list means *not yet*. |
| `server/domain/controllers/tools/type_text.go` | controller (existing) | As above. |
| `server/domain/controllers/tools/wait_for_speech_to_finish.go` | controller (existing) | `Description()` only — narrowed, per Part 3.5. |
| `server/adapters/mcp/guidance_resource.go` | adapter (existing) | 0023's loop updated: the settle is no longer the universal second step. |
| `specs/wire/v1/protocol.md` | contract (existing) | `pressGesture`/`typeText` shapes changed in place. `PROTOCOL_VERSION` 1 is pre-release and both halves ship together (AGENTS.md §), so this is a rebuild, not a migration. |
| `bridges/nvda/tests/unit/.../test_speech_buffer.py` (existing) | unit | `collect_since` returns early when entries arrive, waits out the grace when they do not, and returns an empty list rather than blocking on silence. |
| `bridges/nvda/tests/unit/.../test_press_gesture.py` (existing) | unit | Per-gesture bookmarks; a silent gesture yields an empty span rather than being omitted; `announce` precedes dispatch; state sampled once, at the end. |
| `server/tests/integration/mcp_press_gesture_test.go` (existing) | integration | The collapsed shape reaches the agent, and an empty speech list is representable and distinguishable from an absent field. |

No new port, no new entity, no new adapter: every collaborator already exists
and this is a change of *shape*, which is the reason it is affordable.

---

## What is deliberately not built

**An `await` / expectation parameter** (`pressGesture { until: "Chrome" }`).
Tempting, because it would collapse the slow case — a browser window opening —
from two trips to one. Rejected because its failure mode is the exact collapse
this repo keeps curing: `satisfied: false` would mean *the effect has not
happened yet*, or *it happened and was worded differently*, or *it is never going
to happen*. One observable, three situations — the objection that sank
`waitForFocus` in 0023, and it does not become sound just because the matcher is
a string instead of a role.

The maintainer's framing is also simply sufficient: *"you know you must wait a
little and query again."* The slow case then costs `pressGesture` +
`waitForSpeech` — **two trips, which is what it costs today**. So this spec makes
the common case 3× faster and leaves the rare case unchanged, rather than making
the rare case faster at the price of an ambiguous result on every call.

**`complete` / `finished` on the result.** Part 2. There is no honest way to
compute it.

**Returning focus information.** 0023, quoted in Part 3.3, and still right.

**Returning braille alongside speech.** Consistent, and probably eventually
correct, but braille has no measured equivalent of the 124 ms figure and this
spec's whole warrant is measurement. Deferred rather than guessed.

## Honest limits

- **Attribution is by dispatch-time coordinate, not causation.** A gesture's
  span says "the ring was here when this key was dispatched" — speech caused by
  gesture *n* can land after gesture *n+1* went out, and will be attributed to
  *n+1*. For a batch this is close enough to be useful and is not exact. The
  reliable reading is the *aggregate* window plus "this key's span was empty",
  which is what caught nothing on 2026-08-03.
- **100 ms is a heuristic, and the 124 ms measurement is a single sample** on one
  machine, one synth, one NVDA version, driving the Windows desktop. A slower
  machine or a heavier page moves it. The default is a starting point that the
  parameter exists to override, not a constant anyone should trust the way
  `SPEECH_FINISHED_SECONDS` was trusted.
- **The grace is real time, and it is per gesture in a batch.** A 20-gesture
  batch spends 2 s in grace. Cheap against 20 round trips; not free.
- **This does not fix slow effects.** Chrome opening, a page loading, a dialog
  appearing — all still cost a second call. By design (above).
- **The measured baseline may not be the real bottleneck.** 2.6 s was measured;
  5–12 s was observed hours later on the same machine. That gap is unexplained,
  and if it lives in the agent's own loop or the MCP layer then a 3× reduction in
  call *count* still leaves 4 s per step. **This spec's benefit is proportional
  to a number nobody has bracketed yet.**

## Open questions

- **Should the 5–12 s gap be measured before this is built?** It does not change
  the design — fewer round trips is right either way — but it changes how much
  this is worth, and this repo has just spent a morning learning what happens
  when a remedy is implemented before its premise is measured.
- **Is `graceMs` per call, per session, or both?** Per call is flexible and is
  one more knob on the most-used tool in the surface. A session default set at
  `hello` with a per-call override is more machinery than may be warranted.
- **Should `typeText` grace at all?** Typing echoes per character when the user
  has that on, so a grace after a 19-character URL may return 19 entries of
  noise. Possibly `graceMs` should default to 0 for `typeText` and 100 for
  `pressGesture`.
- **Does the state snapshot belong on `typeText` too?** Typing rarely toggles
  anything. Symmetry is worth something; so is not paying for a snapshot nobody
  reads.
- **What happens to `getNextSpeechIndex`?** Its main customer is bookmarking
  before an action, which the result now does by itself. It should probably stay
  for the observe-only case, but it stops being part of the normal loop.

## Not in scope

Making the *capture* complete ([0024](0024-a-session-the-agent-can-hear.md)) and
reading a whole document
([0026](0026-where-am-i-and-what-is-on-the-page.md)). This spec changes the cost
of a step; it does not change what a step can see, nor add a way to read more
than one at a time.
