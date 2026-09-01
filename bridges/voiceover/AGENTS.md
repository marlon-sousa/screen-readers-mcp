# bridges/voiceover/ — the macOS VoiceOver bridge

The manual for this package. The repo-wide manual is the root
[`AGENTS.md`](../../AGENTS.md) — the four-role vocabulary (port / controller /
entity / adapter), the hard invariants, the workflow and the task list all live
there and are not repeated here. This file is what is specific to the Swift half:
how the repo's rules render in Swift, what the module graph enforces, and the
macOS traps that have already cost time.

`bridges/voiceover/` is one Swift `.app` ([spec
0043](../../specs/0043-the-voiceover-bridge-is-one-swift-bundle.md), Decided).
Its class-by-class layout is [spec
0046](../../specs/0046-the-voiceover-bridge-class-by-class.md); the board entries
are lane 3 in [`ROADMAP.md`](../../ROADMAP.md). What each directory holds, how to
build it, and how to register and remove the capture voice are in
[`README.md`](README.md) beside this file — that is the document for *using* this
bridge, and this is the document for *changing* it.

## It is one bundle and FIVE elements, not one program

Spec 0046 part 3 names them, and the decomposition is wrong if it pretends
otherwise: the speech provider (its own `.appex` process, **and** dlopened into
every client that speaks, VoiceOver included), provider registration, the bridge
session (a background thread of the app), the input path (posting system events,
needing an Accessibility grant), and the control UI (AppKit's main thread).

Two consequences bind every change here:

- **`CaptureVoice` depends on nothing of ours, and that is a hard rule.** Every
  byte it carries runs inside the user's screen reader — the same argument that
  makes the shared wire module stdlib-only, reached from the other direction. It
  never imports the domain, the wire binding, or anything that would grow a
  dependency later. Its tests keep their own `Fakes/` for the same reason.
- **The session runs on a background thread; AppKit owns the main one.** Every UI
  update the session causes marshals to the main thread, and no call the UI makes
  may block it. This is the macOS rendering of the NVDA main-thread rule, and it
  is the same class of bug.

## The module graph is the architecture test

`Package.swift`'s dependency edges are load-bearing, not descriptive: a domain
file that imports `VoiceOverBridgeAdapters` **does not compile**. Lane 1 enforces
the same rule by convention and review; Swift enforces it at build time and costs
nothing for the privilege, so `swift test` (which builds every target) is also
the architecture check.

**`Package.swift` is not the build.** SwiftPM cannot emit `.app` or `.appex`
bundles, so `build.sh` assembles them from swiftc output. A change to what ships
is a change to `build.sh`; a change to what compiles and is tested is a change to
the manifest. Both, usually.

## Swift renderings of the repo's rules

- **One class per file, and no re-export facades.** The file half holds. The
  import half cannot: Swift imports modules, not files, so "every import names its
  file" is not a property Swift offers. The compensating rule is that **no file
  may exist whose purpose is a `typealias` re-export** — and for the wire binding
  that rule is enforced, by `scripts/drift.py --swift`.
- **Fakes conform to their port**, one file per fake, mirroring the port's file.
  A fake that forgets a method fails to **compile**, where Python's ABC fails at
  construction: strictly stronger, same guarantee.
- **A port that can fail says `throws`; the session guards exactly those.** Lane 1
  wraps every teardown step in a blanket guard because a Python port that raises
  looks like one that does not. Here the claim is checkable, so it is made in the
  type: `SessionSignals`' cues throw (a cue reaches an audio device that may be
  gone, and a courtesy is never worth a session), while `Transcript` and
  `MessageChannel.close` promise that they swallow their own IO failures. A
  `try/catch` around one of those would be catching nothing — if you add one, one
  of the two is wrong.
- **Ports are protocols, and binding is chosen per call site.** Separating a
  component costs nothing at run time; only *binding* can. The one place that
  constrains is the capture voice's render block, which must not allocate, must
  not block on a lock, and must not bind through an existential — it captures a
  concrete `final` `AudioRing` for exactly that reason. Everywhere else a port is
  free to be a protocol.

## The capability set grows ONE ENTRY AT A TIME, and at 13.11 it is COMPLETE

`hello` announces what this build actually implements, and nothing else.
`Registry.capabilities` was empty at 13.4, `[speech]` at 13.5, `[speech,
gestures]` at 13.7, `[speech, gestures, typing]` at 13.8, `[speech, gestures,
typing, focus]` at 13.9, `[speech, gestures, typing, focus, interact]` at 13.10
and all six at 13.11, and each entry added its own alongside the handlers that
serve it.

**Six of the contract's eleven, and the five that are missing are missing from
the READER.** Braille, state, config, log and document are not unimplemented
here: VoiceOver exposes no readable braille buffer, keeps no diagnostic log,
answers no query for any of its 45 toggles, and offers no way to ask for a
document as flat lines. So the gate is doing exactly what it exists for, and this
is the first bridge in the repo where that is visible — the NVDA one announces
every group, which is why its conformance run has no unannounced capability to
exercise and this one's does.

Announcing a capability before the entry that implements it produces the one
failure the capability gate exists to prevent: a tool the agent can see, call,
and get nothing from. The converse costs too, and it is why `speech` landed with
13.5 rather than being held back: a capture feed the server gates away is a tool
nobody can call.

The same rule is why `VoiceOverAdapterFactory` refused a silent session until
13.6, and **13.6 deleted that refusal and its named test in the commit that made
the promise keepable**, exactly as this file required. **13.10 did it a second
time**, to the same pattern: `HumanWarning` refused a `pressGesture`'s or a
`typeText`'s `announce` in a silent session, because that is the one mode where
it is the human's only warning and this bridge does not half-keep a promise about
somebody's ears. The refusal and its named test went in the commit that gave the
bridge a channel to speak on.

What replaced 13.6's refusal is not nothing: **it MOVED to the handshake**, which
is the only place that can ask whether this machine can actually deliver
silence. `silent` is not a
preference, it is a promise about a human's ears, so a silent handshake on a
machine where the capture voice is not registered, not published, or would not
stick is refused **by named condition, with its recovery** — never established
and quietly turned into something else.

**A LIVE handshake in the same state was not refused until 13.20**, and the
asymmetry was deliberate rather than squeamish: writing the voice applies live,
in both directions (spec 0047, finding 17), so a live session that starts
unhealthy can become healthy while it runs. Silence promised at the handshake has
to hold from the handshake. **That reasoning still holds and no longer decides
the question** — the handshake now climbs the ladder and refuses in BOTH modes,
for a promise neither mode is exempt from. See "The handshake CLIMBS the ladder"
above.

## The handshake CLIMBS the ladder, and it never restarts the reader

