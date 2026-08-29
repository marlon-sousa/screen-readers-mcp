# 0032 — a bound on the silence

Status: **agreed 2026-08-19.** Board entry **11.10**. Implementation follows on
the same branch, per AGENTS.md.

Two things were deliberately left for the implementing session to settle, both
requiring an ear rather than an argument: the **tone pitch** for the warning
(distinct from announce's 660 Hz and askUser's 440 Hz, unchosen here) and
whether **45/90** are the right numbers once heard from the chair.

**Both were settled by the maintainer on 2026-08-19.** The pitch is **880 Hz** —
an octave above askUser's 440 and a fourth above announce's 660, so it is the
highest of the three and reads as *attention* rather than as a hint or a
question. The thresholds stay at **45/90**: they are configurable per machine, so
a number that turns out to feel wrong from the chair is an edit rather than a
rebuild, and Part 10's first check is the run that tells him.

Part 11 lists the layout amendments made while building it, per AGENTS.md.

The gap is not a missing feature. It is a **missing measurement**: the bridge has
two watchdogs and neither of them measures the thing that hurts.

---

## Part 1 — what neither watchdog measures

A silent session suppresses NVDA's speech at the `speak()` filter (spec 0008).
For as long as it holds, the person sitting at the reader **cannot hear their own
computer**. That is the whole point of the mode, and it is why the panic gesture
exists.

On 2026-08-03 an agent held a silent session open while doing several minutes of
work that never touched the reader. The human sat mute and hit the panic gesture.
Then it happened again. The failsafe worked exactly as designed both times — and
that is the good news, because it means the last line held. The gap is that
**nothing before it did**.

The session has two watchdogs
([`SessionConfig`](../bridges/nvda/addon/globalPlugins/nvdaMcpBridge/domain/controllers/session.py)):

| watchdog | window | reset by | the question it asks |
|---|---|---|---|
| `heartbeat_timeout` | 30 s | any message, including `ping` | is the harness PROCESS alive? |
| `inactivity_timeout` | 120 s | a real command, never `ping` | is the AGENT still testing? |

Both fire on **absence**. Neither fired on 2026-08-03, and neither was wrong to
stay quiet: the agent was there, and it was testing — it was calling every few
seconds. The watchdogs answered their questions correctly. Their questions were
not the human's question, which is:

> **How long have I been unable to hear my machine?**

Those two readings come apart precisely when an agent is **busy but slow**, and
after [0025](0025-one-round-trip-per-intention.md) we know busy-but-slow is the
normal case rather than an edge one: a model turn is 5–10 s while the bridge
answers in 0.2–0.5 ms. Every watchdog we have is calibrated against agent
liveness, and agent liveness is uncorrelated with human audibility.

**Why "be more disciplined" is not the remedy.** The mitigation on the books
today is an agent-side rule — never hold a silent session across work that does
not drive the reader. It costs nothing and it is worth keeping. But it is
discipline, it has been broken twice by an agent that had been told, and **the
person it fails is blind and mute at the time**. A rule whose violation is
invisible to the person harmed until they reach for the panic key is not a
bound.

**Why 11.9 and 11.12 do not close it.** Making each round trip cheaper shortens
every exposure. It does not bound one. An agent that stops calling for four
minutes is silent for four minutes at any round-trip cost.

## Part 2 — a clock on the human, not on the agent

This spec adds a **third watchdog whose question is the human's**. It measures
one quantity:

> **Time since the human last heard their own machine.**

**What resets it — Decided.** Only sound the human actually hears. During
suppression there are exactly three such sounds, and all three already exist:

- the **session start cue** — two ascending tones and the spoken persona
  ([`NvdaSessionSignals`](../bridges/nvda/addon/globalPlugins/nvdaMcpBridge/adapters/nvda_session_signals.py)),
- **`announce`** — the agent's deliberate narration to the human,
- **`askUser`** — a question, which also suspends suppression for its whole
  window.

