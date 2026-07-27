# Spec 0017 — enforced observe-only sessions (entry 11.3)

Status: **drafted 2026-07-23, awaiting review.** Not yet agreed in
conversation; no code written. The smallest of the session-E entries.

## Goal

A session where the **tester drives** and the agent can only watch: the bridge
*rejects* every command that would move the user's machine. Not a convention the
agent is asked to honour — a gate the bridge enforces.

## What already exists, and what does not

Most of "passive mode" is already shipped, and the spec should say so plainly
rather than rebuild it:

- `hello(mode="live")` already means the real synth keeps talking and capture is
  by observation (`pre_speechQueued`, no suppression). The tester hears
  everything.
- `getSpeech(sinceIndex)` already means "everything since I last looked", with
  half-open ranges. That *is* "the user runs and the agent receives the feedback
  all together".

So the observing half of the workflow works today. What does not exist is
**enforcement**: nothing stops the agent from sending `pressGesture` into the
tester's hands, or `setConfig` into their reader, while they are mid-task.

## Why enforcement is worth having at all

The honest counter-argument is "just tell the agent not to". Three reasons it is
not enough:

1. **It is the same argument that deferred remote TCP.** 9.1b greyed out the
   Remote TCP option as **Decided**, because it is remote keystroke injection
   (`pressGesture`) and remote config write (`setConfig`), and that needs its own
   security spec. The exact same two commands are the exact same hazard when the
   human is the one holding the keyboard. A mode that structurally cannot send
   them is the local answer to the same question.
2. **A blind tester cannot see a stray keystroke coming.** An agent that presses
   `kb:control+home` while the tester is typing has moved their cursor with no
   visual cue that it happened. "The agent was told not to" is not a safety
   property.
3. **It makes an unattended agent auditable.** "This session could not have
   touched anything" is a claim the transcript can make truthfully, which matters
   for the very use case the project is heading toward.

## Decided — proposed

### It is a `control` field on `hello`, not a third `CaptureMode`

Capture mode is about **audio**: does the tester hear the reader. Control is
about **input**: may the agent move the machine. They are orthogonal — all four
combinations are meaningful, and the interesting one is `live` + `observe` (the
tester works normally, the agent watches) which a third `CaptureMode` member
could not express without also forcing a capture choice.

So:

```
ControlMode: "full" | "observe"
```

on `HelloParams`, defaulting to `"full"` when absent — an older server that does
not send the field gets today's behaviour, which is what protocol.md §2's
ignore-unknown-fields rule is for in the other direction. `HelloResult` echoes
the mode in effect, as it already does for capture mode, so the agent is told
what it got rather than assuming its request was honoured.

### The gate is in the Session's dispatch, driven by a property of the handler

Not an `if request.cmd in {...}` list in the loop. Each `CommandHandler` gains a
class attribute `mutates_reader: bool` (default `False`), set `True` on
`PressGestureHandler` and `SetConfigHandler`. The Session refuses a mutating
handler in an observe session with a `CommandError` naming the mode.

This follows the two attributes the handler base already carries —
`available_before_hello` and `resets_inactivity` — so the dispatch loop keeps
asking the handler about itself rather than keeping a second list of command
names that can drift from the registry. A future mutating command is
opted **in**, and the failure mode of forgetting is that it is *allowed* — so
the base default and the test that enumerates handlers matter, and the spec says
so out loud.

### The server retracts the tools rather than letting calls fail

The capability gate is already structural: a port is handed over only when the
reader announced the capability, and a tool whose port is nil is not advertised.
Observe mode reuses that machinery exactly — when `hello` echoes
`control: "observe"`, the handshake does **not** hand over `Gestures` or
`Config`, so `press_gesture` and `set_config` are never advertised for that
session.

That is strictly better than advertising them and failing the call: the agent
never plans around a tool it cannot use. The bridge-side rejection remains as the
backstop, for the same reason `CapabilityError` exists on a gated tool that is
called anyway — the tool list is a snapshot, and a call can always arrive late.

**Note the interaction with `getConfig`.** `config` is one capability group
covering both read and write, so withholding the port to block `setConfig` also
blocks the harmless `getConfig`. Two options, flagged for review: accept it
(simplest, and a session that may not write probably has little use for reading),
or split the group. Splitting is a wire change affecting every bridge author and
is almost certainly not worth it for this. **Proposed: accept it, and say so in
the tool descriptions.**

### The tester is told, audibly, which kind of session started