`connect_reader` makes its own setup (spec 0050, board entry 13.20). `hello` used
to REPORT where `ProviderState` had stopped — refusing a silent session by named
condition and letting a live one through with a note — and what that produced was
a session answering `speech: []`, which is indistinguishable from "the reader
said nothing" and is the one answer `ReaderCondition`'s header says a bridge on
this route must never give. It cost an hour of 13.19's live checklist on
2026-08-31, and the trigger is our own build: `build.sh` begins `rm -rf build`,
so the system forgets the extension every time this bridge is rebuilt.

`ReaderEdgeSetup` now runs five rungs, all eager, in this order, each failing by
name with what the AGENT must do:

| # | Rung | What it does | Costs |
|---|---|---|---|
| 1 | `permissions` | READS Accessibility and Automation-of-VoiceOver | one subprocess (the automation grant is a fact about the channel) |
| 2 | `readerRunning` | asks the reader its name; if silent, `open -a VoiceOver` and asks again | one subprocess, usually one |
| 3 | `registration` | `lsregister -f` then `pluginkit -a`, **only** from `notRegistered`, confirmed by polling | nothing on a healthy machine |
| 4 | `voiceSelection` | records the user's voice, writes ours, confirms | unchanged from 13.6 |
| 5 | `captureProof` | presses `describe item in voiceover cursor` and requires the utterance to arrive | one command and one poll interval |

Five rules bind anyone editing this.

**IT IS FATAL IN BOTH MODES, AND THAT IS NOT 13.6's ASYMMETRY REVERSED.** 13.6's
rule is about a promise concerning a human's EARS, which only `silent` makes, and
it stands where it is made. This is a different promise — that `getSpeech` means
anything at all — and a live session announces the `speech` capability just as
loudly. "A live session may become healthy while it runs" was a reasonable thing
to say about a state nobody was repairing and is an unreasonable one about a
state the handshake has just tried to repair and failed.

**THE HANDSHAKE READS GRANTS AND NEVER REQUESTS ONE.** `PermissionBroker.request`
still has exactly TWO callers, both command handlers about to post a system
event, both through `AccessibilityGrant` — so 13.8's lever survives 13.20 word
for word, and no sweep was needed. A handshake that raised a consent dialog would
be a handshake that hangs, on a machine where nobody may be looking at the
screen. **What it cost** is stated rather than hidden: a machine that has never
granted Accessibility can no longer open a session at all, which is the property
`scripts/voiceover_channels.sh` was written to exercise. That script still runs —
it drives the reader directly and opens no session.

**SESSION STATE IS RESTORED AT TEARDOWN; MACHINE STATE IS NOT.** The voice
SELECTION is session state and goes back on every teardown path (hard invariant
3, unchanged). The REGISTRATION is machine state and stays. There is deliberately
no `unregister()` and nothing at teardown may be paired with `register()`,
however much the symmetry appeals: undoing it recreates the exact bug this entry
fixes, and the accept loop is serial today but will not always be — one client's
disconnect must never deregister the voice under another.

**THE RUNG THIS BRIDGE CANNOT CLIMB IS `registered` → `published`**, because the
system publishes a newly registered voice only after VoiceOver RESTARTS and no
handshake may restart a blind person's screen reader. So rung 3 succeeds, rung 5
fails, and the failure names the restart as the remaining action. **Every
sentence in this repo that names a restart spells it as a pair** —
`killall VoiceOver && open -a VoiceOver`, through `readerRestartCommand`, because
`killall` on its own was MEASURED on 2026-08-31 not to relaunch the reader and
would leave somebody with no screen reader at all.

**THE PROOF'S UTTERANCE IS REAL SPEECH AND IT STAYS IN THE BUFFER.** Index 1 of
every session holds what the reader said when it was asked to describe its
cursor; a session's own speech starts at 2. Hiding it would mean the buffer is
not the record of what the reader said that it claims to be — and the tests say
so out loud rather than reading from a fresh mark, because "everything this
session captured" is what several of them are about. The probe is
`describe item in voiceover cursor` because the guidance already calls it the
safe one: it describes and MOVES NOTHING. It is pressed **after** suppression is
in force, so in a silent session it is inaudible.

## Silence is a LEASE, and nothing may come to depend on a teardown path

The single most important rule in this bridge, and the macOS form of hard
invariant 3 (spec 0046, and `protocol.md` §6, which asks a bridge to arrange its
interception so that losing the bridge ITSELF lifts it).

NVDA gets that free — it holds extension-point handlers weakly, so killing the
add-on drops the speech filter with it. Here the interception is a **file on
disk** read by a process the system owns, which would go on reading it forever.
So the marker **expires**: the session rewrites it while it lives, and the
extension treats a marker older than `MarkerFileCaptureModeSource.lease` as
pass-through. A bridge that is `SIGKILL`ed un-mutes the machine **by doing
nothing at all**.

Three consequences bind anyone editing this:

- **The `defer` stays, and nothing may depend on it.** `Session.teardown`
  releases the marker and restores the user's voice because that makes the
  ordinary case immediate; a SIGKILL, a panic and a power cut all skip it, and
  those are the cases the invariant is about.
- **The renewal is driven by the session LOOP, not by a timer of the adapter's
  own.** That is the safer coupling: silence then depends on the liveness of the
  very loop that can lift it, so a session thread wedged inside a handler gives
  the machine back instead of holding it mute with every watchdog still ticking.
  The cost is stated in `MarkerFileSilenceControl`'s header — a single command
  blocking longer than the lease un-mutes early, which is the safe direction.
- **The default is never silence.** Absence, an unreadable date, contents that do
  not parse, a question that cannot be answered: the answer is "speak", on both
  sides of the file.

## The voice is the user's, and it is put back

The bridge reads `VoiceOverDefaultVoiceSelections` in the **system speech**
domain (`com.apple.SpeakSelection`, never VoiceOver's own — spec 0047, findings
10 and 16), records the previous `voiceId` verbatim, writes ours, and writes
theirs back on every teardown path. Three things must survive any edit here:

- **Preserve plist types.** A value written as a string where a real is expected
  is silently rejected, and VoiceOver then overwrites the key with its own choice
  — so the write appears to have done nothing. `scripts/voiceover_voice.py` is
  the same mechanism as a tool and is the instrument the finding was made with.
- **Match our published voice by SUFFIX, never by the identifier the unit
  declared.** The system prefixes the extension's bundle id, so the published
  string never equals what the audio unit said.
- **A previous voice that is OURS is not the user's.** A session that died
  without restoring leaves the reader on the capture voice; recording that as
  "the user's own" would restore our voice at teardown and hand the extension
  itself as the pass-through voice, which is infinite recursion. That is Rule 0's
  first caveat and it is asserted in three places.

## A gesture on this reader is a COMMAND NAME **or a keystroke**, and the id decides

Three rules. The second is the finding that unblocked board entry 13.7; the
third is 13.17, which is where this section stopped being one rule; and 13.19 put
a **source prefix** in front of all of it.

