# Spec 0050 — the handshake climbs the ladder

**Status:** **Decided** — board entry 13.20, agreed in conversation with Marlon
on 2026-08-31. Every decision in §2 was settled in that conversation; this
document records them with their reasons and adds the class/file layout that is
the review gate. Amendments made while implementing are in §7.

**Board entry:** [13.20](../ROADMAP.md), lane 3.

**Found by:** Marlon, 2026-08-31, driving 13.19's live checklist.

> `poe build` deletes and replaces the capture-voice bundle, so the system
> forgets the extension; every session then returns `speech: []`, which is
> indistinguishable from "the reader said nothing".

It cost that checklist an hour. The bridge **knew**: `BridgeListener` printed
`providerNotRunning` in its startup report and the handshake established the
session anyway.

## 1. The problem, exactly

`ProviderState` is a five-rung ladder — `notRegistered`, `registered`,
`published`, `selected`, `capturing` — and until this entry `hello` only ever
**reported** where the climb had stopped. It read the state, and:

- in a `silent` session it refused, by named condition with its recovery (13.6);
- in a `live` session it wrote a note in the transcript and carried on.

So a live session on a machine whose capture voice is not registered establishes
cleanly, announces six capabilities, and then answers every speech read with an
empty list. That empty list is the one answer
[`ReaderCondition`](../bridges/voiceover/Sources/VoiceOverBridgeDomain/Entities/ReaderCondition.swift)'s
own header says a bridge on this route must never give:

> An empty read-back is the same answer for "the reader said nothing", "the
> provider died", "the voice is not selected" and "VoiceOver never offered the
> voice at all".

The two waiting speech handlers do name `unheardConditions` when a wait times
out — that machinery is right and stays — but `getSpeech` does not wait, and an
agent that reads back nothing after a gesture has no reason to suspect the
machine rather than the page.

**And the trigger is our own build.** `poe build` runs `build.sh`, which begins
`rm -rf build` and reassembles the `.app` from scratch. LaunchServices and
pluginkit then hold a registration for a bundle that no longer exists at that
inode, and the voice is gone. So the state this entry exists to repair is not
an exotic one a user might reach — it is the state every developer of this
bridge is in immediately after building it.

### 1.1 The bridge could have fixed it all along

Nothing in the failing state needs a human. `lsregister -f` and `pluginkit -a`
are two subprocesses; selecting the voice has been the bridge's job since 13.6
(spec 0047 findings 16–17); launching the reader is `open -a VoiceOver`. What
was missing was not a capability but a **decision about who does it**, and
`ProviderLifecycle`'s header made that decision explicitly and wrongly:

> `register()` / `unregister()` are named in spec 0046's 13.6 table and are
> deliberately absent: re-registration only takes effect after the reader is
> RESTARTED (spec 0047, finding 6), and restarting a blind person's screen
> reader is not something a handshake may decide.

The argument is sound about the **restart** and was over-applied to the
**registration**. Registering is silent, changes nothing a running reader can
see, and only its *effect* needs a restart. §2.4 narrows the rule rather than
contradicting it, and `ProviderLifecycle.swift`'s header is rewritten in the
same commit — a header that says a method is deliberately absent, sitting above
that method, is worse than no header.

## 2. Decisions

### 2.1 `hello` climbs the ladder, eagerly and in order

The handshake performs its own setup. Five rungs, all of them attempted, in this
order, each failing **by name** with what the agent must do next:

| # | Rung | What it does | Fails when |
|---|---|---|---|
| 1 | permissions | **reads** Accessibility and Automation-of-VoiceOver | either is not granted |
| 2 | reader alive | asks the reader its own name; if silent, **activates** it and asks again | it will not come up |
| 3 | registration | `lsregister -f` on the app, then `pluginkit -a` on the appex, then polls | pluginkit still does not list it |
| 4 | selection | points the reader at the capture voice and confirms the write took | the write did not stick |
| 5 | capture proof | makes the reader speak and requires an utterance to arrive | nothing arrives inside the bounded wait |

**Eager, not lazy.** Every rung runs on every handshake; a rung whose work is
already done is a cheap read. That is deliberate: a lazily-repaired session is
one whose first three commands behave differently from its fourth, and the whole
point of this entry is that `connect_reader` either hands back a session that
can capture or says why it cannot.

