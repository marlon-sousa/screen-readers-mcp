# 0027 — the first external run: feedback as received

Status: **a findings record, not a design spec.** Nothing here is agreed or
proposed; it is evidence. Received 2026-08-15. Numbered into `specs/` because
that is where a reader looks for a numbered project document, and because
[0014](0014-announce-and-real-world-run.md) established that run documents live
here.

**Why this file exists at all.** The board records what we decided to *do* about
this feedback, and decisions move — an entry gets absorbed into another, split,
renumbered or deferred, and each of those moves loses a little of the original
ask. Two of the five below had already been folded into a third entry within a
day of arriving, and that entry was then itself absorbed. Without this file, the
asks would survive only as a pointer to a pointer. **The demands are real and
outlive our current plan for them**, so they are written down once, plainly, and
the board points here rather than the other way round.

---

## Where it came from, and why the source matters

An external agent drove **acter**, a third-party application, through this MCP on
2026-08-15 and wrote up the friction afterwards.

It is the first session **nobody on this project was sitting at**. Every earlier
E-finding came from a live checklist run with the maintainer at the keyboard,
which means every earlier finding was shaped by someone who already knew how the
system was meant to be used. This one was not.

It produced **no bugs**. Five pieces of feedback, every one a missing affordance.

---

## 1. Speech entries have no timestamp

> *"This is my strongest ask. The single most valuable piece of evidence in the
> whole run — that the stop woke a sleeping script in 63ms — I could not get from
> the MCP. `get_speech` gives `logPosition` but no time, so I read `session-*.log`
> off disk and diffed timestamps by hand. Any assertion of the form 'X happened
> promptly after Y' needs that, and timing assertions are a large fraction of what
> accessibility testing is. A timestamp on each entry would have made it a
> one-liner."*

**Status:** board entry **11.15**, open, spec not yet written.

The design was settled in conversation on 2026-08-15: wall clock rather than
monotonic (`Clock.time()`, on `getLogPosition`'s precedent), stamped per entry in
`SpeechBuffer.append` — which already takes the instant and discards it into an
overwritten `_last_time` — and named for the moment the reader **emitted** the
utterance, never for speaking, since neither capture hook is audio.

## 2. A toggle with no setter

> *"NVDA+space is a toggle, and there's no setter. With no idempotent way to say
> 'be in browse mode', automation has to `get_state`, branch, press, then re-check
> — and if it guesses wrong it flips the wrong way and silently corrupts
> everything after. `set_browse_mode("browse"|"focus")` would remove a whole class
> of automation bug. Your own config makes this sharper: an agent that assumes
> auto-switching gets wrong answers and, as I just demonstrated, blames the app."*

**Status:** board entry **11.17**, open. Closely related to **11.11**, which comes
from a different session and the same `NVDA+space` incident, with a complementary
remedy — 11.17 gives the agent a setter, 11.11 gives it the tone it cannot hear.

The named remedy (`set_browse_mode`) was **not** adopted: spec 0005 makes the
capability the unit of reader difference, so the shape is `setState` mirroring
`getState`. The last clause of the ask is its own finding — an agent blaming the
application for a reader-mode confusion is exactly the failure spec 0023
predicts, reached independently by someone who had never read it.

## 3. No way to combine an action with its submit

> *"Every command cost me two round trips (`type_text`, then `press_gesture
> ["enter"]`) at ~5–10s each. That's not just slow — it made one scenario
> untestable: `big` has a 1.5s finish delay, so it always completed before I could
> stop it, and I had to substitute `burst` to test stopping a too-big command.
> Either a sequence primitive (`do([{type:…},{gesture:…}])`) or a submit flag on
> `type_text` would fix the throughput. The deeper version, if you ever want it,
> is act-on-trigger: 'when speech matches X, immediately press Y', evaluated
> bridge-side where the latency isn't."*

**Status:** the remedy lives in **11.12** (spec 0025, *one round trip per
intention*), which reached the same conclusion from a different session and
carries measurements this ask lacked. Board entry **11.16** recorded it first and
is now marked absorbed.

One correction worth keeping attached to the ask: **the 5–10 s is not ours.**
Entry 11.4 measured the bridge at 0.2–0.5 ms; the cost is the client model's turn
time. The fix removes model round trips, not transport.

**Two riders that 0025 does not yet cover, and which must not be lost:**

- **Act-on-trigger falls out for free** if `waitForSpeech` is one of the step
  types — the wait blocks bridge-side and the next step fires ~0.2 ms later. No
  new concept, and nothing is pushed, so 0021's pull-not-push decision stands.
- **A sequence must be able to express *settling*, not only sleeping.** A
  primitive that can only sleep mass-produces the exact failure 0023 exists to
  prevent. (Note that 0025 argues the settle step is itself unanswerable; these
  two positions need reconciling in that spec's review.)

## 4. Getting the application focused is outside the tool

> *"I had to drop to PowerShell and Win32 `SetForegroundWindow` to put Acter in
> front. Arguably correct scoping — it isn't a screen reader concern — but it's
> the first thing any agent needs, so at minimum it deserves a line in the README.
> `type_text`'s own warning about landing in the wrong window is the tell that
> this gap is known."*

**Status:** **Done** — board entry 11.14, PR #55, 2026-08-16.

The scoping judgement was upheld; the gap was that a hazard had been named
without its remedy. Review of the fix turned up something larger than the ask: a
gesture is a **discrete press and release**, so no modifier can be held across
several keys and the ordinary way of walking a window switcher is not expressible
at all. That limit belongs to spec 0018's input vocabulary and had never been
written down anywhere.

## 5. `type_text` could take `replace: true`

> *"Minor: I hit a field with stale content and did `control+a`, `delete`,
> verify."*

**Status:** subsumed by the sequence work in **11.12** — select all, delete, type
is a sequence. Recorded here so that if 0025 ships without a general sequence
primitive, this ask is still visible and still unmet.

---

## Traceability

| # | Ask | Handled by | Status |
|---|---|---|---|
| 1 | timestamps on speech entries | 11.15 | open, design settled |
| 2 | an idempotent mode setter | 11.17 (+ 11.11) | open |
| 3 | action + submit in one call | 11.12 / spec 0025 | open, spec drafted |
| 3b | act-on-trigger | 11.12, **rider not yet in 0025** | at risk |
| 4 | getting the app in front | 11.14 | **Done** (PR #55) |
| 5 | `type_text replace: true` | 11.12, **rider not yet in 0025** | at risk |

**The two rows marked *at risk* are the reason this file exists.** They are not
in any spec text today; they survive only here and in 11.16's absorbed note. If
0025 is agreed without them, they must either be argued down explicitly or spawn
their own entry — not simply fall off.