**A command name is an English phrase**, from VoiceOver's own
`SCRStringsToCommandsMap` vocabulary — 415 entries on macOS 15.0, phrases like
`go to desktop` and `mute sound toggle`. There is no table of them in this
repo and there must not be one: the reader does its own dispatch and answers an
unknown name with `Command does not exist (6)`, which is a better check than any
copy that goes stale every release. **A keystroke is `+`-joined, modifiers first
and the key last** — `command+l`, `control+option+space` — and
`CommandVocabulary` tells the two apart by **the space rule**: a separator counts
as keystroke notation only in an id with no spaces at all. Every real command
name that carries one carries spaces too (`toggle single-key quick nav on or
off`), and no command in the 415 is a bare `+`-joined token. The same rule
decides the hyphen case, which is why the rule is one rule and not two.

**`kb:` OUTRANKS ALL OF THAT, and it is what makes a lone key expressible.** A
source prefix — everything up to and including the first `:`, lane 1's own rule
in `bare_key_name` — says the id is a keystroke whatever shape it has, so `kb:h`
is the letter key and `h` is a command name. It exists because 13.17's `+` rule
left an ordinary user's commonest act unreachable: with single-key Quick Nav on
you press `h` to move by heading, and there was no notation for it (spec 0049).
Three consequences worth knowing before you touch this: `kb(laptop):` and any
other source are **refused by name**, because a wrong source must not fall
through to being read as a phrase; the prefix is **not second-guessed**, so
`kb:go to desktop` is a malformed keystroke and not a command name; and
`Gesture.described` **emits the prefix only where dropping it would change the
meaning** — `kb:h` keeps it, `command+l` does not — so a transcript line is
always replayable and still spells a chord the way lane 1 documents it.

**EVERY KEY NAME THIS BRIDGE ACCEPTS NAMES THE SAME PHYSICAL KEY ON NVDA**, and
that is a rule to keep rather than a coincidence to erode. The names in
`Keystroke.NamedKey` were read out of `../nvda/source/vkCodes.py` (`byCode`,
lower-cased into `byName` for lookup) rather than recalled, and the Mac's own
spellings are synonyms where they name the same key (`return` for `enter`, `left`
for `leftArrow`, `alt` for `option`). Where a name would mean a *different* key
it is **refused by name** instead: `delete` is this machine's erases-backwards
key and Windows' erases-forwards one, so it names `backspace`, `forwardDelete`
and the reader's own `delete key` and presses nothing. The line is that **a name
that differs with no hazard is tolerated and a name that differs with a hazard is
refused** — and the one key with no shared spelling anywhere is forward delete,
which NVDA calls `delete`. What is deliberately *not* copied from lane 1 is
`press_order`'s modifier hoisting: it exists to undo NVDA's own alphabetical
normalizer, there is no such normalizer here, and `l+command` stays a named
failure rather than being quietly reordered.

**`VO-D` is still refused, and no feature retires that.** `VO` is whatever the
person has bound their VoiceOver modifier to — Control-Option, or Caps Lock, or
both — so pressing it would mean guessing at somebody's own configuration and
pressing the wrong keys with total confidence. The refusal names both
alternatives: the reader's command name, or `control+option+d` if those literal
keys were meant.

**Prefer the command name wherever one exists**, and the reason is the grant: a
command name is an AppleEvent and costs nothing, a keystroke is a `CGEvent` and
costs Accessibility. `return key` and `command+enter` are not interchangeable
just because both press a key. That is also why **an UNPREFIXED lone key stays a
command name**: the vocabulary's 30 `… key` commands cost nothing, and routing a
bare `return` through the event path would spend the grant for a keypress that
never needed it. `kb:enter` is how a session says it meant the key itself, and it
pays for saying so — which is the whole shape of 13.8's lever surviving 13.19
intact, word for word.

**Do NOT build a chord out of the reader's modifier commands.** The vocabulary
carries 30 commands whose name ends in `key` — `tab key`, `return key`, the four
arrows, `f1 key` through `f12 key`, `delete key`, `forward delete key`, `fn key`
— plus modifiers in two flavours, momentary (`command key`, `shift key`, …) and
sticky (`toggle command key`, …). **Measured 2026-08-30 on macOS 15.0: they do
not compose.** Four runs — sticky and momentary, option and command — each
followed by `delete key` into a scratch document removed exactly one character,
the same as the no-modifier control, where Option-Delete would have taken a word
and Command-Delete the line. The modifier command *succeeds* and changes nothing
about the key that follows it, which is the worst shape a negative can have, so
it is written down here and re-runnable as `bash scripts/voiceover_modifiers.sh`.
Independently of that, the table has **no letter keys at all**, so literal text
can never come out of it — which is why `typeText` synthesizes events and pays
for the grant.

**And that measurement was read too widely for four entries, which is the
cautionary half of this section.** "The modifiers do not compose" is true, and it
was generalised into "a chord is not expressible on this reader" and then into a
sentence in the shipped guidance document telling an agent that a chord needs
`type_text`'s route — a route that cannot press one either. A true statement
about one channel became a false statement about the bridge, it read like a
platform limit, and so nobody looked for the missing feature behind it while a
blind user's commonest act stayed unreachable. Spec 0048 §1.1 keeps the record.

## Pressing a chord: the layout is the hard part, and there is no table

`CGKeystrokePresser` holds every decision — key to keycode, modifiers to flags,
down then up — over two seams: `KeyboardLayout` (which physical key produces a
character **on the layout that is active now**) and `EventPoster`. Four rules
bind anyone editing it.

**There is no keycode table for characters in this repository, and there must not
be one.** A `CGEvent` carries a virtual keycode, and which one produces `l`
depends on the active layout; the maintainer's is Brazilian. A hard-coded ANSI
table would compile, pass every test its author wrote, read well in review, and
**press the wrong key on his machine** — the exact shape of failure this lane
keeps paying for. So `CurrentKeyboardLayout` asks
`TISCopyCurrentKeyboardInputSource` and `UCKeyTranslate`, building the reverse map
backwards because macOS only ever answers the forward question.

**The map is cached by the input source's id, and the id is re-read on every
lookup.** That is one cheap call against 256 `UCKeyTranslate` calls, and it means
somebody who switches layouts mid-session gets the right keys on the very next
press — with no notification observer to register, forget to remove, or receive
on the wrong thread.

**An unreachable character is a NAMED FAILURE that posts nothing.** "This layout
has no key that produces `ç`" is an answer an agent can act on; pressing
something else is not, and a chord that quietly did the wrong thing is the worst
failure available on an edge nobody can watch. Measured on the maintainer's
`com.apple.keylayout.Brazilian-Pro`, 2026-08-31: 110 characters mapped, `ç` among
the ones that are not, and `$` reported on the **shifted layer** of the key that
carries `4`.