**Rungs 3 and 4 are conditional on the rung below them being unmet**, which is
not laziness but the same eagerness expressed cheaply: `register()` runs only
when `state() == .notRegistered`, because re-registering a registered extension
publishes nothing new and costs two subprocesses and a five-second poll;
`selectCaptureVoice()` runs only when the reader is not already on our voice,
which is the rule 13.6 already had.

**Rung 5 is the only one that is evidence.** `ProviderState.capturing` is
documented as provable by nothing but an utterance arriving, and this is the
first thing in the bridge that actually provides that evidence rather than
inferring around it. The promotion goes through the existing pure
`observing(captured:)`.

### 2.2 Rung 1 — permissions are READ, and never asked for

`PermissionBroker.status` for both `.accessibility` and `.automationVoiceOver`.
Either one missing stops the handshake.

**The handshake never calls `request`.** It does not open a consent dialog and
does not wait for one to be answered. A handshake that blocks on a modal dialog
is a handshake that hangs, and on this machine nobody may be looking at the
screen. Reading costs nothing and shows nothing: `AXIsProcessTrusted()` raises
no dialog, and the automation read is the `return name` probe the bridge sends
anyway.

**The failure is addressed to the AGENT**, because an agent is what reads it.
Not "grant this permission" — the agent cannot — but *tell the human at the
machine to grant it, then call `connect_reader` again*. `Permission.recovery`
already carries the human-facing half (which System Settings pane, and the SSH
wrinkle that names `/usr/libexec/sshd-keygen-wrapper`); the rung wraps it in the
instruction the agent can act on.

**The lever survives verbatim, and there is no sweep.** `PermissionBroker.request`
still has exactly **two** callers, both command handlers about to post a system
event, both through `AccessibilityGrant`. So

> a session that presses only the reader's COMMAND NAMES and reads speech never
> triggers an Accessibility request

is unchanged, word for word, and the counting-broker scenario in
`Tests/Integration/SessionRoundTripTests.swift` still asserts it end to end. The
structural check in `PermissionBroker.swift`'s header — *"this port's `request`
is reached from TWO COMMAND HANDLERS and from nowhere else"* — holds. What
changes is only that a **missing** grant is now fatal at connect rather than
discovered ten commands in.

**What is lost, plainly.** A machine that has never granted Accessibility can no
longer run a speech-only session. That is exactly what
[`scripts/voiceover_channels.sh`](../scripts/voiceover_channels.sh) was written
for — the channels probe runs where the keyboard probe cannot, and this bridge's
own `AGENTS.md` says so. The script itself is unaffected (it drives the reader
directly and never opens a bridge session), but the *property* it documents —
that this bridge is useful on a machine with no Accessibility grant — is spent
here. It is spent knowingly: a session that can read speech but cannot type is
worth less than a session that reports honestly why it cannot do either, and the
false-empty-read-back is the more expensive failure by an order of magnitude.

**How a human grants these is NOT this entry's, and it is an open question**
(§6). The VoiceOver Automation toggle they can reach themselves; Accessibility is
unclear, and the obvious answer — a button in the bridge — has a real problem:
TCC attributes a grant to the process it holds **responsible**, measured on
2026-08-31 to be `/usr/libexec/sshd-keygen-wrapper` rather than the bridge or the
agent, so a button may well grant something other than what needs it. For 13.20
the bridge **refuses**.

### 2.3 Rung 2 — the reader is alive, and the bridge may activate it

`ReaderLiveness.readerAnswersItsOwnName()`, which already exists and already asks
the narrowest question that separates a dead reader from a dead scripting object
model. If it answers no, the bridge **activates** the reader and asks again;
if it still does not answer, the handshake fails by name.

`ReaderLiveness` gains **`activate()`**. It is non-throwing, like the port's
existing method and for the same reason: activation is a *request*, the only
evidence that counts is the re-check, and a caller that had to handle two errors
in order to learn a boolean would be worse off.

**Measured 2026-08-31: `killall VoiceOver` does NOT relaunch it — `open -a
VoiceOver` does.** So the adapter runs `/usr/bin/open -a VoiceOver` through the
`ProcessRunner` seam, and every place in this repo that tells a human to restart
the reader now spells the pair: **`killall VoiceOver && open -a VoiceOver`**.
Never a `killall` on its own, which leaves a blind person with no screen reader.

This is the one rung that **starts** something rather than repairing it, and it
is worth naming why that is safe: activating VoiceOver is what the person's own
Command-F5 does, it is announced out loud by the reader itself, and a session
that is about to drive the reader needs it running anyway.