The session-start beeps (spec 0008) are two ascending tones. An observe session
uses a distinguishable cue — proposed: three ascending tones — so a tester
starting an unattended run knows by ear that the agent cannot type. It costs one
extra `wx.CallLater` and it is the only feedback a blind tester gets about a
property they are trusting.

The transcript records the control mode at session open, so the audit claim above
is written down and not merely believed.

### The control dialog gets nothing

Deliberately. Control mode is chosen per session by the party that knows what the
session is for — the agent, at `connect_reader` — exactly as capture mode is
(`SessionOptions`' reasoning: "under auto-connect they would have to be chosen by
whoever wrote the MCP host config, before anyone knew what the session was
for"). A persisted user-level "never allow gestures" setting is a different
feature with a different argument, and it is not this entry.

## Wire contract changes

| Addition | Shape |
|---|---|
| `ControlMode` StrEnum | `FULL = "full"`, `OBSERVE = "observe"` |
| `HelloParams.control` | optional `ControlMode`, absent means `full` |
| `HelloResult.control` | the mode in effect |

Regenerates `schema.json`; prose added to `protocol.md` §3 and §4.

## Class/file layout

### Shared

1. **`shared/nvda_mcp_wire/protocol.py`** — `ControlMode`, the two `hello`
   fields, `COMMAND_SHAPES` unchanged (no new command).

### Bridge

2. **`domain/controllers/commands/command_handler.py`** — the
   `mutates_reader: bool = False` class attribute, documented beside the two
   existing ones.
3. **`domain/controllers/commands/press_gesture.py`**,
   **`set_config.py`** — set it `True`. (`set_config` arrives in
   [spec 0015](0015-bridge-introspection.md); if 11.3 lands first, this is one
   line added there instead.)
4. **`domain/controllers/commands/hello.py`** — reads the requested control
   mode, records it on the context, echoes it in the result.
5. **`domain/controllers/commands/session_context.py`** — carries the control
   mode.
6. **`domain/controllers/session.py`** — the dispatch gate; the observe-session
   start cue; the transcript line.
7. **`domain/ports/session_signals.py`** + **`adapters/nvda_session_signals.py`**
   — `observe_session_started()` beside the existing two.

### Server

8. **`domain/entities/control_mode.go`** — the entity, beside `capture_mode.go`.
9. **`domain/ports/session_dialer.go`** — `SessionOptions.Control`;
   `ReaderSession.Control`.
10. **`adapters/bridge/handshake.go`** — sends it, reads the echo, and withholds
    `Gestures`/`Config` when the echo says observe.
11. **`domain/controllers/tools/connect_reader.go`** — a `control` parameter,
    with the schema text explaining what the agent gives up.
12. **`adapters/mcp/info_resource.go`** — `screenreader://info` reports the
    control mode, so an agent that did not open the session can still learn what
    it may do.

### Tests

13. Handler-level: a mutating handler refused in an observe session, permitted in
    a full one; a test that **enumerates every registered handler** and asserts
    its `mutates_reader` value, so a new mutating command cannot be added without
    a deliberate answer.
14. Wire-level scenario: an observe session refusing `pressGesture` and serving
    `getSpeech`.
15. Server: the handshake withholds the two ports on an observe echo; the
    advertised tool list lacks `press_gesture` and `set_config`.
16. Conformance: an observe session end to end against the real Python bridge —
    the tier that would catch the echo being dropped in the binding.

## Live-NVDA checklist (11.3's PR body)

1. An observe session starts with the distinguishable cue.
2. `press_gesture` and `set_config` are absent from the agent's tool list.
3. Calling `press_gesture` anyway (by tool name, past the list) is refused, and
   **no keystroke reaches the machine** — verified with a text field focused.
4. `get_speech`, `get_braille` and the introspection tools all work normally.
5. The tester drives a full EnhancedFindDialog interaction by hand and the agent
   reads back the whole run from one `get_speech` call.
6. The transcript records the control mode at session open.
7. A `full` session in the same NVDA run afterwards behaves normally — the gate
   is per session, not global.

## Out of scope

- A persisted user-level setting in the control dialog — above.
- Splitting the `config` capability into read and write groups — above.
- Any rate limiting or per-gesture allowlist. The mode is binary on purpose;
  "may press some gestures" is a policy with no obvious owner.

## Definition of done

The files above; headless suites both sides, pyright strict, ruff, the schema
drift gate and the conformance job green; the live-NVDA checklist run with the
tester at the keyboard, results in the PR body.