**The modifiers are PRESSED AND RELEASED, not merely set as flags — and that is
the bug this entry produced.** Flags on the key event are what menu shortcuts
match, and the first `command+l` through this bridge opened Safari's location bar
on the first try. It also left **Command held down on the maintainer's keyboard**:
`CGEventSource.flagsState` said so, nothing else did, every keystroke afterwards
was a chord, and the symptom that surfaced was `typeText` reporting `typed: 11`
into an address bar the reader read back as empty. So the sequence is what a real
keyboard produces — a `flagsChanged` per modifier building up, the key down and
up, then transitions unwinding to `[]` — and **the release is in a `defer`, so it
runs even when the press failed**. Its own failures are swallowed: leaving
somebody's Command key down is worse than any error this class could return. Spec
0048 §2.5, reversed with the measurement it asked for.

**The seam reports which LAYER the character sits on, and that is a decision
rather than a detail.** Digits are unshifted here and on an American keyboard and
**shifted** on a French AZERTY one, so a seam answering only a keycode would make
`command+4` a named failure on a machine where the person presses it daily.
Reporting the layer keeps the decision — a shifted layer means an added
`.maskShift` — above the seam, where it is an ordinary unit test. Named keys
(`return`, `f5`, the arrows) are layout-independent constants and skip the
translation entirely; their table is the one table the presser is allowed to
carry, because a physical position is not a layout.

Re-runnable as `bash scripts/voiceover_chords.sh`, which prints what this
machine's layout answers and then presses a chord into a scratch document it
closes without saving. It needs the Accessibility grant, which is why it is a
separate script from `voiceover_modifiers.sh` — the same split as
`voiceover_keyboard.sh`, for the same reason.

**`perform command` is addressed to the `commander object`, never to
`application "VoiceOver"`.** `VoiceOver.sdef` in this directory is the authority:
the `application` class responds to `output`, `open`, `close menu` and `quit`,
and not to `perform command`; the commander does, reached through the
application's read-only `commander` property. Sending a command to an object that
does not handle it fails **before any name lookup**, which is why spec 0047
measured error 4 for a valid name and a bogus one alike and recorded the channel
as dead. It was not: spec 0041 and spec 0047 disagreed because their scripts
differed. Addressed correctly, a valid name succeeds and a bogus one returns 6.

A "simplification" back to the application target compiles, reads better, and
restores a state in which every gesture fails identically with nothing saying
why — so `VoiceOverGestureSenderTests` asserts the target as a **negative** as
well as a positive.

## Typing is the OTHER half of input, and it costs the grant

Two commands, three ports, two capabilities, and the separation is the lane's one
design lever rather than tidiness. A **command name** through `pressGesture` is
an AppleEvent to the reader; `typeText` and a **keystroke** through
`pressGesture` both synthesize system input events and need **Accessibility**
(`kTCCServiceAccessibility`). Windows has no equivalent gate, so lane 1 has no
analogue and there is nothing to copy here.

**The line falls between NOTATIONS, not between commands, and 13.17 is where it
moved.** Until then it fell between the two commands, and the sentence below said
"only presses commands". It now says "presses only the reader's COMMAND NAMES",
which is the property that was ever worth having — and the narrowing is written
into every place that states it rather than left for somebody to discover.

**THE TWO GRANTS ARE READ BY DIFFERENT MEANS, AND 13.11 HAD TO FIX THAT.**
Accessibility is a fact about THIS PROCESS, which posts its own `CGEvent`s, so
`AXIsProcessTrusted` answers about the thing that acts. Automation is a fact
about a CHANNEL: this bridge never sends an AppleEvent itself — every one leaves
an `osascript` subprocess, and macOS attributes a subprocess's events to whatever
process it holds RESPONSIBLE for it. So an API that answers about the calling
binary answers about a process that sends nothing.

Measured 2026-08-30, seconds apart, on the maintainer's machine:
`AEDeterminePermissionToAutomateTarget` returned **-1744** from an unsigned
launcher — reported as `notGranted` — while that same process's `osascript` had
just driven the reader through a whole MCP session. The grant was held all along,
by the responsible process: VS Code was launched over SSH, Claude Code from VS
Code, and the bridge from Claude Code, so TCC consulted
`/usr/libexec/sshd-keygen-wrapper`. `TCCPermissionBroker` now asks the channel
and reads the NUMBER — `-1743` is the missing grant, a reply is the grant, and
anything else is `cannotTell` rather than a guess, because "the reader is not
running" is not evidence about a permission.

**THE ACCESSIBILITY GRANT IS REQUESTED FROM TWO PLACES, BOTH COMMAND HANDLERS,
BOTH THROUGH `AccessibilityGrant`:** `TypeTextHandler` on a `typeText` (13.8),
and `PressGestureHandler` on a batch containing a **keystroke** (13.17). Not at
construction, not in `Wiring`, not in `VoiceOverAdapterFactory`, not in
`scripts/doctor.py`, not in a probe, and **not in a test**. That is what makes

> a session that presses only the reader's COMMAND NAMES and reads speech never
> triggers an Accessibility request

a *checkable statement about this bridge* rather than an intention, and the check
is a round trip in `Tests/Integration/SessionRoundTripTests.swift` that drives a
handshake, a command-name gesture, a speech read, an `announce` and an `askUser`
past a counting broker, asserts it was asked nothing at all, and only then sends
the two commands that may ask. `Wiring` **constructs** `TCCPermissionBroker` at
startup and never calls it: constructing asks nobody anything, and only `request`
raises a dialog.

**The shared check is a file because the second caller arrived**, which is the
rule `HumanWarning` and `Observation` were both created by. Two hand-written
copies of a permission check would come to differ the first time one was
reworded, and what they would differ about is whether somebody's machine raises a
consent dialog. **If you add a THIRD caller, ask first whether the thing you are
adding is a command that moves the machine.** 13.9 wanted this grant for focus
and did not take it — it reads whether the grant is held through an adapter seam
that cannot request anything — and that is the shape to copy.

**No test may touch the real grant or post a real event.** The real broker's
`request` raises a system consent dialog and leaves this process on a list that
**stays granted**, with no undo; a real `CGEvent` types into whatever window the
developer has in front of them at that moment. Both are injected into
`VoiceOverAdapterFactory` for exactly that reason, and
`Tests/Fakes/Support/ReaderEdge.swift` hands every test fakes — the same guarantee
it already gives for the provider lifecycle, which writes the voice the developer
hears.

**The target application rewrites what was typed, and the same holds for a
chord.** Two lines sent to TextEdit came back autocapitalized (spec 0041). "Send
this keystroke" is not "this text arrives" — nor "this chord happened", since an
application that ignores `command+f` is indistinguishable from one that acted on
it — and **nothing in this bridge, its tests or its documentation may compare
typed input with observed output as though they were the same string**.
Autocapitalization is only the measured instance; autocorrect, smart quotes and an
application's own filtering are the same class, and they are per-application and
per-user settings no bridge can see or turn off. A check that needs to know what
arrived asks the application, or the reader, and compares *that*.
`AccessibilityTextTyper`'s header carries this where whoever writes the comparison
will read it, and `bash scripts/voiceover_keyboard.sh` is the re-runnable
instrument — **a separate script from `voiceover_channels.sh` on purpose**, because
the channels probe runs on a machine that has never granted Accessibility and the
keyboard one cannot.