### 2.4 Rung 3 — registration, which is MACHINE state and is never undone

`ProviderLifecycle` gains **`register()`**, implemented in
`PluginKitProviderLifecycle` over the `ProcessRunner` seam it already holds:

1. `lsregister -f <app path>`
2. **then** `pluginkit -a <appex path>`

in that order, because spec 0041 C1 measured the first alone as not enough.

**It confirms by POLLING, not by reading the exit status.** Measured
2026-08-31: `pluginkit -a` hands the work to `pkd` and returns, so an immediate
`state()` reports failure on a registration that worked. A false alarm here is
worse than no check at all — it would send a human to re-register something that
is already registered — so the adapter polls `state()` for about five seconds and
reports failure only if the extension is still unlisted at the end of it.

**REGISTRATION IS NEVER UNDONE.** There is deliberately no `unregister()`, and
nothing at teardown is paired with `register()`, however much the symmetry
appeals — `ProviderLifecycle`'s own header names `unregister()` as a candidate
and that is the temptation. Two reasons, and the second is the one that will
matter later:

- Undoing it would recreate the exact bug this entry fixes: the next session
  would start on a machine that has forgotten the extension.
- The accept loop is serial today and will not always be. One client's
  disconnect must never deregister the voice out from under another.

The rule, in one sentence, and it is the one to keep:

> **SESSION state is restored at teardown; MACHINE state is not.**

The voice *selection* is session state and is restored on every teardown path —
that is hard invariant 3 in its macOS form and it is unchanged. The
*registration* is machine state and stays.

### 2.5 Rung 4 — selection, which already worked

`selectCaptureVoice()` is unchanged: it already discovers the identifier the
system published (by suffix), writes it with the plist type preserved, and
**confirms the write took**, which is where "the voice VoiceOver does not offer"
is actually caught (spec 0047, findings 16–17).

The order around it is unchanged and stays load-bearing: the user's own voice is
read and recorded on the context **before** ours is written, and it is recorded
only when it is not already ours — so every teardown path holds what to put back
even if a later rung throws, and a session that died without restoring cannot
make the bridge hand the extension itself as its own pass-through voice.

### 2.6 Rung 5 — proving capture with the safe probe

The bridge makes the reader speak and requires an utterance to arrive in the
session's `SpeechBuffer` inside a bounded wait. The probe is

    describe item in voiceover cursor

which this reader's own guidance document already calls the safe one: it
describes what the cursor is on and **moves nothing**. Choosing a command that
navigated would make every `connect_reader` a small, invisible edit to where the
person was.

It runs **after** the marker channel is opened and, in a silent session, after
suppression is in force — so the proof is inaudible in exactly the mode where
being audible would be a broken promise. Capture is unaffected by that ordering:
`CaptureController.capture()` emits to the sink **before** it synthesizes, which
is 13.5's ordering rule and is why first-utterance latency is identical in both
modes.

The bookmark is `SpeechBuffer.nextIndex()` taken **before** the press, so an
utterance that was already in flight cannot be mistaken for evidence.

No utterance inside the wait is a failure by name, and it carries
`ProviderState.selected`'s existing `unheardConditions` — both candidates with
both recoveries — because from outside the reader nothing distinguishes them.

### 2.7 It is fatal in BOTH modes, and here is the paragraph

13.6 made `silent` fatal and `live` not, and the asymmetry was right for what it
was about: `silent` is a promise about a human's ears that has to hold *from* the
handshake, while a live session that starts unhealthy can heal itself, because
writing the voice applies live in both directions (spec 0047, finding 17). This
sequence is fatal in both modes, and the reason it does not contradict that is
that it is about a **different promise**. What rungs 1, 2 and 5 establish is that
`getSpeech` means anything at all — and a live session makes exactly that promise
as loudly as a silent one does, because it announces the `speech` capability and
the server advertises five speech tools on the strength of it. The 13.6 argument
also assumed a bridge that only *reported*: "it may become healthy while it runs"
is a reasonable thing to say about a state nobody is repairing, and an unreasonable
one about a state this handshake has just tried five times to repair and failed.
Two rungs are not mode-dependent in any case — a live session with no Automation
grant, or with no reader running, can do nothing whatever — so a mode-conditional
ladder would be one sequence with two exits and no clean sentence describing
either. One sequence, one answer: **`connect_reader` returns a session that can
capture, or it says by name what stopped it.**

