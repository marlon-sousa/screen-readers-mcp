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

## The capability set grows ONE ENTRY AT A TIME

`hello` announces what this build actually implements, and nothing else.
`Registry.capabilities` was empty at 13.4, `[speech]` at 13.5, `[speech,
gestures]` at 13.7 and `[speech, gestures, typing]` at 13.8, and each later entry
adds its own alongside the handlers that serve it. Announcing a capability
before the entry that implements it produces the one failure the capability gate
exists to prevent: a tool the agent can see, call, and get nothing from. The
converse costs too, and it is why `speech` landed with 13.5 rather than being
held back: a capture feed the server gates away is a tool nobody can call.

The same rule is why `VoiceOverAdapterFactory` refused a silent session until
13.6, and **13.6 deleted that refusal and its named test in the commit that made
the promise keepable**, exactly as this file required. What replaced it is not
nothing: **the refusal MOVED to the handshake**, which is the only place that can
ask whether this machine can actually deliver silence. `silent` is not a
preference, it is a promise about a human's ears, so a silent handshake on a
machine where the capture voice is not registered, not published, or would not
stick is refused **by named condition, with its recovery** — never established
and quietly turned into something else.

**A LIVE handshake in the same state is not refused**, and the asymmetry is
deliberate rather than squeamish: writing the voice applies live, in both
directions (spec 0047, finding 17), so a live session that starts unhealthy can
become healthy while it runs. Silence promised at the handshake has to hold from
the handshake.

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

## A gesture on this reader is a COMMAND NAME, addressed to the commander

Two rules, and the second one is the finding that unblocked board entry 13.7.

**Gesture ids are English command names**, from VoiceOver's own
`SCRStringsToCommandsMap` vocabulary — 415 entries on macOS 15.0, phrases like
`go to desktop` and `mute sound toggle`. There is no table of them in this
repo and there must not be one: the reader does its own dispatch and answers an
unknown name with `Command does not exist (6)`, which is a better check than any
copy that goes stale every release. What `CommandVocabulary` refuses is a
**keystroke sent as a gesture** — `control+l`, and VoiceOver's own `VO-D`
notation — because that is the mistake the reader cannot diagnose usefully, and
because synthesizing a keystroke needs the Accessibility grant 13.8 exists to
keep lazy. The hyphen rule has to survive real command names that contain
hyphens, so a hyphen counts only in an id with no spaces at all.

**A gesture reaches commands and single KEYS, and NOT chords.** The vocabulary
carries 30 commands whose name ends in `key` — `tab key`, `return key`, the four
arrows, `f1 key` through `f12 key`, `delete key`, `forward delete key`, `fn key`
— plus modifiers in two flavours, momentary (`command key`, `shift key`, …) and
sticky (`toggle command key`, …). All cost no Accessibility grant, so a chord
reachable this way would widen the lazy lever considerably. **Measured 2026-08-30
on macOS 15.0: they do not compose.** Four runs — sticky and momentary, option
and command — each followed by `delete key` into a scratch document removed
exactly one character, the same as the no-modifier control, where Option-Delete
would have taken a word and Command-Delete the line. The modifier command
*succeeds* and changes nothing about the key that follows it, which is the worst
shape a negative can have, so it is written down here and re-runnable as `bash
scripts/voiceover_modifiers.sh`. Independently of that, the table has **no letter
keys at all**, so literal text can never come out of it — which is why `typeText`
synthesizes events and pays for the grant.

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

Two commands, two ports, two capabilities, and the separation is the lane's one
design lever rather than tidiness. `pressGesture` is an AppleEvent to the reader;
`typeText` synthesizes system input events and needs **Accessibility**
(`kTCCServiceAccessibility`). Windows has no equivalent gate, so lane 1 has no
analogue and there is nothing to copy here.

**THE ACCESSIBILITY GRANT IS REQUESTED FROM ONE PLACE: `TypeTextHandler`, on a
`typeText`.** Not at construction, not in `Wiring`, not in
`VoiceOverAdapterFactory`, not in `scripts/doctor.py`, not in a probe, and **not
in a test**. That is what makes

> a session that only presses commands and reads speech never triggers an
> Accessibility request

a *checkable statement about this bridge* rather than an intention, and the check
is a round trip in `Tests/Integration/SessionRoundTripTests.swift` that drives a
handshake, a gesture and a speech read past a counting broker and asserts it was
asked nothing at all. `Wiring` **constructs** `TCCPermissionBroker` at startup and
never calls it: constructing asks nobody anything, and only `request` raises a
dialog. If you add a caller, you have spent the lever — the entry is worth what
its checkability is worth.

**No test may touch the real grant or post a real event.** The real broker's
`request` raises a system consent dialog and leaves this process on a list that
**stays granted**, with no undo; a real `CGEvent` types into whatever window the
developer has in front of them at that moment. Both are injected into
`VoiceOverAdapterFactory` for exactly that reason, and
`Tests/Fakes/Support/ReaderEdge.swift` hands every test fakes — the same guarantee
it already gives for the provider lifecycle, which writes the voice the developer
hears.

**The target application rewrites what was typed.** Two lines sent to TextEdit
came back autocapitalized (spec 0041). "Send this keystroke" is not "this text
arrives", and **nothing in this bridge, its tests or its documentation may compare
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

## Two executables exist that the bundle does not ship

`CaptureProbe` answers *"is the capture voice published?"* without a human
squinting at a settings pane, and `BridgeListener` starts the bridge listening
from a terminal. Neither is copied by `build.sh`. They are in the repo for one
reason: **anything a check depends on is versioned, in the same PR as the
check** — the 2026-08-22 rule — and both answer a question no unit test can.
Keep them thin. Every decision `BridgeListener` makes is a flag read into a
`BridgeConfig`; the graph is `Wiring`'s, and logic that starts accumulating there
belongs in `Wiring` or in the dialog.

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