**The text is never logged, and `typed` is a length.** protocol.md §5 says
`typeText` is exactly how a secret is entered. The obligation lands on the
transcript: `TYPE length=<n>`, never the words, because a transcript is a file a
human reads afterwards and a password in it is a password on disk. `typed` counts
**unicode scalars**, which is the number lane 1's `len` and the server's
conformance rune count both mean; Swift's `String.count` counts grapheme clusters
and would disagree silently on a decomposed character.

**`graceMs` defaults to 0 here and 100 for a gesture**, and that is not an
oversight: with "speak typed characters" on, typing emits one utterance per
character and none of them is worth waiting for.

## The human channel goes AROUND the reader, which is why it works in silence

`announce`, `askUser` and `waitForUserReply` are the `interact` capability, and
all three rest on one fact: **the `Announcer` speaks with the bridge's own
synthesizer, outside VoiceOver entirely.** On this platform the suppression is
rendered inside the capture voice, so anything said *through* the reader is
exactly what the person cannot hear — and going around it is a cleaner bypass
than NVDA's, where the same claim rests on the interception being a filter in
front of a synth that is still loaded. It is also why `pressGesture`'s and
`typeText`'s `announce` field is honourable here at all: until 13.10 it was
refused in a silent session, because there was nothing to say it on.

Four rules bind anyone editing this.

**Our own capture voice is excluded by SUFFIX, and that is not a nicety.** An
announcement rendered by the extension that is rendering silence would be silence
talking to itself — an `announce` that returns `ok` while the room stays quiet, in
the one mode where it is the human's only channel. The match is by suffix and
never by equality, because the system publishes our voice as the extension's
bundle id followed by the one the audio unit declared (spec 0041 A1, spec 0047
finding 17). It is the same constant `PluginKitProviderLifecycle` matches ours by,
read a second time rather than copied.

**Asking is PRESENTED and POLLED, never awaited.** `askUser` and
`waitForUserReply` are two commands (protocol.md §5), and the thread that a
continuation would park is **the one that renews the silence lease**. A lease
expiring while somebody reads a dialog is the failure the lease design exists to
prevent, so the AppKit prompter owns a table keyed by ticket, `waitForUserReply`
polls it against the same `Clock` port every other wait uses, and nothing blocks
either thread. The alternative and its rejection are in `UserPrompter`'s header.

**A question gives the reader back while it is open.** protocol.md §5 says
`suppressing` is false while an `askUser` window is open, and the reason is not
bookkeeping: asking a question of somebody whose screen reader this session has
muted is asking them to answer a dialog they cannot hear. The prompt records
whether it lifted anything — a live session lifted nothing — and the answer puts
back exactly that, **unless the silence cap has already fired**, because that was
a guarantee rather than a loan. While a window is open the dispatch loop keeps the
cap's own window fresh, so a human who takes two minutes cannot cause a lift of a
suppression that is not in force.

**What the human was told is in the transcript, in full.** `announced` records
the text where `typed` records a length, and the asymmetry is deliberate: an
announcement is written to be heard out loud in a room, and a password is not.

## Focus has TWO ROUTES, and the grant picks one without ever being asked for

`getFocusInfo` answers from the **accessibility tree** of the frontmost
application when this process holds the Accessibility grant, and from
**VoiceOver's own cursor** over AppleEvents when it does not. Five rules bind
anyone editing this, and the first is the one that keeps the section above true.

**The grant is READ, never requested, and the reading happens at the adapter
layer.** `VoiceOverFocusInspector` holds `AccessibilityTrust` — a seam with one
method, `isTrusted()`, answered by the same `TCCPermissionBroker` that answers
the domain's `PermissionBroker` — and not the domain port itself. That is
deliberate rather than incidental: focus is the one command that WANTS 13.8's
grant and does not move the machine to earn it, so the guarantee is made
structural, by handing it an object that cannot request anything. `Tests/Integration/SessionRoundTripTests.swift` drives
`getFocusInfo` down both routes past a counting broker and asserts it was asked
nothing at all. If you ever hand the inspector the broker, you have spent the
lever. The alternative that was declined — `focusInfo(accessibilityGranted:)`,
with the controller passing the answer down — is recorded in spec 0046's 13.9
section with its why.

**Nothing merely empty is a fault.** Nothing focused, no title, `missing value`,
no bundle identifier: each is an ANSWER. Spec 0047's finding 5 is the argument —
with VoiceOver frontmost every read comes back empty because it publishes no
accessibility tree of its own, and a bridge that reported a named reader fault
for that would be diagnosing its own doing. What throws is a channel that refused
the question: the AppleEvents grant missing, the reader not running, the
accessibility API refusing outright.

**`AXUIElementCreateSystemWide()` fails with `-25204 kAXErrorCannotComplete`,
and no permission fixes it.** It is not `kAXErrorAPIDisabled` (-25211), so
anybody who reads the number as a permission problem will spend an evening
proving otherwise. The bridge addresses `AXUIElementCreateApplication(pid)`
instead, which is why the tree seam takes a pid and why `FrontmostApplication` is
a collaborator rather than a convenience. `AXAccessibilityTree`'s header carries
the measurement where whoever tries the system-wide element will read it, and
`bash scripts/voiceover_focus.sh` keeps it as a **labelled control that is
expected to fail** — re-measured 2026-08-30, still `-25204`.

**The two cursors separate on ONE keystroke, and the tree tracks the KEYBOARD
one.** Measured 2026-08-30, macOS 15.0, and re-runnable as `bash
scripts/voiceover_cursors.sh`: with a TextEdit document focused, one press of the
reader's own `stop interacting with item` moved the `vo cursor` to the scroll
area while the `keyboard cursor` and the accessibility tree both stayed on the
focused text. So `getFocusInfo` answering the keyboard view is a real choice with
a real consequence — an agent that navigates with VoiceOver commands and then
asks where it is gets the element it left, and the one it is on comes from
`pressGesture ["describe item in voiceover cursor"]` plus a speech read. **The
same run found that the VO cursor's answer is LOCALIZED** — `área de rolagem`,
where the tree says `AXTextArea` on every machine — so the fallback route's
`name` is not comparable across machines. That is not a reason to withhold it; it
is a reason no check may compare it. **And one negative worth keeping**: `move
right` inside a text area shows none of this, because it moves the cursor within
the element while `text under cursor` reports the whole element, so the run looks
like agreement when nothing was tested.