### 2.8 What this entry does NOT widen

- **The bridge does not become multi-session.** `BridgeServer.serve()` runs one
  session at a time by design, because a session mutates a **singleton** — it
  selects the reader's voice and holds the silence lease — and two would fight
  over one machine. A disconnect already leaves the listener up, so the
  reconnect this entry's failures ask for costs nothing.
- **The bridge still never restarts the reader.** §5.
- **No wire change.** A bridge failing a handshake it cannot serve is already
  what `protocol.md` §3 describes; gesture ids, `schema.json` and every DTO are
  untouched, so `poe gates` is unaffected and no MCP reconnect is required.

### 2.9 The bundle paths are Wiring's decision, and the adapter knows only identifiers

`register()` needs two filesystem paths; `PluginKitProviderLifecycle`'s header
says in as many words that it is "the place that knows what an answer means and
not the place that knows what we are called". So Wiring resolves them and passes
them in, resolving in this order:

1. **`Bundle.main`**, when the code is running inside the assembled `.app`.
2. The conventional **`build/` path beside the package**, which is where
   `build.sh` puts it and what the dev `BridgeListener` runs against.
3. Neither → the paths are `nil`, and `register()` is a **named failure carrying
   both commands** so a human can run them by hand.

**The bundle names are declared in Swift and read by `build.sh` with `sed`**,
which is exactly the pattern `BridgeVersion.swift` established at 13.11 and for
the same reason: the alternative is `APP_NAME` in the build script and a
hard-coded `"VoiceOverCaptureSpike.app"` in Wiring, drifting apart the first time
anybody renames anything, with the failure surfacing as a registration that
silently does nothing.

## 3. Class/file layout

The review gate: every file the implementing PR adds or changes, with its role
and its collaborators.

### 3.1 Domain — `Sources/VoiceOverBridgeDomain/`

