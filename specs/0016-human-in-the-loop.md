# Spec 0016 — human-in-the-loop (entry 11.2)

Status: **agreed in conversation 2026-07-29, with one question still open** —
the sequencing of the heartbeat fix (see "The heartbeat fix", below). Everything
else is decided and ready to implement. No code written.

Scheduled **after** the real-world run (entry 11b) so the run could say whether
the cheap shape below is enough before the expensive one is built. It ran, and
nothing in it showed a need to build stage 2 — see that section.

## Goal

The agent is driving NVDA in `silent` mode and needs something only the human
can supply — a password, a CAPTCHA, a decision, a physical act ("plug the
braille display in"). Today it has no way to ask and no way to be answered. Give
it one, **without ending the session.**

## The problem, stated exactly

Three facts combine badly:

1. In `silent` mode the capture filter empties every speech sequence, so *all*
   of NVDA's speech is suppressed — not just the app under test. A tester in a
   silent session cannot hear anything.
2. The bridge's only human-facing channel, `announce` (spec 0008), speaks one
   canned utterance through `getSynth().speak()`, below the filter. It is
   fire-and-forget: there is no reply.
3. The wire is strictly request/response — server sends, bridge replies. **There
   is no unsolicited bridge→server frame.** So nothing at the bridge can push a
   human's answer toward the agent; the agent must ask for it.

So the agent can currently make a noise at a human who cannot hear anything
else, cannot navigate, cannot reply, and whose only exit is the panic gesture —
which stops the whole bridge and ends the session.

## Why not simply end the session and start a new one — **rejected**

Considered 2026-07-23 and rejected. It is genuinely simpler, and teardown does
restore speech for free (`_teardown` stops the speech source, which unregisters
the filter). But:

1. **The buffers reset.** `SpeechBuffer`/`BrailleBuffer` are built at `hello` and
   live in `ctx.adapters`. A new session re-seeds index 0 and the first capture
   lands at 1 again. Every bookmark the agent held is now wrong — and not loudly
   wrong: index 7 is still a valid index, it just means something else. Silent
   corruption of exactly the assertions the project exists to make reliable.
2. **The transcript and NVDA log capture are session-scoped.** Six restarts
   scatter the record across six file pairs, defeating spec 0009's purpose.
3. **`logLevel` is session-scoped** and must be re-requested each time.
4. **There is no way back in.** Fatal. After `bye` the agent is the only party
   that can restart the conversation, via `connect_reader` — and it stopped the
   session precisely because it could not hear the human. It has no signal
   telling it the human is done, so its only options are a fixed sleep or an
   immediate reconnect-and-hope. **Ending the session destroys the very channel
   needed to learn that it may resume.**
5. It also forecloses [spec 0017](0017-observe-only-control.md) entirely:
   observe-and-interfere requires one live session throughout, by definition.

## Decided

### The mechanism is suspending suppression, not ending the session

The realisation that shrinks this entry: the human does not need the session
gone, they need **speech back**. That is a much smaller thing — unregister the
`filter_speechSequence` handler for the duration of an interaction window and
re-register it after — and it keeps everything else alive.

`SpeechSource` gains `suspend()` and `resume()`. In `NvdaSilentSpeechSource` they
unregister and re-register the filter; in `NvdaLiveSpeechSource` they are no-ops,
because live mode never suppressed anything. Both are idempotent, like `stop()`.

It fails in the safe direction: a `resume()` that never happens leaves the tester
with speech, not silence. Teardown already calls `stop()`, which unregisters
unconditionally, so a suspended session that dies is a session that was already
audible.

### Speech is not captured while suspended

The tester navigating a dialog is not reader-under-test output. Feeding it into
the speech buffer would corrupt the very assertions the agent is making. Since
indices are append-only, "not captured" simply means no new indices, so the
agent's before/after arithmetic stays sound across the window. The transcript
records the window opening and closing, so the gap is explained in the human
record rather than being a mystery.

### The window is opened by `askUser` and closed automatically

Three ways it closes, all of them: the human answers, **the window's own
lifetime expires**, or the session tears down. The window is exactly the
interaction, so there is no suspended state the agent can leak or forget to
close.

**Decided 2026-07-29 — the window's lifetime is its own, not the poll's.** The
draft said "the timeout expires" without saying which, and the two candidates
behave very differently. If a `waitForUserReply` timeout closed the window, the
window would die on the first poll miss and the whole present-then-poll shape
would collapse. So it does not: a poll miss is just a miss.

`UserPrompt` therefore carries an absolute deadline, defaulting to **300
seconds**, set when `askUser` mints it. On expiry the prompt is marked cancelled
and the speech source resumed, so the next poll returns a clean
`answered: false` against a closed window rather than waiting forever. Without
this bound an agent that stops polling would leave capture suspended
indefinitely — the exact half-suspended failure that `suspendCapture` was
rejected for, arrived at by another route.

An explicit `suspendCapture`/`resumeCapture` pair was considered and is **not**
in this entry. It is more flexible — "go do this multi-step thing by hand and
tell me when you are done" — but a forgetful or crashed agent leaves the session
half-suspended, and the flexibility is speculative until the 11b run shows a case
for it. If one appears, it is an amendment, and `askUser` becomes a composition
of the two.

### The ask is present-then-poll, because of a 30-second wall

**This is the constraint that decides the command shape**, and it is a real,
measured one:

- `wiring.py:44` — `heartbeat_timeout = 30.0`, `inactivity_timeout = 120.0`.
- `session.py:145-147` — `_touch_heartbeat()` runs **before** `_dispatch()`, and
  `_check_deadline()` **after**. A handler that blocks 60 s leaves
  `now - last_message_time == 60 >= 30`, so the session tears down with
  `HEARTBEAT_TIMEOUT` the instant it answers.
- `json_lines_client.go` — one mutex serialises whole round trips, so the 20 s
  heartbeat goroutine **cannot** slip a `ping` in while a call is in flight; it
  blocks on the mutex.

So the longest any bridge command may block today is under 30 seconds, and a
human typing a password needs minutes. Hence:

- `askUser` presents the prompt and **returns a ticket immediately.**
- `waitForUserReply(ticket, timeout)` blocks for at most its own timeout and
  returns `answered: false` if nothing yet; the agent re-calls.

That is the `waitForSpeech` shape exactly, including the client's `waitSlack`
(5 s added to the caller's timeout so the *bridge* times out first and the agent
gets a clean negative rather than a lost connection). It is also robust to the
timeouts this project does not own: `DefaultCallTimeout` (15 s) and the MCP
client's own tool timeout.

The prompt is presented **once**, tied to the ticket, so re-polling does not
re-nag the human.

### Three timeouts, and how a window survives them — **Decided 2026-07-29**

Polling is not merely one valid shape here; it is **what keeps the session
alive**, and that is load-bearing enough to state rather than leave implicit.

| Timeout | Reset by | What it bounds |
|---|---|---|
| heartbeat, 30 s | any message, `ping` included | each **poll's own timeout** |
| inactivity, 120 s | real commands only (`ping` sets `resets_inactivity = False`) | the agent's **poll interval** |
| window lifetime, 300 s | nothing — absolute, from `askUser` | how long the human gets |

Trace each way it can go wrong and the composition is already correct, so **no
change to the watchdogs is part of this entry**:

- **The agent abandons the session.** Inactivity fires at 120 s, teardown runs,
  `stop()` unregisters the filter, and **the tester gets their speech back.**
  This is why the inactivity watchdog must *not* be suspended for the window: it
  is the last thing that rescues a blind user whose agent died mid-question.
- **The human never answers while the agent waits patiently.** The window's own
  deadline expires, the source resumes, the prompt is cancelled, and the next
  poll returns a clean negative.
- **The human answers.** The window closes normally.

Note the consequence: a window can only outlive 120 s *if the agent is still
polling*, so the window deadline is only ever reached in the case where someone
is genuinely waiting — which is exactly when it should be.

### The heartbeat fix — **OPEN, to be resolved before implementation**

While a handler runs, the peer's silence is *our* doing, not evidence it died.
`_dispatch` should refresh the heartbeat when it returns, not only before it is
called. Verified still present on main: `session.py:146-148` touches the
heartbeat, dispatches, then checks the deadline — so `waitForSpeech` with a
caller-supplied `timeout: 40` kills the session the instant it answers, despite
`wait_for_speech.py`'s comment asserting timeouts stay "well below the watchdog
windows" with nothing enforcing it.

Two sub-decisions, and the second matters more than it looks:

**(a) Refresh the heartbeat after dispatch.** Not contentious — this is the bug.

**(b) Also refresh *inactivity* after dispatch?** `_last_command_time` is set
*before* `handler.execute()`, so a handler blocking 300 s trips inactivity even
with (a) fixed. Proposed: **no.** Inactivity means "has the agent abandoned this
session", and per the table above it is the last backstop that frees a blind
user's speech filter. A backstop a hanging handler can defeat is not a backstop.
Handlers carry their own timeouts; this one should stay measured from dispatch
start.

**What is open is the sequencing, not the fix.** The proposal is to land (a)
alone and first, in its own PR with a regression test — a handler that blocks
past the heartbeat window must not end the session — because it is a live bug
today, independent of this entry, and reviewable on its own merits.

**Whichever way that goes, it does not change this entry's design.** Even with
unlimited blocking at the bridge, `DefaultCallTimeout` is 15 s in the Go client
and the MCP client imposes its own tool timeout — **timeouts this project does
not own**. A blocking `askUser` would die at the server or the client regardless.
Present-then-poll is required by those, not by the heartbeat, and must not be
"simplified" away later on the grounds that the heartbeat was fixed.

### The reply is an acknowledgement gesture first, a dialog only if needed

**The scope decision, and the one the 11b run should settle.**

Most of the time the human does not need to *say* anything — they need to **do**
the thing and hand control back. That is a gesture press, not a dialog, and the
panic gesture is the exact precedent: an `@script` with a `scriptCategory`, so it
appears in Input Gestures and the user can rebind it. Roughly ten lines.

So this entry ships **stage 1**: `askUser` announces the prompt, suspends
suppression, and waits for the acknowledgement gesture.
`WaitForUserReplyResult` carries `{ answered: bool, text: str }` with `text`
always empty.

**Stage 2** — the wx dialog with canned Yes/No buttons and an edit field — is
deliberately *not* built here. It is designed for, not built: the same command
answers more richly by populating `text`. Because unknown and absent object
fields are ignored (protocol.md §2), adding the dialog later is not a wire break
and not a re-spec of the command. Build it when a real run shows "press a key
when you're done" was insufficient — which is a question 11b answers and
speculation does not.

**Decided 2026-07-29: stage 1 only.** The 11b run happened and showed no case
needing a typed reply. A later observation sharpened why: in a session driven
from an agent chat window, every human-in-the-loop moment was "do this, then
tell me" — a hand-back, not an answer, and the human answered in the chat
because they were sitting at it. The gesture exists for the case the chat cannot
serve: a tester inside the application under test, in a silent session, who
cannot reach the chat window at all. Nothing yet shows they need to *say*
something once they get there.

### It is one new capability, `interact`

Covering `announce`, `askUser` and `waitForUserReply`. `Capability.ANNOUNCE`
(added in 9c, exposed at the server in 11a) is **renamed** to
`Capability.INTERACT` rather than joined by a second capability: the three
commands are one coherent group, a reader that can speak to a human can almost
certainly be asked by one, and splitting them would advertise a distinction no
bridge author will want to make. v1 is pre-release and amendable in place
(protocol.md §8) and the only consumer is this repo, so the rename is cheap —
but it does touch `protocol.py`, `schema.json`, the Go binding, the domain
capability constant, the handshake mapping and the conformance bridge, so it is
not free either.

**Decided 2026-07-29: rename.** Entry 11.1 widened `NVDA_CAPABILITIES` and the
cost of that ripple is now known rather than guessed — it is mechanical, and the
conformance expectations are the only place it is easy to forget. Paying a known
one-off diff to avoid permanently uglier vocabulary is the right trade while v1
is pre-release and this repo is the only consumer.

## Wire contract changes

Amendments to `shared/nvda_mcp_wire/protocol.py`, regenerating
`specs/wire/v1/schema.json`, plus prose in `specs/wire/v1/protocol.md`:

| Addition | Shape |
|---|---|
| `Command.ASK_USER = "askUser"` | params `AskUserParams{prompt: str}` → `AskUserResult{ticket: str}` |
| `Command.WAIT_FOR_USER_REPLY = "waitForUserReply"` | params `WaitForUserReplyParams{ticket: str, timeout: float = 30.0}` → `WaitForUserReplyResult{answered: bool, text: str}` |
| `Capability.INTERACT = "interact"` | replaces `Capability.ANNOUNCE` |

A `waitForUserReply` for an unknown or already-answered ticket is a
`CommandError`, not a silent `answered: false` — "you polled the wrong ticket"
and "the human has not answered yet" are different situations with different
remedies, the same reasoning as the server's `CapabilityError` distinguishing
"connect first" from "this reader cannot".

## Class/file layout

### Bridge — domain (strict-checked)

1. **`domain/entities/user_prompt.py`** — entity. One outstanding ask: its
   ticket, prompt, answered flag, answer text and **absolute deadline** (300 s
   from minting; see "The window is opened by `askUser`"), guarded by a lock
   because the NVDA main thread writes the answer while the session thread
   polls it. An expired prompt answers `answered: false` and is cancelled
   rather than waited on. Holds a
   `_wait(predicate, timeout)` loop against the injected `Clock`, mirroring
   `IndexedBuffer._wait` — same poll cadence, same fake-clock testability.
2. **`domain/ports/user_prompter.py`** — port. `present(prompt, ticket)` and
   `cancel(ticket)`. Implemented by `NvdaUserPrompter`; used by
   `AskUserHandler`. The port is what keeps the domain from knowing that "ask a
   human" means beeps and a gesture.
3. **`domain/controllers/commands/ask_user.py`** — `AskUserHandler`. Mints a
   ticket, stores the `UserPrompt` on the context, suspends the speech source,
   asks the prompter to present, returns the ticket. Returns immediately.
4. **`domain/controllers/commands/wait_for_user_reply.py`** —
   `WaitForUserReplyHandler`. Looks the ticket up, waits on the entity, and on a
   real answer resumes the speech source and clears the outstanding prompt. A
   poll miss leaves the window open — only an answer, the window deadline or
   teardown closes it. On finding an expired prompt it resumes, clears, and
   returns `answered: false`, so the window cannot outlive its deadline merely
   because nobody polled during it.
5. **`domain/controllers/commands/session_context.py`** — gains the single
   outstanding `UserPrompt | None` and the accessors for it. One at a time: a
   second `askUser` while one is outstanding is a `CommandError`, because two
   simultaneous questions to one human through one audio channel is not a
   situation with a good answer.
6. **`domain/ports/speech_source.py`** — `suspend()` / `resume()` added.
7. **`domain/controllers/session.py`** — the heartbeat fix, plus a teardown step
   that resumes and cancels any outstanding prompt.

### Bridge — adapters (NVDA edge, pyright-ignored)

8. **`adapters/nvda_silent_speech_source.py`** — real `suspend`/`resume`
   (unregister / re-register the filter), idempotent.
9. **`adapters/nvda_live_speech_source.py`** — no-op `suspend`/`resume`.
10. **`adapters/nvda_user_prompter.py`** — presents: two cue beeps distinct from
    the announce cue, then the prompt spoken through the live synth, then a
    spoken instruction naming the acknowledgement gesture. All via `run_on_main`.
11. **`plugin.py`** — the acknowledgement `@script`, default
    `kb:NVDA+control+shift+a`, in the existing `scriptCategory` so it is
    rebindable. It routes to whatever prompt is outstanding on the live session,
    and says so audibly when there is none — a user who presses it idly deserves
    an answer, not silence.

### Server

12. **`domain/ports/announcer.go`** → renamed/extended to the `interact` group:
    `Announce(text)`, `AskUser(prompt) (ticket, error)`,
    `WaitForUserReply(ticket, timeout) (UserReply, error)`.
13. **`adapters/bridge/json_lines_client.go`** — the two new calls, the wait one
    budgeting `timeout + waitSlack` like `WaitForSpeech`.
14. **`domain/controllers/tools/ask_user.go`** and **`wait_for_user_reply.go`** —
    two controllers, gated on `interact`, plus registry lines.
15. **`domain/entities/capability.go`**, **`handshake.go`**, **`tool_context.go`**
    — the `announce` → `interact` rename.

### Tests

16. Fakes for `UserPrompter` and the extended `SpeechSource`; a fake speech
    source that records suspend/resume so "capture stops during the window" is
    asserted as behaviour.
17. Handler unit tests both sides; a wire-level scenario covering
    ask → poll-miss → answer → poll-hit; a session test proving teardown resumes
    a suspended source and cancels an outstanding prompt; and a regression test
    for the heartbeat fix — a handler that blocks past the heartbeat window must
    not end the session.

## Live-NVDA checklist (11.2's PR body)

1. In a silent session, `ask_user` is heard: cue beeps, the prompt, and the
   instruction naming the acknowledgement gesture.
2. Speech returns the moment the prompt is presented — the tester can navigate,
   hear typed characters, and read the screen normally.
3. What the tester hears during the window does **not** appear in `get_speech`,
   and the speech index is unchanged across it.
4. Pressing the acknowledgement gesture ends the window; suppression resumes;
   the agent's next `wait_for_user_reply` returns `answered: true`.
5. A poll before the answer returns `answered: false` at its timeout, and the
   session survives.
6. A prompt left unanswered past its timeout resumes suppression on its own.
7. The panic gesture during an open window stops cleanly and leaves speech on.
8. Killing the MCP client during an open window leaves the tester **audible** —
   the invariant this whole design is arranged around.
9. A session held open across a five-minute human interaction does not trip
   either watchdog (the heartbeat fix, observed live).

## Out of scope

- The reply dialog with canned answers and an edit field — stage 2, above.
- Explicit `suspendCapture`/`resumeCapture` — above.
- Unprompted human→agent messages (a mailbox the agent polls). Different
  mechanism: nothing pushes, so the agent must poll, and a mailbox nobody checks
  is a feature that works only when the agent remembers. If wanted, its own
  entry, and it should be considered together with whether every tool result
  should carry a "pending messages" flag — which is what would make it reliable
  and which is a wire envelope change.
- MCP elicitation (`elicitation/create`, supported by go-sdk v1.6.1). It is the
  protocol-correct answer for a *different* topology: it renders in the MCP
  client's UI, which is the agent chat window, which is exactly where a tester
  in a silent session cannot get to. Worth revisiting if the reader ever runs on
  a different machine from the client.

## Definition of done

The files above; headless suites, pyright strict, ruff, the schema drift gate and
the conformance job green; and the live-NVDA checklist run with the tester at the
keyboard, results in the PR body.