**`role` is `AXRole` and `appModule` is a BUNDLE IDENTIFIER.** `AXRoleDescription`
is asked for nowhere: it is `AXButton` rendered into the user's language, and a
`role` built from it would mean a different thing per machine while looking
perfectly reasonable. Same for the application: `localizedName` is "Editor de
Texto" here and `com.apple.TextEdit` everywhere. Spec 0047's finding 15 is the
same lesson for the tree itself — filter by role and predicate, assert exactly
one match, prefer structure over words, confirm by meaning — and it is what any
later entry that WALKS the tree has to follow.

## Speech is paced by the CAPTURE VOICE, and an announcement is two utterances

Measured 2026-08-31 in Safari web content, and it explains every capture-fidelity
question this bridge has. **Landing on an element produces two utterances — the
role, then the text — and the gap between them is 50–110 ms in a silent session
and ~1505 ms in a live one.**

**THE READER PACES ITS QUEUE ON OUR RENDER COMPLETION, which is what that
twentyfold difference proves.** A silent session renders near-zero-length audio,
so the extension signals completion at once and VoiceOver hands over the next
utterance immediately; a live one renders real speech and VoiceOver waits for it
to be spoken. So the pacing is ours to observe and — in principle — ours to
change. Any command that arrives inside that window makes VoiceOver **cancel**
the pending utterance, and a cancelled utterance is one this bridge never sees at
all: the capture point is the SYNTHESIZER, downstream of the reader's own queue.

**That is one of two architectural differences from lane 1, and both are worth
knowing in both directions.**

**BOTH READERS PACE THEIR QUEUE ON THE SYNTHESIZER. What differs is where capture
sits relative to that pacing** — read out of `../nvda` at `release-2026.1`,
2026-08-31, rather than assumed:

- NVDA's `SpeechManager` holds `pendingSequences` and pushes the next one when the
  synth reports done: `_onSynthDoneSpeaking` → `_handleDoneSpeaking` →
  `_pushNextSpeech(True)` (`source/speech/manager.py`). So it waits, exactly as
  VoiceOver does.
- **But `filter_speechSequence.apply(speechSequence)` is the FIRST LINE of
  `speak()`** (`source/speech/speech.py:1096`) — before the priority handling,
  before the manager, before the synth exists in the story. Lane 1 therefore
  captures **upstream of its own queue**, and this bridge captures **at the
  synthesizer**, downstream of the reader's.

So the agent-visible consequence, which is the part to tell an agent: on NVDA a
session sees everything the reader **decided to say**, at the instant it decided,
whatever the synth is doing and whether or not the speech is later cancelled. Here
a session sees what got as far as **being spoken**. `getSpeech` means "what the
reader queued" on one bridge and "what the reader handed to a synthesizer" on the
other — neither is wrong, and they are not the same sentence. **It is also why
`silent` versus `live` changes what an agent can read here and changes nothing at
all on NVDA.**

**AND THE CAPTURE PATH IS IPC HERE AND A FUNCTION CALL THERE**, which is the
difference that decides how wide a wait has to be. Lane 1's bridge is an add-on
**inside the NVDA process**: `filter_speechSequence` is called on NVDA's own
thread, so capture costs a function call and its latency is nil. Here the reader,
the capture voice and the bridge are **three processes**. VoiceOver hands the
utterance to the capture voice (its own `.appex`), which appends a JSON line to a
file in its container, which `FileLineTailer` **polls every 50 ms** — a cadence
its own header calls "a deliberate floor on the feed's latency, and the one number
in this class a live run should be measured against".

**So `graceMs`'s default of 100 ms is about two poll intervals wide here, and
effectively unbounded there.** Same field, same number, same contract — and on
this bridge some of it is spent before any utterance is visible at all. Nothing
has yet measured how much of a real grace window the pipe consumes; that is board
entry 13.18, and it is why that entry is an investigation rather than a parameter.

**AND THE TEXT HALF MUST STAY AHEAD OF THE AUDIO HALF -- it already is, and it is
load-bearing.** `CaptureController.capture()` emits to the `UtteranceSink`
**before** it calls `synthesizer.speak`, so a session sees an utterance the moment
VoiceOver hands it over, whether or not anything is about to be spoken aloud. That
is what makes **first-utterance latency identical in live and silent**, which is
the property lane 1 gets for free by capturing at queue time. The spike did it the
other way round -- the line was written after the prebuffer wait -- and every
captured utterance reached the file about 0.2 s late; the order was changed
deliberately and its header says so. **Anyone "tidying" that emit to sit beside
the `speak` call reintroduces it, and makes live worse than silent for every first
utterance.**

So the live/silent difference is NOT that our capture waits for audio. It is that
VoiceOver will not hand over utterance N+1 until N has finished rendering -- the
delay is upstream of this bridge, in the reader's own queue, and it is a person
listening.

**What the pipe does NOT distort is `emittedAt`.** The stamp is taken in the
capture voice's own process at the moment the utterance arrives
(`ContainerFileUtteranceSink`, `at: Date().timeIntervalSince1970`) and travels in
the line; `ContainerFileSpeechSource` reads it rather than re-stamping, "so
`emittedAt` means the instant of EMISSION and survives". **That is what makes the
gaps above trustworthy** — they are differences between two upstream stamps, not
between two poll ticks, and the silent figure landing near the poll interval is a
coincidence rather than a measurement of our own tailer. What the pipe delays is
*when a session can see* an utterance, which is what a grace window is actually
racing.

**`graceMs` returns on the FIRST utterance**, in both bridges and by contract
(`protocol.md` §5, spec 0025) — `SpeechBuffer.collectSince` waits for speech to
have STARTED. Lane 1's docstring states the assumption behind it out loud: "the
common case is one announcement ~124 ms after a keystroke". That is an NVDA fact.
Here it means a batched `pressGesture` fires the next key as soon as the role
lands and cancels the text, **in silent as well as live** — measured, 2 of 4 titles
lost in a silent batch. What the reader needs and neither bridge has is the
COMPOSITION of the two waits this repo already owns: start, then quiet.
`collectSince` is start-only and `waitToFinish` is quiet-only, and quiet-only
cannot work on its own, for the reason its own docstring gives.

**Responding asynchronously for pass-through was considered and declined**, and
the reasoning is kept because it is the only lever that exists. Signalling
completion as soon as the utterance is captured, and playing the audio out of
band, would give a live session a silent session's fidelity — the pacing finding
above says it would work. It also makes THIS BRIDGE the owner of interruption:
VoiceOver would cancel what it believes is current, which by then is a later
utterance, while our queue of already-"completed" ones keeps playing. A person
presses a key to stop the reader and it carries on talking about where they used
to be, and that is the single most-used gesture a screen reader user has. Audio
would also drift further behind the cursor the faster somebody drives, and the
queue lifecycle would land in the render path that must not allocate or block.
**The trade-off it tries to beat is one the contract already draws** (`protocol.md`
§4): a live session is paced by audio because a human is listening, and you cannot
have audio-paced delivery and non-audio-paced capture for the same listener.
Prefer silent when reading; that is what it is for.

## The endpoint, and why the derivation is duplicated on purpose