| File | Role | Change |
|---|---|---|
| `Controllers/ReaderEdgeSetup.swift` | **controller — new** | Runs the whole five-rung use case. HOLDS: the `AdapterSet` (permissions, readerLiveness, providerLifecycle, gestureSender, silenceControl), the `SessionContext` (clock, transcript, `previousVoice`) and this session's `SpeechBuffer`. BUILT BY: `HelloHandler`, once per session — the same reason the `SpeechBuffer` is built there and not in `Wiring`: its collaborators do not exist until `hello` has read the mode and the factory has built them. Throws `CommandError`, like `AccessibilityGrant`, because it is in the controller layer and the agent must read one vocabulary of failure. |
| `Entities/SetupRung.swift` | **entity — new** | The five rungs as an enum, each with a `summary`, and the ONE function that composes a failure sentence: which rung, what is wrong, and **what the agent must do**. Pure. It mirrors `ReaderCondition` / `Permission` / `Precondition`'s `described` shape deliberately — a diagnosis without its recovery is a complaint — and exists so five rungs cannot grow five sentence shapes. |
| `Entities/ReaderCondition.swift` | entity — **amended** | New case `readerNotRunning` (rung 2's failure), which the vocabulary did not have: `scriptingChannelDead` is the reader answering its name and nothing else, and this is the reader not answering at all. Every `recovery` that said "restart VoiceOver" now spells `killall VoiceOver && open -a VoiceOver`, and the ones that said "register the extension" say that the bridge does it at connect and what it means when it did not take. |
| `Entities/ProviderState.swift` | entity — **unchanged** | The ladder and `observing(captured:)` are exactly what this entry climbs. Recorded here because "no change" is the reviewable claim. |
| `Ports/ReaderLiveness.swift` | port — **amended** | Gains `activate()`, non-throwing. Header gains the `killall` measurement and the rule that the re-check is the only evidence. |
| `Ports/ProviderLifecycle.swift` | port — **amended** | Gains `register() throws`. The "what is not here, and why" paragraph is **rewritten**: the restart argument survives narrowed, `unregister()` is refused by name with the two reasons of §2.4, and the session/machine-state sentence is stated where the next person will read it. |
| `Controllers/Commands/Hello.swift` | controller — **amended** | `establishReaderEdge` MOVES into `ReaderEdgeSetup` wholesale; the handler builds the setup and runs it. Its header's 13.6 paragraph is rewritten for §2.7. |

### 3.2 Adapters — `Sources/VoiceOverBridgeAdapters/`

| File | Role | Change |
|---|---|---|
| `PluginKitProviderLifecycle.swift` | adapter — **amended** | Implements `register()`: `lsregister -f` then `pluginkit -a`, then polls `state()` for `registrationConfirmationSeconds`. Gains an optional `bundlePaths` and a `Clock` (the poll must be injectable or its test takes five real seconds). Header's "registration is not performed here" paragraph rewritten. |
| `VoiceOverLiveness.swift` | adapter — **amended** | Implements `activate()` as `/usr/bin/open -a VoiceOver` through a `ProcessRunner`, which is a **second seam** beside the `AppleScriptRunner` it already holds — launching an application is not an AppleScript question, and routing it through one would have meant guessing at a scripting term nobody measured. |
| `CaptureBundle.swift` | **packaging declaration — new** | `captureAppName`, `captureExtensionName`, and the pure derivation of the app/appex path pair from a directory. Read by `Wiring` and, by `sed`, by `build.sh` — the `BridgeVersion.swift` pattern (§2.9). No decisions, no IO. |
| `Wiring.swift` | composition root — **amended** | `captureBundlePaths()`: `Bundle.main`, else the conventional `build/` directory beside the package, else nil. Passes them and a `Clock` to `providerLifecycle()`, and a `ProcessRunner` to the factory for the liveness adapter. Still asks the permission broker nothing. |
| `VoiceOverAdapterFactory.swift` | adapter — **amended** | Takes a `ProcessRunner` so it can build `VoiceOverLiveness`. One new constructor argument; every other decision unchanged. |

### 3.3 Tests

Hand-written stateful fakes subclassing their ports, mirrored under `Tests/`.

| File | Tier | Asserts |
|---|---|---|
| `Tests/VoiceOverBridgeDomainTests/Controllers/ReaderEdgeSetupTests.swift` | unit — **new** | each rung's failure names the rung and says what the agent must do; a healthy machine climbs all five and promotes to `capturing`; **no rung ever calls `request`** (counting broker); `register()` is called only from `notRegistered` and never at teardown; the previous voice is recorded before ours is written; the probe presses `describe item in voiceover cursor` and bookmarks before pressing; the probe runs after suppression in a silent session |
| `Tests/VoiceOverBridgeDomainTests/Entities/SetupRungTests.swift` | unit — **new** | every rung renders one sentence carrying its name, the cause and the agent action |
| `Tests/VoiceOverBridgeDomainTests/Entities/ReaderConditionTests.swift` | unit — amended | the new case; every recovery that names a restart names both halves of the command |
| `Tests/VoiceOverBridgeAdaptersTests/PluginKitProviderLifecycleTests.swift` | unit — amended | `register()` runs `lsregister -f` **then** `pluginkit -a`, in that order, with the resolved paths; it polls rather than trusting the return, and succeeds on a state that only appears on a later poll; it fails by name after the window; with no paths it fails by name **carrying both commands** and runs nothing |
| `Tests/VoiceOverBridgeAdaptersTests/VoiceOverLivenessTests.swift` | unit — amended | `activate()` runs `/usr/bin/open -a VoiceOver` and swallows a failure to launch |
| `Tests/VoiceOverBridgeAdaptersTests/CaptureBundleTests.swift` | unit — **new** | the appex path is derived from the app path; the names are the ones `build.sh` reads |
| `Tests/VoiceOverBridgeAdaptersTests/WiringTests.swift` | unit — amended | the bundle paths resolve to the conventional `build/` directory, and to nil when neither exists |
| `Tests/Fakes/ReaderLiveness.swift`, `Tests/Fakes/ProviderLifecycle.swift` | fakes — amended | `activate()` and `register()`, each **counted** and each able to refuse, because when they are called is as much of this entry as what they do |
| `Tests/Fakes/Support/ReaderEdge.swift` | scaffolding — amended | a **healthy machine** by default: the fake script runner answers the capture probe by writing one `synthesize` line to the test's own capture path, so the real `ContainerFileSpeechSource` tails it into the buffer and every existing integration handshake still passes. The IO is in the Support closure, never in the fake. |
| `Tests/Integration/SessionRoundTripTests.swift` | integration — amended | a handshake climbs the ladder over the real stack and the real tailer; a machine with a rung broken refuses **in both modes** with the rung's name; the counting-broker scenario keeps its claim unchanged |
| `Tests/ConformanceBridge/main.swift` | scaffolding — **unchanged** | its scripted fake reader already answers `describe item in voiceover cursor`, which is the probe. Recorded because "no change" is the reviewable claim, and because it is the one place a change would have been invisible until CI. |

### 3.4 Documents

| File | Change |
|---|---|
| `bridges/voiceover/AGENTS.md` | A new section: the handshake climbs, what each rung costs, the session-vs-machine-state rule, and the `killall && open` pair. The 13.6 asymmetry paragraph is amended for §2.7 |
| `bridges/voiceover/README.md` | The manual registration commands are still correct and are now what the bridge does for you; the deregistration recipe stays, because the live checklist needs it |
| `Entities/Documents/common.md` | One paragraph: a session is set up at connect, so a `speech: []` is now much likelier to mean the reader said nothing — and what a named connect failure means |
| `bridges/voiceover/build.sh` | Reads `captureAppName` / `captureExtensionName` out of `CaptureBundle.swift` with `sed`, as it already reads the version |
| `ROADMAP.md` | 13.20 → **Done**, and the next-free-number line |

## 4. The live checklist this earns

In the PR body as checkboxes, driven against the maintainer's real VoiceOver.

1. **From a DEREGISTERED voice.** `pluginkit -r` the appex, confirm
   `pluginkit -m -p com.apple.AudioUnit-Speech -v` no longer lists it, then
   `connect_reader`. The handshake registers it (verify with `pluginkit -m`
   afterwards) and **fails at rung 5**, naming the reader restart and giving
   `killall VoiceOver && open -a VoiceOver`.
2. **After the restart.** Run that command, `connect_reader` again: it succeeds,
   and a `press_gesture` + `get_speech` round trip returns real speech.
3. **A grant withheld.** With Accessibility revoked, `connect_reader` fails by
   name at rung 1, tells the agent to have the human grant it and connect again,
   and **no consent dialog appears anywhere on the machine**.
4. **Disconnect, then reconnect.** `disconnect_reader` then `connect_reader`:
   the voice is still registered (the bridge deregistered nothing), the user's
   own voice was restored in between, and the second handshake succeeds.
5. **The reader not running.** Quit VoiceOver, `connect_reader`: the handshake
   activates it and succeeds.
6. **The ordinary case costs nothing visible.** On a healthy machine a silent
   `connect_reader` still completes promptly, the probe is **inaudible**, and the
   VoiceOver cursor has not moved.
7. `bash scripts/voiceover_channels.sh` still runs — it drives the reader
   directly and opens no session, so §2.2's loss does not reach it.

## 5. Honest limits

- **The rung the bridge cannot climb is `registered` → `published`.** The system
  publishes a newly registered voice only after **VoiceOver restarts**, and a
  handshake may not restart a blind person's screen reader. So rung 3 succeeds,
  rung 5 fails, and the failure says exactly that: what was done, that the
  restart is the one remaining action, and the `killall VoiceOver && open -a
  VoiceOver` command to do it with. This is the honest shape of the limit — the
  bridge does everything it may and names the one thing it may not.
- **Rung 5 proves the machine, not the page.** An utterance arriving proves the
  capture path end to end; it proves nothing about whether the application under
  test is responsive. `ReaderLiveness`'s header already carries that lesson from
  the other end (2026-08-30, a wedged Finder that looked exactly like a dead
  reader), and this entry does not narrow it.
- **A machine with no Accessibility grant can no longer open a session at all**
  (§2.2). Stated here as well as there because it is the one capability this
  entry takes away.
- **The probe is one command's worth of reader time**, added to every handshake.
  On a healthy machine that is a subprocess and one poll interval; nothing has
  measured it under load, and 13.18's unfinished question about how much of a
  grace window the pipe consumes applies to this wait as much as to any other.
- **`cannotTell` is treated as a stop.** The automation grant can answer
  "cannot tell" for reasons that are not permissions, and rung 1 stops on
  anything that is not `granted`. Rung 2 is what would have distinguished them,
  and it runs after — so the message says which read was inconclusive rather
  than asserting the grant is missing.

## 6. Open questions

1. **How does a human grant these?** Not decided, and deliberately not this
   entry's. The VoiceOver Automation toggle a person can reach themselves;
   Accessibility is unclear. A button in the bridge is the obvious candidate and
   has a real problem: TCC attributes a grant to the process it holds
   **responsible**, measured on 2026-08-31 to be `/usr/libexec/sshd-keygen-wrapper`
   rather than the bridge or the agent, so a button may grant something other
   than what needs it. That investigation is its own board entry, and it needs a
   measurement before it needs a design.
2. **Should the bridge ever restart the reader?** Never unattended. With a human
   declared present (`attended`) and having said yes to a question this bridge
   already knows how to ask (`askUser`, 13.10), it is at least arguable. Not
   proposed here.
3. **Should the ladder be re-climbable mid-session?** A `getState`-shaped command
   that re-runs the rungs would let a long session notice a voice that went away.
   This reader announces no `state` capability, so there is nowhere to put it
   today.

## 7. Amendments made while implementing (2026-09-01), each with its why

1. **`ReaderEdgeSetup` owns the marker channel too**, which §3.1 did not say. The
   suppression has to be in force *before* the capture proof presses anything, or
   the proof is audible in the one mode whose promise is that a human hears
   nothing — so `openSilenceChannel` sits between rungs 4 and 5 inside this
   controller rather than staying behind in `HelloHandler`. The whole of
   `establishReaderEdge` therefore moved rather than half of it, which also
   leaves the handler with one statement where it had a private method.

2. **The capture proof's utterance stays in the session's buffer, at index 1.**
   Not named in the spec, and it is the entry's most visible consequence: a
   session's own speech now starts at 2, `getLastSpeech` immediately after
   connect answers with the cursor description, and the transcript opens with it.
   Considered and declined: proving capture into a throwaway buffer and starting
   the real one afterwards. It would need a stop/start of the speech source and
   would reintroduce the 2026-08-30 attach race the tailer's header exists to
   prevent — and it would mean the one utterance that proves the feed is the one
   utterance the record does not contain. The buffer is what the reader SAID, not
   what the agent asked for. Disclosed in `common.md` and in the tests, which say
   it out loud rather than reading from a fresh mark.

3. **`VoiceOverLiveness` gained a second seam** (`ProcessRunner`) rather than
   sending an AppleScript. Starting an application is not an AppleScript question,
   and the channel this class asks over is by definition the one that is not
   answering when `activate()` is called. `VoiceOverAdapterFactory` therefore
   takes a `ProcessRunner` too — one new constructor argument, no new decision.

4. **`CaptureBundle.swift` is a new file the layout did not have**, and `build.sh`
   reads the two names out of it with `sed`. §2.9 called for Wiring to resolve the
   paths; what it left implicit is that *something* has to know the bundle is
   called `VoiceOverCaptureSpike.app` and its extension `CaptureVoice.appex`, and
   a second spelling in Wiring would drift from the shell script's the first time
   anybody renamed anything — with the failure surfacing as an `lsregister -f`
   that registers nothing and reports success. This is `BridgeVersion.swift`'s
   pattern, and `CaptureBundleTests` asserts the declarations still have the shape
   the `sed` expression matches.

5. **`FakeAppleScriptRunner` gained `scriptedAnswers` and `onScript`**, and
   `FakeProcessRunner` gained `beforeRun`. All three exist because the handshake
   now sends two different scripts down one seam and polls a machine that
   changes while it is polled — a fake that answered one thing forever could not
   tell a poll that waits from one that got lucky, and one that answered every
   script identically would report a dead reader on every healthy machine.

6. **Two integration scenarios changed how they are SET UP without weakening what
   they assert.** The permission-lever scenarios began on a machine with nothing
   granted, which rung 1 now refuses. They hold the grant at the handshake and
   revoke it immediately after — something macOS itself does live — and the claim
   they can now make is strictly stronger: *the handshake reads both grants and
   requests neither*.

7. **Four `ReaderCondition` recoveries were rewritten, not just extended.** They
   told a human to re-register the extension; the bridge does that itself now, so
   the sentence would have been sending somebody to redo something already done.
   Each now says what the bridge already tried and names the one action left. In
   the same pass every restart became `readerRestartCommand` — a `killall` with
   no `open` beside it is a sentence somebody could follow into having no screen
   reader.

8. **`HelloTests`' `synth` test lost half its subject, and says so.** The field
   could report somebody else's voice only because a live session was established
   on a machine where ours could not be selected; that session is now refused, so
   the branch is unreachable through a successful handshake. The branch stays —
   the field is ASKED rather than asserted, and a store that changed underneath
   must not be able to make it lie — and the test asserts what is left, which is
   that asking is idempotent across two sessions.