They share a mechanism: all three reach the synth through
[`cue_and_speak`](../bridges/nvda/addon/globalPlugins/nvdaMcpBridge/adapters/nvda_cue.py),
which drives `getSynth().speak()` directly and therefore bypasses the very filter
that is muting everything else. **That is not a coincidence — it is the
definition.** The set of things that reset this clock is exactly the set of
things that get past the suppression, which is exactly the set of things the
human hears.

**What does NOT reset it.** `pressGesture`, `typeText`, `getSpeech`, `getLog`,
`getState`, `waitForSpeech`, `ping` — every one of them, no matter how many, no
matter how fast. An agent that has pressed four hundred keys in ninety seconds
has told the human **nothing**, and the clock is right to say so.

**Why this is the load-bearing choice.** It converts the standing agent-side
discipline into a property of the mechanism. An agent that narrates its work — as
the guidance already tells it to — never sees the cap. An agent that goes quiet
gets overridden. The good behaviour stops depending on the agent remembering it,
which is the entire reason this entry exists.

**Two thresholds — Decided.**

- **Warn at 45 s.** The reader speaks a warning to the human, through the real
  synth, over a distinguishing tone pair. Early enough to land before the human
  starts wondering whether the machine has died; long enough that a normally
  narrated run never hears it.
- **Lift at 90 s.** Suppression ends. See Part 3.

Both are defaults, changeable by the human (Part 4). They are **not** on the
wire and no command can set them: an agent that could raise its own ceiling does
not have one.

**While an `askUser` prompt is outstanding the clock does not run.** The prompt
suspends suppression for its whole window
([`SessionContext.suspend_speech`](../bridges/nvda/addon/globalPlugins/nvdaMcpBridge/domain/controllers/commands/session_context.py)),
so the human is hearing everything. Counting silence during a window with no
silence in it would fire the cap at the one moment it is provably not needed.

## Part 3 — what "lift" means: capture without suppression

**Decided: the session lives, capture continues, only the muting stops.**

The obvious implementation is `suspend()`, which already exists for the `askUser`
window. **It is the wrong one here**, and the reason is worth stating because it
is the whole shape of the remedy. `suspend()` *unregisters the filter*
([`NvdaSilentSpeechSource.suspend`](../bridges/nvda/addon/globalPlugins/nvdaMcpBridge/adapters/nvda_silent_speech_source.py)),
and that filter is where capture happens. Suspending would give the human their
sound back **by taking the agent's evidence away** — trading one party's blindness
for the other's. Nothing about the human's problem requires that trade.

So the lift introduces a third state of the speech source:

| state | filter registered | words reach the synth | words reach the buffer |
|---|---|---|---|
| suppressing (today's silent mode) | yes | no | **yes** |
| suspended (today's `askUser` window) | no | yes | no |
| **passing through (new)** | **yes** | **yes** | **yes** |

In the new state `_capture_and_suppress` appends to the buffer as always and then
returns the sequence **unchanged** instead of `[]`. Two consequences fall out and
both must be honoured:

- **`_advance_callbacks` must not run while passing through.** It exists to hand
  NVDA's `CallbackCommand`s onto the event queue because an emptied sequence
  would otherwise eat them (the say-all stall of 11.13). A sequence that is
  returned intact reaches `speech.speak()` with its callbacks in place and NVDA
  clocks them itself; running them a second time would double-advance say-all.
- **`resume()` must not re-suppress a lifted session.** The `askUser` window ends
  in `resume()`, which today re-registers the filter and therefore re-mutes. If a
  lift happened before or during a prompt, `resume()` must restore *passing
  through*, not suppression. Getting this wrong silently re-mutes a human the cap
  just rescued — the exact harm, reintroduced by the recovery path.

**The agent loses nothing.** `getSpeech` returns the same entries with the same
indices and the same timestamps. What changes is only that the words also reach
the speakers. That asymmetry is why this design is cheap: the fix costs the agent
its silence, not its evidence.

**Re-suppression is allowed, and restarts the clock — Decided.** A session may go
quiet again: it calls nothing new, it simply narrates (`announce` resets the
clock) and the ordinary flow resumes. Each re-suppression is audibly marked and
starts a fresh 45/90 window from zero. So exposure stays bounded no matter how
many times a session re-arms — an agent cannot accumulate unbounded silence out
of bounded pieces, because every piece is bounded and every boundary is heard.

**Teardown is not this mechanism's job.** The panic gesture
(`NVDA+control+shift+b`) remains the human's instant, unconditional exit and is
unchanged. The distinction is deliberate: the cap's failure mode is *"the human
cannot hear"*, whose proportionate remedy is giving the sound back; the panic
gesture's is *"I want this to stop"*, whose remedy is stopping it. Killing a
session because an agent was slow would cost a run to fix a fault that needed a
speaker.

## Part 4 — the machine decides whether anyone is there

An unattended run — accessibility validation on a CI box at 3am, nobody in the
room — has no human to protect. There the cap is not a safeguard; it is damage,
because it un-mutes a session whose whole purpose was to run silently and
unattended.

**Decided: whether the cap runs is a property of the MACHINE, set on the reader's
side, and it is not on the wire.**

A single setting, `unattended`, **defaulting to false**, in `config.ini` beside
`connectionMode` and `autoStart`, with a checkbox in the bridge dialog. When
true, no session on that machine is capped. When false, every session is, whatever
it declares.

**Why not the persona.** The natural-looking alternative is a persona — a
*copilot* implies a pilot is present — and semantically that is exactly right.
It is the wrong **authority**, for two reasons.

*The agent declares the persona.* Making the persona decide hands the session its
own ceiling, which is the same lever Part 2 deliberately kept off the wire, one
level up. A server with a bad default, or an agent reasoning "this is a long
batch, better use the unattended one", leaves a human mute with no bound — and
does it **silently**, because the symptom of a missing cap is that nothing
happens.

*The two facts are about different subjects.* `user` / `validator` / `expert`
([`Persona`](../server/domain/entities/persona.go)) are stances toward the
interface: how the session drives and what it may take apart. "Is a human in this
room" is a property of the deployment — a CI runner is empty at 3am and empty at
3pm, whatever connects to it. Folding an environment fact into a stance enum
gives every future persona a second axis it has no opinion about.

**Why the default is attended.** The costs are not symmetric. Capping an
unattended machine speaks a warning to an empty room and un-mutes a session
nobody is listening to — recoverable, cheap, visible in the transcript. Failing
to cap an attended one leaves a blind person unable to hear their computer with
nothing to stop it. A machine nobody has configured is a machine we cannot assume
is empty.

**The cap only exists in `silent` mode.** In `live` mode nothing is suppressed,
so there is no silence to bound and the clock never starts.

## Part 5 — what the agent is told

The environment travels **outward**, in the handshake: `HelloResult` gains an
optional `silenceCap`, stating whether a cap is in force on this machine and with
what thresholds.

This is information, never a control — the agent reads it and cannot write it.
It earns its place because it changes what a well-behaved agent does. On a capped
machine, narrate before any stretch of work that does not drive the reader; on an
uncapped one, do not spend round trips on narration nobody will hear. Today an
agent cannot distinguish those situations at all, so it must either narrate
uselessly forever or guess.

It rides in the handshake for the reason [0022](0022-tool-discovery-an-agent-can-rely-on.md)
A.5 put the guidance document there: a fact an agent must fetch is a fact it does
not have. The reply was already being sent.

**A lift is visible in three places**, all pull-based — nothing is pushed, so
[0021](0021-observing-the-log.md)'s decision stands untouched:

- the human **hears** it (the point),
- the transcript records it, and the log journal carries it, so `getLog` shows it
  in place among everything else that happened,
- `status` reports the session's current suppression state, so an agent that
  wants to know can ask.

**What the agent is NOT promised:** a lift does not arrive as an error, an
exception, or a field on the next unrelated result. An agent that never looks
carries on working correctly and simply does not know the room got loud. That is
an acceptable outcome — the mechanism exists for the human, and the human is
served whether or not the agent notices.

## Part 6 — bridge file/class layout

Per AGENTS.md, every file with its role and collaborators.

### New

**`domain/entities/silence_cap.py`**

- `SilenceCapPolicy` — *entity, frozen dataclass*. `enabled: bool`,
  `warn_after: float`, `lift_after: float`. Built by `plugin.py` from
  `BridgeConfig`; carried on `SessionConfig`. Validates the ordering
  (`0 < warn_after < lift_after`) so a nonsensical config cannot reach the loop.
- `SilenceCapAction` — *entity, enum*: `NONE` / `WARN` / `LIFT`.
- `SilenceCap` — *entity*. Pure bookkeeping, no IO, no NVDA, no clock of its own —
  every method takes `now` as a monotonic float, so the whole thing is testable
  with plain numbers. Holds the policy, the last-audible mark, and whether this
  silence window has already warned or lifted.
  - `heard(now)` — an audible event happened; reset the window.
  - `check(now) -> SilenceCapAction` — what the loop should do now. Returns each
    of `WARN` and `LIFT` **at most once per window**, so a loop that polls every
    few hundred milliseconds does not repeat itself.
  - `paused(now)` / `resumed(now)` — the `askUser` window, where the clock must
    not run.
  - `resuppressed(now)` — a lifted session went quiet again; a fresh window.
  - Deliberately knows nothing about speech sources, announcers or NVDA. It
    answers "given these instants, what should happen"; the Session does it.

### Changed

**`domain/ports/speech_source.py`** — *port*. Two new abstract methods:
`stop_suppressing()` and `resume_suppressing()`. Both idempotent, both no-ops in
live mode (nothing was ever suppressed). Their docstrings carry Part 3's
interaction rule, because the `resume()` trap is invisible at the call site.

**`adapters/nvda_silent_speech_source.py`** — *adapter*. Gains
`self._suppressing: bool`. `_capture_and_suppress` returns `[]` when suppressing
and the sequence unchanged when not; `_advance_callbacks` runs **only** when
suppressing. `resume()` re-registers the filter but honours `_suppressing`, so it
cannot re-mute a lifted session. Writes its own log markers on each transition,
paired the way `SUPPRESSED_MARKER`/`RESTORED_MARKER` already are — a human reading
`nvda.log` afterwards must never find a suppression that never ended.

**`adapters/nvda_live_speech_source.py`** — *adapter*. Both new methods, no-op.

**`domain/ports/bridge_config.py`** + **`adapters/ini_bridge_config.py`** —
*port + adapter*. `get_unattended()` / `set_unattended()`, plus getters for the
two thresholds; three new `config.ini` keys under the existing section. Defaults
when absent or corrupt: `unattended=false`, `45`, `90` — the safe direction, and
the same failure posture the adapter already takes on a corrupt file.

**`views/bridge_dialog.py`** — *view*. A checkbox, "This machine is unattended (no
speech time limit)", beside the existing auto-start checkbox, and two labelled
spin controls for the thresholds, disabled while the checkbox is ticked. Follows
the `guiHelper` pattern already in `_build_ui`; label text is translatable.

**`domain/controllers/session.py`** — *controller*. Owns the `SilenceCap`. A new
`_check_silence()` sits beside `_check_deadline()` in the loop and acts on the
returned `SilenceCapAction`: `WARN` speaks through the announcer, `LIFT` calls the
context's `stop_suppressing()` and notes both to the transcript. Created only for
a `silent` session on a capped machine; otherwise `None` and the loop skips it.

- **The loop must reach `_check_silence` even when nothing arrives.** It already
  does: `read_message` returns `Timeout` and the loop calls `_check_deadline`
  on that path, which is what makes the existing watchdogs fire against a silent
  peer. The new check goes in the same places, for the same reason.

**`domain/controllers/commands/session_context.py`** — *parameter object*.
`note_audible()` (the announce/askUser reset, routed to the Session's cap) and
`stop_suppressing()` / `resume_suppressing()` beside the existing
`suspend_speech` / `resume_speech`.

**`domain/controllers/commands/announce.py`**, **`ask_user.py`** — *command
controllers*. Each calls `ctx.note_audible()` after the sound is emitted, not
before: the clock resets when the human was actually told, not when the bridge
decided to tell them.

**`adapters/nvda_announcer.py`** / **`adapters/nvda_cue.py`** — *adapters*. The
warning and the lift notice use `cue_and_speak` at a **third pitch**, distinct
from announce (660 Hz) and askUser (440 Hz), so the human can tell this apart from
an agent's narration before any word arrives — the same reasoning that gave those
two different pitches in the first place.

**`wiring.py`** / **`plugin.py`** — *composition*. `plugin.py` reads the three
settings from `BridgeConfig` and builds the `SilenceCapPolicy`;
`build_session` puts it on `SessionConfig`.

**`domain/controllers/commands/hello.py`** — *controller*. Reports the policy in
`HelloResult.silenceCap`.

### Tests

- `tests/unit/domain/entities/test_silence_cap.py` — the entity against plain
  numbers: warn-once, lift-once, reset, pause/resume, re-suppression, and a
  policy that is disabled.
- `tests/unit/domain/controllers/test_session.py` — a fake clock and a fake
  announcer prove the loop warns, lifts, and does neither when the machine is
  unattended, when the mode is live, or when the agent keeps announcing.
- `tests/unit/adapters/test_nvda_silent_speech_source.py` — the three states,
  and the two traps: callbacks not double-run while passing through, `resume()`
  after a lift not re-muting.
- `tests/unit/adapters/test_ini_bridge_config.py` — the new keys, their defaults,
  and a corrupt file falling to the safe side.

## Part 7 — the wire

`shared/screenreader_wire/protocol.py`:

```python
@dataclass
class SilenceCapInfo:
    """Whether this reader bounds how long a silent session may keep the human mute."""

    enabled: bool
    warnAfterSeconds: float
    liftAfterSeconds: float
```

and `HelloResult.silenceCap: SilenceCapInfo | None = None`. Optional and
defaulted, so an older bridge is not a protocol error — `None` means "this bridge
does not say", which a server reports as unknown rather than as either answer.

`specs/wire/v1/schema.json` regenerates (the CI drift gate covers it), and
`specs/wire/v1/protocol.md` gains a section stating the semantics, the reset rule,
and that the thresholds are readable but not settable over the wire.

## Part 8 — server layout

Small, and read-only throughout.

- **`server/domain/entities/silence_cap.go`** — *entity*. The policy as received,
  plus the sentence rendered for an agent.
- **`server/adapters/bridge/handshake.go`** — *adapter*. Carries the new field off
  the handshake onto the session record.
- **`server/domain/controllers/tools/connect_reader.go`** — *controller*. States
  the cap in its result, next to the persona's stance: it is the moment the agent
  learns what kind of machine it is on.
- **`server/domain/controllers/tools/status.go`** — *controller*. Reports whether
  suppression is currently in force, so a lift is discoverable by asking.
- **`server/domain/controllers/reader_guidance.go`** — *controller*. One paragraph
  in the guidance: on a capped machine, narrate before going quiet.

## Part 9 — honest limits

- **It bounds silence; it does not shorten work.** A slow agent stays slow. What
  changes is that the human hears their machine every 90 seconds regardless.
- **The warning is speech, and speech can be missed** — a human wearing
  headphones on the other side of the room hears neither. The lift is the
  guarantee; the warning is a courtesy that gives the agent 45 seconds to fix it
  first.
- **`announce` proves emission, not audition.** protocol.md §7.1 measured
  emission running two to three utterances (~5 s) ahead of audio, so an
  `announce` that resets the clock has been *made*, not necessarily *heard*. At
  these thresholds the discrepancy is a rounding error; it would not be at 5 s
  ones, and anyone tempted to shorten them should read this line first. Board
  entry **11.24(b)** is the entry that would make an acknowledgement honest about
  this.
- **An unattended machine is unattended because someone said so.** If a human sits
  down at a box configured `unattended`, there is no cap and nothing detects
  them. The setting is a claim about the room, and no software here can check it.
- **This is not the panic gesture and does not replace it.** It bounds a silence
  the human did not choose. A human who wants the session gone still reaches for
  `NVDA+control+shift+b`.

## Part 10 — what live testing must confirm

The checklist lands in the implementing PR's body (AGENTS.md), one box per check.
The claims that cannot be proven headless:

1. In a silent session with no `announce`, the warning is **heard** at ~45 s and
   suppression **ends** at ~90 s, with NVDA speaking normally afterwards.
2. `getSpeech` after a lift returns entries **captured during and after** it —
   indices and timestamps continuous across the transition.
3. A say-all started after a lift reads the whole document and carries the caret
   (11.13's re-run, repeated in the pass-through state — the callback path is the
   one Part 3 says must not double-run).
4. An `announce` every 30 s means the warning is **never** heard.
5. An `askUser` prompt left open past 90 s does **not** trip the cap.
6. Re-suppression after a lift is audible, and warns again 45 s later.
7. With `unattended` ticked, a silent session stays silent well past 90 s.
8. `nvda.log` shows balanced suppression markers on every path above.

## Part 11 — amendments made while implementing

Per AGENTS.md, the layout in Part 6 is the review gate, and a change to it rides
in the implementing PR with a one-line why. Nine, in the order they arose.

1. **`SpeechSource` gains a third method, `is_suppressing()`,** beside the two
   Part 6 named. Part 5 promises that `status` reports the session's *current*
   suppression state, and only the adapter knows it: a session may be suppressing,
   suspended for a prompt, or passing through after a lift, and the domain
   re-deriving that would be a second copy of the adapter's own state machine.

2. **The wire gains a `PingResult`,** where Part 7 named only `SilenceCapInfo`.
   Same reason: a lift happens on the reader with nothing pushed, so the only
   honest way for `status` to answer is to ask — and it already makes a real
   `ping` round trip so its answer is proof rather than memory. `ping` answered
   with `AckResult` before, which `bye` also uses, so a session-specific fact
   could not go on it. `{ ok, suppressing }`, both optional; the wire is
   pre-release (protocol.md §8) and both halves ship from this repo.

3. **Go: `SessionLifecycle.Ping` and `Connection.Verify` return a
   `ports.PingReport`** rather than only an error, which is how (2) reaches
   `status`. Six call sites, all of which discard it.

4. **`Announcer` gains `silence_notice(SilenceNotice)`,** where Part 6 implied the
   Session would speak text through the announcer. The bridge domain has no
   `_()` — NVDA installs it, and the domain is unit-tested headlessly — so a
   translatable sentence cannot live there. The domain says *what happened*; the
   adapter says it in the reader's own language, exactly as `SessionSignals` does.

5. **`SessionContext` gains `mode` and `silence_cap_policy`** beside the methods
   Part 6 listed. The Session must know the capture mode to decide whether a cap
   applies at all (it is created only for a `silent` session), and `hello` must
   report the machine's policy whatever mode was asked for — Part 5 calls it a
   fact about the machine. Both are set the way `persona` already is.

6. **`SilenceCapPolicy` gains a `from_settings` named constructor.** Part 6 says
   the entity validates the ordering, and the plain constructor raises — right for
   a programming error, wrong for a config file a human typed, where two settings
   read independently can each look sane and still cross over. `from_settings`
   falls back on the shipped defaults, so the decision stays in the tested domain
   instead of in `plugin.py`, which is the untested edge.

7. **`BridgeConfig` gains setters for the two thresholds,** not only the getters
   Part 6 named: the dialog's spin controls have to persist what the human types.

8. **The guidance paragraph goes in the server's own
   `adapters/mcp/documents/guidance-method.md`,** not in
   `domain/controllers/reader_guidance.go` as Part 8 said. That controller serves
   the *bridge's* document, which it carries opaque and never composes — the rule
   about agent behaviour is the server's own to state, and `guidance-method.md` is
   where such rules already live.

9. **The markers pair through two helpers** in the silent speech source rather
   than a second marker pair. Part 6 asks that a human reading `nvda.log` never
   find a suppression that never ended; a lift *is* the end of one, so it writes
   the existing `RESTORED` marker (after a line naming the cap as the cause) and a
   re-arm writes `SUPPRESSED` again. One balanced pair on every path, rather than
   two pairs that could interleave.