The bridge **listens**; the server dials
([`specs/wire/v1/protocol.md`](../../specs/wire/v1/protocol.md) §1). The default
is the local endpoint, addressed by the bare name `voiceoverMcpBridge`, which
resolves here to a Unix domain socket under `$XDG_RUNTIME_DIR` or `~`.

`Entities/LocalSocketPath.swift` deliberately mirrors the server's
`server/domain/entities/local_socket.go`. **Both halves must derive the same path
from the same published rule or they never meet**, and the failure mode is a
refused connection on a machine where the bridge is plainly running. So the rule
lives in the published contract, both sides compute it in tested domain code, and
neither reads the environment to do it — the caller passes the values in.
`LocalSocketListener` holds §1's three listener obligations (directory mode
`0700`, unlink before binding, unlink on exit) because their **order** is the
contract.

## What this reader says about itself: the guidance document

`getGuidance` is the `guidance` capability, and it is the reason that capability
came last: the document can only be written against a vocabulary that already
works, so **every concrete claim in it is a measurement some earlier entry paid
for**. It lives in `Sources/VoiceOverBridgeDomain/Entities/Documents/` as five
`.md` files — `common`, plus one per persona, plus `unknown` — because a document
served to an agent is a file and never a string literal (root `AGENTS.md`,
invariant 9).

Four rules bind anyone editing it.

- **It is the THIRD rendering of the embedded-document trap, and the least
  dangerous of the three.** Go embeds at compile time and Python has no build
  step, so both can serve a stale document silently; SwiftPM has a real
  dependency graph that includes resources, so an edited document forces a
  rebuild. Measured 2026-08-31. What is *not* free is the `.app`:
  `Bundle.module` is found beside an executable SwiftPM built and not inside a
  bundle a script assembled, so whoever gives the app the domain's dependency
  edge (13.14) copies the generated bundle into `Contents/Resources` in the same
  breath. `Package.swift`'s header carries that obligation.
- **A missing document raises; it never returns `""`.** An empty document reads
  to an agent as "this reader has nothing to say", which is a very different and
  much worse answer than "the build is broken" — and the agent acts on it. The
  rule earned itself immediately: `.copy` of a directory nests the files, the
  first run could not find `common.md`, and the loader said so by name instead of
  serving nothing.
- **The boundary it draws is NOT NVDA's, and that is the point of the document
  existing.** Spec 0029's rule is reader-agnostic — a command that re-reads what
  is already there is in, a command that reaches what focus cannot is out — and
  every instance of it is this reader's. On NVDA the boundary falls at object
  navigation and the review cursor; here **cursor navigation is what an ordinary
  user does all day**, so the boundary falls at the mouse commands and the hot
  spots instead. A stance transcribed from lane 1 would forbid the platform's own
  vocabulary.
- **It names a curated subset of the toggles and NO table of the vocabulary.**
  The 414 command names stay out of this repo for the reason the gesture section
  below gives; what the document adds is which toggles matter, that each
  announces its own result — which is how an agent reads state on a reader that
  cannot be asked — and that the reader is the authority on the rest. The names
  in it were read out of `SCRStringsToCommandsMap.scrconfig`, not recalled.

**The handshake carries it too.** `hello` sends the same document (protocol.md
§3) so a session gets it without a second round trip, and a server that receives
it must not call `getGuidance` as well. Both routes therefore compose through one
static function, and a conformance scenario drives both over a real wire and
asserts they are equal — two compositions would be a handshake and a command that
agree today.

## The conformance tier: the third binding, finally on a wire

`poe conformance` drives the real Go binary against the real Swift bridge, as it
already did against the real Python one, and 13.11 is where the two halves of
this lane were first gated together.

**What it adds that `scripts/drift.py --swift` cannot.** That gate reads the
binding's SOURCE against `specs/wire/v1/schema.json`, so it catches a field that
was never written. It cannot catch a field written *differently* from how the
server reads it, because nothing had ever put the two implementations on opposite
ends of a socket. Every other test of the server drives a Go fake that encodes
with the same generated binding the server decodes with — both sides wrong
together, in agreement.

`Tests/ConformanceBridge/` is what makes it reachable: a real `BridgeServer`, a
real `Session`, a real `JsonLinesChannel` and a real `Registry`, with a **fake
reader edge**, startable as a process. Four rules:

- **It speaks the Python harness's protocol byte for byte** — `--transport`, one
  JSON line on stdout, stdin EOF to stop — so the Go side has one driver protocol
  rather than two to keep in step with the contract it is testing.
- **It must never be copied into the bundle.** It carries the doubles that exist
  to keep code away from a real reader, a real grant and a real voice; shipping it
  would ship a bridge that only pretends to drive VoiceOver.
- **It announces with `FileHandle`, not `print`.** Swift's `print` is fully
  buffered to a pipe, so a `print` there deadlocks the Go driver until the process
  exits. Measured on `BridgeListener` first, whose startup report was invisible
  for exactly this reason.
- **`/tmp` and a short endpoint name.** A Unix socket path may be at most 103
  bytes and `NSTemporaryDirectory()` is a `/var/folders/...` path around 49 before
  anything of ours is appended. The kernel's answer to a longer one is `connect:
  invalid argument`, naming neither the limit nor the path.

The Go scenarios are `//go:build conformance && darwin`. **That is not a skip**:
the tier's rule is that failing to reach the real bridge is a hard failure and
never a fall-back, and nothing falls back — on Windows the files do not compile in
at all, because a Swift bridge for a macOS-only reader cannot exist there. On
macOS there is no escape hatch. They connect **live** rather than silent, because
13.6 refuses a silent handshake where the capture voice is not published, which is
every CI runner.

## Two executables exist that the bundle does not ship

`CaptureProbe` answers *"is the capture voice published?"* without a human
squinting at a settings pane, and `BridgeListener` starts the bridge listening
from a terminal. Neither is copied by `build.sh`. They are in the repo for one
reason: **anything a check depends on is versioned, in the same PR as the
check** — the 2026-08-22 rule — and both answer a question no unit test can.
Keep them thin: the graph is `Wiring`'s, and logic that starts accumulating in
either belongs in `Wiring` or in the dialog.

**`BridgeListener` is how a bridge is STARTED on this platform, and it will be
until 13.14.** The control dialog was split out of 13.10 on 2026-08-30 —
*"wait until you can control VoiceOver, so that you can navigate through your own
GUI by yourself, and keep using the config file until then"* — so the launcher
reads the same persisted settings the dialog will edit: it starts from
`UserDefaultsBridgeConfig` and lets this run's flags override them without
writing anything. It also plays the audible cues as well as printing them, and
prints what the machine can do before anything is pressed — the capture voice's
state, whether AppleScript control of VoiceOver is on, and which permissions are
held. **None of that asks a human for anything**: `status` shows no dialog, and
the scripting setting is two file reads.

## Tests

The root manual's rules apply unchanged: `Tests/` mirrors `Sources/` file for
file, one test module per source module, and a source file with no test file is a
deliberate statement (ports, and leaves that make no decisions). The lane's own
shapes:

- **swift-testing** (`import Testing`), decided for the lane at 13.4.
- **`Tests/Fakes/` is a shared target** — the domain's tests, the adapters' tests
  and the integration scenarios all need the same doubles, and three copies of a
  stateful fake is three chances for one to drift into agreeing with the code
  instead of with the port. `Support/` inside it is scaffolding that stands in for
  no port, which is lane 1's `tests/support/` in the one form Swift allows.
- **`Tests/Integration/`** holds headless scenarios that drive the real stack,
  including over **real** sockets dialled by a client built from the raw socket
  API — a round trip proven with our own code on both ends would not prove the
  endpoint is dialable. They bind in a home directory they invent under `/tmp`, so
  they never touch the endpoint a developer's own bridge listens on. Live-VoiceOver
  scenarios are **not** here: they live behind the bridge's `live` tier and never
  run in CI.
- **No test compares reader strings.** VoiceOver renders under the tester's own
  locale — the maintainer's machine speaks Portuguese — so structure is compared
  and text never is. That is
  [`scripts/live_pages/README.md`](../../scripts/live_pages/README.md)'s rule in
  its macOS instance.

## Gotchas learned the hard way

- **A `swift test` that passes does not prove the loop calls what you added.**
  Measured on 2026-08-30: 13.6's lease renewal was written into
  `Session.checkSilence`, and the edit that was supposed to CALL it from the
  dispatch loop silently did not apply. Everything compiled, every unit test of
  the adapter passed, and the marker would never have been refreshed on a real
  machine -- so every silent session would have un-muted itself after thirty
  seconds with nothing in the logs to say why. What caught it was a session-level
  test asserting the number of renewals, not an adapter-level one. Anything whose
  value is that it happens REPEATEDLY needs a test at the layer that repeats it.
- **A wedged application under test looks exactly like a dead reader.** Measured
  2026-08-30: Finder stopped responding, every cursor read answered `missing
  value`, dispatches appeared to do nothing — and VoiceOver was entirely healthy,
  saying so out loud in the user's own language. `killall Finder` fixed it.
  Nothing at the bridge's layer can detect this, which is why `ReaderLiveness`
  answers one narrow question about the READER and its header says in as many
  words that a healthy answer from it is not a claim about the machine under
  test. Spec 0047's finding 5 is the same confound from the other end: VoiceOver
  frontmost publishes no accessibility tree of its own, so every read looks dead
  then too. **When reads go quiet, check what is in front before blaming the
  reader.**
- **A reader that runs on its own thread must ATTACH before `start()` returns.**
  `FileLineTailer` opened the feed and seeked to its end on the new thread, which
  is a race against everything the caller does next — and what the caller does
  next is act on the reader. The utterance an action caused was therefore the one
  that could be swallowed by the seek, and it failed as a `waitForSpeech` timeout
  reading exactly like "the reader never said it". Measured on 2026-08-30, in the
  tests, which is the only reason it was not measured live instead. Whatever a
  background loop must not miss, capture it on the caller's thread.
- **DO NOT RUN THE BRIDGE UNDER `script(1)`, and fix the buffering instead.**
  Swift's `print` is block-buffered when stdout is not a terminal, so
  `BridgeListener > run.log &` shows nothing at all while it runs -- which is
  exactly how a live check captures the startup report. The obvious workaround is
  a pty: `script -q run.log BridgeListener`. **It breaks the accessibility
  reads.** Measured 2026-08-31: under `script -q`, `getFocusInfo` answered
  `-25204 kAXErrorCannotComplete` for *every* application, while the same build
  launched directly answered `AXList / com.apple.finder` immediately, and
  `scripts/voiceover_focus.sh` had been reporting a healthy tree the whole time.
  An hour went into suspecting the bridge, `NSWorkspace.frontmostApplication`,
  the SSH session and a wedged Finder before the harness turned out to be the
  variable. `BridgeListener` now sets `setbuf(stdout, nil)`, so the report is
  visible in a plain redirect and there is no reason to reach for a pty. **The
  general lesson is the one this repo keeps relearning: when a measurement
  disagrees with a versioned instrument, suspect the harness before the code.**
- **macOS filesystems are case-insensitive by default, so two source files whose
  names differ only in case are ONE file to the build.** `Ports/TcpBinder.swift`
  beside `TCPBinder.swift` compiled, and one object file silently overwrote the
  other; the failure arrived as *"undefined protocol descriptor"* at link time,
  naming nothing that would lead you back. Measured on 2026-08-30. A type may
  differ from another only in case; a **file** may not.
- **Searching outside the repo needs `-a`.** macOS's interesting files are binary
  plists, and both `grep` and ripgrep report *absence* rather than saying they
  declined to look. Ripgrep's version is worse because it looks safe: `rg -l` on a
  **named** binary file matches, while `rg -l` **walking a directory** does not.
  The root manual carries the measurement; it cost an evening here.
- **When a value must exist but cannot be found, compare states instead of
  searching for strings** — checksum the candidate tree with the value set to A,
  to B, and back to A. See
  [`docs/how-we-found-the-voice-store.md`](../../docs/how-we-found-the-voice-store.md).
- **The bundle identity is frozen**, and `README.md` says why: the voice
  identifier VoiceOver stores is derived from the extension's bundle id, so
  renaming costs every user a trip to VoiceOver Utility to re-select a voice that
  silently vanished. 13.11 owns identifiers and is where that is paid once.
- **Three findings are built into `build.sh`, each of which failed silently when
  it was wrong**: a speech provider must be sandboxed, must **not** hold
  `com.apple.security.network.client` (which is why the bridge reads a file rather
  than a socket from the extension), and must not declare `AudioComponentBundle`.
  [Spec 0041](../../specs/0041-can-voiceover-say-what-it-said.md) A1 has the
  measurements.
- **VoiceOver crashes on the maintainer's machine as routine weather**, so lane
  3's live checklists measure the crash census from two independent sources and
  every check is independently re-runnable from a cold start. Spec 0046 part 1(c).
  **The two sources, and how to read them** (13.11's live run used both):
  `~/Library/Logs/DiagnosticReports/` and the `Retired/` directory beneath it
  hold the `.ips` reports, one per crash, named with a timestamp; and VoiceOver
  keeps its own count in `SCRCUserDefaultsUnplannedShutdownCount` inside
  `com.apple.VoiceOver4.local.plist` (spec 0046 part 2). They can disagree, which
  is why there are two. **And the weather is not constant**: measured 2026-08-31,
  six reports all dated 2026-08-28 and none in the three days since, with the
  reader's own counter at 0. A burst rather than a drizzle -- so "it crashed"
  is a hypothesis to check against both sources, not a default explanation for a
  quiet read.
