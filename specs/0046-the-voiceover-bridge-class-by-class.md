# Spec 0046 — the VoiceOver bridge, class by class

**Status:** implementation spec for `ROADMAP.md` entry **13.1**, agreed in
conversation **2026-08-29**. It covers the whole of lane 3 — entries 13.2
through 13.13 — because the lane's decomposition is one decision and reviewing
it a slice at a time would review nothing.

It inherits, and does not relitigate:

- [Spec 0041](0041-can-voiceover-say-what-it-said.md) — the capture spike, and
  the six fixes that each cost a live round against a real reader.
- [Spec 0043](0043-the-voiceover-bridge-is-one-swift-bundle.md) — the direction
  RFC. One Swift bundle; Swift for both halves; the repo stays a monorepo; the
  local endpoint resolves per platform. **Decided**, all of it.
- [Spec 0044](0044-the-local-endpoint-off-windows.md) — where the local endpoint
  lives on POSIX, which is the rendezvous both halves must compute identically.
- [Spec 0013](0013-mcp-server.md) — the capability gate, which is what makes a
  partial bridge a first-class citizen rather than a degraded one.

Spec 0043 gave **no class/file layout**, deliberately, because it added no
production class. This spec is where that lands, and it is the repo's review
gate for the decomposition itself: every class, its role — port, controller,
entity, adapter, or a **named supporting construct** — and its collaborators.

## Part 1 — the three questions 13.1 owed

### (a) Six capabilities, and they arrive one entry at a time

**Announced when the lane is complete:** `speech`, `gestures`, `typing`,
`focus`, `interact`, `guidance`.

**Not announced, each for a reason recorded below:** `braille`, `state`,
`config`, `log`, `document`.

The set is not announced all at once, and that is the point. A capability
appears in `hello`'s list **in the entry that makes the thing behind it real**,
so the gate describes what works rather than what is planned:

| After entry | The announced set is |
|---|---|
| 13.4 | *(empty — `hello`, `ping`, `echo`, `bye` belong to no group)* |
| 13.5 | `speech` |
| 13.7 | `speech`, `gestures` |
| 13.8 | `speech`, `gestures`, `typing` |
| 13.9 | `speech`, `gestures`, `typing`, `focus` |
| 13.10 | `speech`, `gestures`, `typing`, `focus`, `interact` |
| 13.11 | all six |

That table is a demonstration of [spec 0013](0013-mcp-server.md)'s design, not a
schedule: a half-built bridge is honest at every step, and no agent ever sees a
tool that does not work.

### (b) Braille — absent from the reader, so no port exists

**There is no `BrailleSource` port, no braille buffer, and no `getBraille`
handler.** Not "unimplemented": VoiceOver's AppleScript `braille window` exposes
exactly one property, `enabled` (read/write visibility), and the speech provider
route captures speech and nothing else. There is no braille content to read.

Stated precisely, because the imprecise version is false: braille is not wholly
absent from the reader. The command table holds **31 `SCRBraille.*` commands** —
tables, status cells, word wrap, Nemeth, auto-advance — so a bridge can *drive*
braille settings as gestures. What is absent is braille **content**, and
`getBraille` is a content command.

Three consequences for the layout:

1. No `braille` in the announced set, ever, on this reader.
2. **No `IndexedBuffer` base class.** The NVDA bridge factors one out because it
   has two buffers; here there is one, so `SpeechBuffer` is one class. If a
   second capture stream ever appears, the base is extracted then — which is the
   lesson `AGENTS.md` already records about that very file.
3. **The bridge must not synthesise it.** Deriving a braille stream from speech
   text would be the same failure as returning an empty read-back for a dead
   scripting channel: an answer that looks like data and is not.

Braille is the example the capability gate was designed around — spec 0013's own
words are *"a reader without braille never shows a braille tool"*. Lane 3 is the
first time that sentence is exercised against a real reader.

### (c) The live checklist — measure the weather, provoke the conditions

VoiceOver crashes on the maintainer's machine as routine weather: five crash
reports on 2026-08-28 alone, all before the spike started. That cannot be
designed away, so it is **measured** instead. Four rules bind lane 3's live
checklists, and 13.11 is the entry that must satisfy them.

1. **The first and last checklist items record the crash-report census** — the
   count and timestamps of `VoiceOver*` reports in
   `~/Library/Logs/DiagnosticReports/` before the run and after it. A crash
   during a run then becomes evidence with a coordinate, and a crash that was
   going to happen anyway is not attributed to the bridge.
2. **Every check is independently re-runnable from a cold start.** No check may
   depend on state a previous check left behind, because the reader restarts
   underneath the run. This is stricter than lane 1's checklists and it is the
   direct consequence of the weather.
3. **Three items deliberately provoke the conditions the machine actually
   produces**, and each expects a *named, reported* condition rather than an
   empty answer:
   - issue `open next speech attribute guide` six times → the scripting object
     model dies while VoiceOver lives (spec 0041's sharpest finding);
   - switch VoiceOver's voice away from the capture voice → utterances stop;
   - kill the extension → the provider dies, VoiceOver falls back to a working
     voice, and **only a reader restart re-binds ours**.
4. **Attempts and crash references are part of the evidence.** An item may be
   ticked as *"passed on attempt 2 of 3; attempt 1 lost to a VoiceOver crash at
   14:02, report `VoiceOver_2026-…`"*. An item that cannot be made to pass stays
   unticked with its finding inline and spawns an iteration entry, exactly as the
   existing rule says.

Everything a check depends on is versioned in the same PR, per the 2026-08-22
rule — including the probe kept under 13.2 below, which is what answers *"is the
capture voice published?"* without a human squinting at a settings pane.

**The panic route is the OS's own**, and it is better than NVDA's: Command-F5
toggles VoiceOver off, and a dead provider falls back to a working voice rather
than to silence (spec 0041, C2). So no bridge-side panic gesture is designed,
and the checklist says so rather than leaving the tester to wonder.

**Checklist steps stay short enough to survive the inactivity watchdog.** Lane
1's third live lesson applies here with more force, because a reader restart
mid-step costs the step twice.

## Part 2 — what was measured on 2026-08-29, and what it moved

Three questions were researched on the macOS host before this spec was written,
because two of them looked settled and were not. Everything below was measured
on **macOS 15.0 (24A335)** with VoiceOver running as pid 472.

### VoiceOver has no diagnostic log of its own

`log show --last 60m --info --debug --predicate 'process == "VoiceOver"'`
returned **52 records, none of them VoiceOver's**. Every one comes from a
framework VoiceOver links — `com.apple.apsd:connection`, CoreAudio's `AUHAL` and
`HALC_ProxyIOContext` — and the message bodies are `<private>` redacted. There is
no `com.apple.VoiceOver` or ScreenReader log subsystem; there is no log file
under `~/Library/Logs` or `/Library/Logs`; and the ScreenReader framework binary
lives in the dyld shared cache, so there is no diagnostic switch discoverable on
disk. Web sources describing "enabling VoiceOver logging" name no mechanism.

So **`log` is absent from the reader**, and that is measured rather than
inferred — a stronger statement than the braille one.

**The tempting alternative is declined explicitly.** The unified log *is* rich
and system-wide, and spec 0041 used it to diagnose the provider (`AXTTSCommon`,
`pkd`). Serving it through `getLog` would be a different thing wearing that
name: `getLog`'s contract is the *reader's own* journal, with positions that
join to speech entries via `logPosition`. If we want the system log, it gets its
own conversation and its own capability.

### Focus has three routes, and the obvious one does not work

VoiceOver does have the NVDA+Tab equivalent, and more than one. From the command
table: `describe item in voiceover cursor` (`SCRApplication.focusedElementOverview`),
`describe item with keyboard focus` (`SCRApplication.keyboardElementOverview`) —
one per cursor — plus `describe window`, `describe open applications`,
`read help tag for item`, and `output` with `window overview` / `web overview` /
`workspace overview`. **All of these speak, and the bridge captures speech**, so
they cost AppleEvents only.

The accessibility API also works, and returns exactly `getFocusInfo`'s shape.
Measured read-only against a focused Finder window:

```
AXRole = AXOutline
AXRoleDescription = contorno
AXDescription = visualização por lista
AXEnabled = 1 · AXFocused = 1 · 23 attributes in total
```

**Two traps, both of which fail confidently rather than loudly:**

- **`AXUIElementCreateSystemWide()` + `kAXFocusedUIElementAttribute` fails**,
  with `-25204 kAXErrorCannotComplete`. Notably **not** `kAXErrorAPIDisabled`
  (`-25211`), so it is not a permission problem and no permission grant fixes
  it. The route that works is
  `AXUIElementCreateApplication(frontmostPid)` → `AXFocusedUIElement`, which
  returned `kAXErrorSuccess`. The failing form is the obvious first thing to
  write.
- **VoiceOver publishes no accessibility tree of its own.**
  `AXUIElementCopyAttributeNames` on VoiceOver's process returns nothing, so
  reading the reader's state through its own AX tree — which would have solved
  the state question — is closed.

`appModule` is free: `NSWorkspace.shared.frontmostApplication` needs no
permission at all.

### State is richly toggleable and not readable at all

**Readable state through the scripting object model — the complete list, four
read/write properties:** `caption window enabled`, `braille window enabled`,
`vo cursor magnification`, and `mouse cursor position`. Nothing else in the
dictionary reports state. (Four, not three: `position` declares no `access`
attribute, and sdef's default is `rw`.)

**Toggleable state — 45 of them, none readable.**
`SCRStringsToCommandsMap.scrconfig` holds **415 commands**, 45 beginning
"toggle": arrow-key Quick Nav, single-key Quick Nav, both together, **web
navigation DOM or group**, screen curtain, cursor tracking, insertion-point
(caret) navigation, mute speech / sound / VoiceOver, the VO-modifier lock, the
three commanders, hiding ignored elements. Every one is a *command*; none has a
query. The vocabulary splits `Global` 212, `SCRWorkspace` 105, `SCRBraille` 31,
`SCRTextElement` 23, `SCRWebArea` 21, and a long tail.

**The preferences plist is not the live truth, three ways.** It records only
deviations from default — this machine's file carries
`SCRCUserDefaultsWebNavigationMethod => 0` and
`SCRCUserDefaultsIndependentSingleLetterQuickNavEnabled => 0` but no arrow-key
Quick Nav key at all, so *absent* is ambiguous between "off" and "we guessed the
key name wrong". It sits behind `cfprefsd`, which caches. And VoiceOver holds its
own copy in memory.

**The state of the art does not solve this; it sidesteps it in a way this bridge
must not.** Guidepup exposes `getSetting`/`getSettings`, which looked like a
counterexample. Its source is the opposite: `getPreferences()` reads a
**portable plist mounted from a disk image**, and `mountGuidepupPreferences()`
symlinks the user's VoiceOver preference files to that image and restarts the
preferences daemon. Its state story is *own the preference file*, not *ask the
reader*. That is legitimate on a CI box and unacceptable on the machine a blind
developer uses, because it replaces their screen-reader configuration wholesale.
Recorded here so nobody re-proposes it.

#### Why the toggles live in `gestures` rather than in `setState`

The proposal considered, and the reasoning that settled it, because "the spec was
written for NVDA where we have full control" is the correct diagnosis.

`setState` guarantees three things ([spec 0033](0033-arriving-at-a-mode.md), and
`protocol.md` §5): **arrive** at a mode rather than toggle towards one; *no
script, no earcon, no utterance* when the reader is already in the asked-for
state; and a compare-and-set that happens **inside the reader**, so no window
exists between the read and the write. All three need a read **before** the
write. VoiceOver offers none. The capture feed gives a read-*after*-write, which
is the wrong side of the operation, and deciding what the announcement meant
would require the bridge to parse localized text — the one thing spec 0041
forbids outright.

**The agent loses no power, and this is the load-bearing half of the argument.**
`pressGesture { gestures: ["toggle web navigation dom or group"] }` works today
over `perform command`, and the grace window returns **VoiceOver's own
announcement of the resulting mode** in the result's `speech`. The agent reads
it, knows the state, and toggles again if it wanted the other one. An unknown
command fails cleanly with `Command does not exist (6)`. That is full toggle
authority over all 45 toggles, delivered by a command whose contract (§7.3)
already says *"a result says what had arrived by a stated instant"* and claims
nothing further.

So the choice was never power versus no power. It was **which command name
carries it**, and `pressGesture` carries it while making no promise it cannot
keep. The compare stays with the agent, which is the only party that knows the
locale, the reader and the intent.

**Where the power is actually delivered is `guidance`.** Those 45 toggle strings
are undocumented and unguessable. 13.11's guidance document names the ones that
matter and says that a toggle announces its own result — which turns *reachable
in principle* into *usable in practice*, and is exactly what `protocol.md` §4
says only a bridge can write down.

**If we want more later, it is a new concept and not a bent `setState`:** named
reader toggles with *last observed* values and the instant each was observed,
explicitly a cache of observations and never a live read. That is a v1-successor
conversation. It is recorded under Open questions rather than smuggled into
`getState`'s four fields.

## Part 3 — the shape

### The bridge is five elements, and there are two hexagons

The bundle is one deliverable and **not** one program. Five things live in it,
each with its own process, its own lifecycle owner and its own permission story,
and the decomposition is wrong if it pretends otherwise. Naming them first is
what makes the module table below mean something.

| # | Element | Runs in | Lifecycle owned by | Permission |
|---|---|---|---|---|
| 1 | **The speech provider** | its own `.appex` process, **and** dlopened into every client that speaks — VoiceOver included | macOS: `pluginkit`, `runningboardd` | sandboxed; **no** entitlements, and asking for the network one disqualifies it |
| 2 | **Provider registration** | transient tools and in-process checks | the app, or the user by hand | none |
| 3 | **The bridge session** | a background thread of the app | the app | AppleEvents to VoiceOver |
| 4 | **The input path** | the app's process, posting system-wide events | the app | **Accessibility**, requested lazily |
| 5 | **The control UI** | the app's **main** thread, under AppKit's run loop | the app | none |

Between 1 and 3 there is a **seam rather than an element**: the container file.
It belongs to neither side, it is the only door macOS leaves open, and it is the
reason elements 1 and 3 can be in one bundle without being in one program.

**Element 3 is the bridge's hexagon.** The session is the domain with ports; the
UI (element 5) is a *driving actor* that consumes ports and implements none,
exactly as `views/bridge_dialog.py` does; and elements 2 and 4 are ordinary
port-and-adapter pairs inside it.

**Element 1 is a second, smaller hexagon of its own** — a separate module, in a
separate process, with its own ports. It never imports the bridge's domain, and
that is a *module dependency* rule (it runs inside the user's screen reader), not
an architectural exemption.

An earlier draft of this spec argued the opposite: that a realtime audio
component should stay a monolith because indirection costs performance. **That
argument conflates two different decisions**, and it is recorded here because it
is the kind of reasoning that sounds responsible and is not.

**Separation and binding are not the same choice.** Separating a component —
into files, types, modules — costs nothing at run time. What can cost something
is how a call site is *bound*, and binding is chosen per call site, after the
separation exists. It is the same confusion as "C++ is slower than C because of
objects": virtual dispatch may indeed cost, and virtual dispatch is a binding
decision, not a consequence of having components at all.

In Swift the binding choices are explicit, and only the last one is dynamic:

| Binding | Dispatch |
|---|---|
| `struct`, or a method on a `final class` | static, and inlinable |
| a protocol reached through a generic (`some P`, `<T: P>`) | specialized at compile time; static |
| a method on a non-final class | vtable |
| a protocol reached through an existential (`any P`) | witness table; dynamic |

**Whole-module optimization is on in release builds**, so the compiler inlines
across files *within* a module and file count is free; `@inline(__always)` exists
for the few places that want more.

So the real constraint is narrow and it applies to **one function**: the render
block must not allocate, must not block on a lock, and must not bind through an
existential. The first two the spike already honours; the third is satisfied by
the render block capturing a **concrete, `final`** `AudioRing` outside the
closure, which is what it already does. Every port below is free to be a
protocol, because no port is called from the audio thread.

Everywhere else in the extension — the request thread, the synthesis queue — is
ordinary code with no deadline at all. And the measurement spec 0041 actually
made (a per-sample loop costing **449 dropped render blocks** in eight seconds of
live speech) is an argument about *holding a lock too long*, not about having
classes.

**The cost of the monolith, meanwhile, is not hypothetical: it cannot be
tested.** Six fixes that each cost a live round against the maintainer's own
screen reader are currently comments in one 300-line class, provable only by
running VoiceOver. Separation is what turns them into assertions, and that is the
side of the trade with a measured price.

**What the extension must therefore show is its four layers**, because it has one
input and **two** outputs and the spike's single class hid that:

| Layer | What it is | Where it lives |
|---|---|---|
| **Input** | VoiceOver hands over an utterance as SSML, before any audio exists; and cancels — which it does before *every* new utterance, so cancellation is the normal path | `CaptureAudioUnit` → an `Utterance` entity |
| **Processing** | parse the SSML, read its language, pick the mode, choose a re-synthesis voice that is not ours | `CaptureController`, `SsmlDocument`, `VoiceChoice` |
| **Audio output** *(non-silent only)* | re-speak with an ordinary voice and hand the host its samples | `Synthesizer` port → `AudioRing` → the render block |
| **Text output** *(always)* | the captured utterance, for the bridge to read | `UtteranceSink` port → the container file, and `os_log` |

Two outputs from one input is the shape of the thing, and it is why the audio
half being absent in silent mode changes nothing about the text half.

**The consequence is that the extension gains unit tests**, run headlessly with
no VoiceOver and no audio device. The spike had none, correctly, because it was
throwaway. 13.2 is where that changes: the six fixes that each cost a live round
against a real reader become assertions instead of comments, which is the whole
reason spec 0043 kept this code rather than the measurements alone.

**Element 5 imposes a threading rule with a known analogue.** AppKit owns the
main thread and its run loop; the session runs on a background thread. Every UI
update the session causes must marshal to the main thread, and every session call
the UI makes must not block it. This is the macOS rendering of the NVDA
main-thread rule in `bridges/nvda/AGENTS.md`, and it is the same class of bug —
so teardown paths use the fire-and-forget form, and a main-thread caller can
never end up waiting on the thread it is joining.

### One bundle, six modules, and the package graph is the architecture test

The distributable is one `.app` (spec 0043). Inside it, SwiftPM builds six
targets, and **`Package.swift`'s dependency edges are what keep the hexagon
honest**: a domain file that imports the adapters module does not compile. The
NVDA bridge enforces the same rule by convention and review; Swift enforces it at
build time, which is a better rendering of the same rule and costs nothing.

| Target | Depends on | What it is |
|---|---|---|
| `ScreenReaderWire` | *(nothing)* | the wire contract's Swift binding — pure value types and validation |
| `VoiceOverBridgeDomain` | `ScreenReaderWire` | ports, controllers, entities. No AppKit, no AVFoundation, no sockets, no JSON framing |
| `VoiceOverBridgeAdapters` | domain, wire | the only place macOS frameworks, AppleScript, the filesystem and real IO live |
| `CaptureVoice` | *(nothing of ours)* | the speech provider: **its own small hexagon**, built into a framework |
| `CaptureVoiceExtension` | `CaptureVoice` | the `.appex` stub executable |
| `VoiceOverBridgeApp` | adapters, domain, wire | the container app: composition root and control dialog |

**`CaptureVoice` depends on nothing of ours, and that is a hard rule.** It is
dlopened into VoiceOver's own process, so every byte it carries runs inside the
user's screen reader — the same argument that makes hard invariant 1 stdlib-only,
reached from the other direction. It never imports the domain, the wire binding
or anything that would grow a dependency later.

**SwiftPM cannot emit `.app` or `.appex` bundles**, so `build.sh` (promoted from
the spike, and already proven) assembles them from SwiftPM's build products.
`Package.swift` alone is not the build, and 13.2 says so out loud.

### Two Swift renderings of repo rules, stated rather than assumed

- **"One class per file, no re-export facades"** holds for files. It cannot hold
  for imports: Swift imports modules, not files, so "every import names its
  file" is not a property Swift offers. The compensating rule is that **no file
  may exist whose purpose is `typealias` re-export** — the facade this repo
  bans is banned in the shape Swift would express it.
- **Fakes subclass their port.** In Swift a fake that forgets a method fails to
  **compile**, where Python's ABC fails at construction. Strictly stronger, same
  guarantee, no change to how fakes are written.

## Class/file layout

Roles are **port**, **controller**, **entity**, **adapter**, **adapter seam**,
**leaf adapter**, or a named supporting construct. A leaf makes no decisions and
carries no test file, per `AGENTS.md`.

### 13.2 — the bridge the tooling can see

| File | Role | Collaborators / why |
|---|---|---|
| `bridges/voiceover/pyproject.toml` | declaration only | The `[tool.screen-readers-mcp.bridge]` block spec 0042 requires. **Contains no Python and never will**: `scripts/bridges.py` reads `pyproject.toml` per bridge directory, so this is the file the tooling looks in. See Honest limits. |
| `bridges/voiceover/Package.swift` | build manifest | The module graph above — the architecture test. |
| `bridges/voiceover/build.sh` | build script (promoted) | Assembles the `.app`, `.appex` and framework from SwiftPM products. Carries the bundle-shape findings of spec 0041 A1: sandboxed, **no** network entitlement, **no** `AudioComponentBundle`. |
| `bridges/voiceover/VoiceOver.sdef` | reference (kept) | The dictionary this repo otherwise does not have. |
| `bridges/voiceover/README.md` | documentation | Build, register, remove; the two failure flags. |

**The extension's own hexagon**, per Part 3. The spike's `CaptureAudioUnit` did
all four layers at once; this is the same code, decomposed so the layers are
visible. `Sources/CaptureVoice/`:

| File | Role | Collaborators / why |
|---|---|---|
| `Domain/Ports/UtteranceSink.swift` | port | **Text output.** Where a captured utterance goes. Deliberately a port with two adapters, because the spike emits two ways on purpose and both must keep working. |
| `Domain/Ports/Synthesizer.swift` | port | **Audio output.** Given an utterance and a voice, produce PCM buffers and say when it is done. |
| `Domain/Ports/VoiceCatalogue.swift` | port | what voices exist here — the input `VoiceChoice` decides against. |
| `Domain/Ports/CaptureModeSource.swift` | port | is silence in force right now? |
| `Domain/Entities/Utterance.swift` | entity | **Input, made a value**: the SSML, the plain text, the language, the requesting voice, and the bridge-assigned sequence. |
| `Domain/Entities/SsmlDocument.swift` | entity | **Processing.** Parses the SSML: plain text, and `xml:lang` when present. Pure, and carries the finding that **VoiceOver's SSML has no `xml:lang` at all** — so "unknown" is the normal answer and must not be read as licence to pick a default. |
| `Domain/Entities/VoiceChoice.swift` | entity | **Processing.** Picks the re-speaking voice: never one whose identifier ends in ours (re-entrancy excluded by construction, not by naming an Apple voice that may not exist elsewhere), the language's **default** voice first because a listed voice can fail to synthesize, and the system's current language when the utterance does not say. Pure; this is where the Arabic-reading-Portuguese bug is a test. |
| `Domain/Entities/AudioRing.swift` | entity | **Audio output.** Single-producer/single-consumer ring; the consumer uses `trylock` and never waits. `final`, so the render block's call is statically dispatched. |
| `Domain/Controllers/CaptureController.swift` | controller | **The orchestrator, and the class the spike did not have.** One utterance in; text out through `UtteranceSink` **always**; re-synthesis started through `Synthesizer` into the ring **only when not silent**. Unit-tested end to end against four fakes, with no audio device and no VoiceOver. |
| `Adapters/CaptureAudioUnit.swift` | adapter | The AudioToolbox edge, and now thin: bus and format negotiation, the request and cancel entry points, and the render block. Keeps the `PRIO_DARWIN_BG` escape, the host-settled output format read at `allocateRenderResources`, and the bounded wait inside the render block. Its only collaborator there is the concrete `AudioRing`. |
| `Adapters/AVFoundationSynthesizer.swift` | adapter | Implements `Synthesizer`. **One `AVSpeechSynthesizer` per utterance** (a shared one, stopped and immediately rewritten, stalled for seconds), the completion backstop through the delegate as well as the zero-length buffer, the boundary ramps, and format conversion to whatever the host settled. |
| `Adapters/AVSpeechVoiceCatalogue.swift` | leaf adapter | `AVSpeechSynthesisVoice.speechVoices()`. |
| `Adapters/ContainerFileUtteranceSink.swift` | adapter | JSON lines into the extension's own container — the only door, since a network-entitled extension is silently skipped. |
| `Adapters/OsLogUtteranceSink.swift` | adapter | the second route, which works under the sandbox when the file does not. |
| `Adapters/FanOutUtteranceSink.swift` | adapter | both of the above, so "emit two ways" is a composition rather than an `if`. |
| `Adapters/MarkerFileCaptureModeSource.swift` | adapter | the marker file 13.6 writes. Silence stays **opt-in**: the default cannot be the setting that mutes a screen reader. |
| `Adapters/AudioUnitFactory.swift` | adapter | the extension's principal class. |
| `Sources/CaptureVoiceExtension/main.swift` | leaf | The stub that anchors the framework — the audio unit must live in a framework or in-process loading cannot find it. |
| `Sources/CaptureProbe/main.swift` | diagnostic (**kept**) | Lists voices and enumerates speech audio components, so *"the extension never ran"* and *"VoiceOver ignored it"* stay separable. |


`Tests/CaptureVoiceTests/` mirrors that tree file for file, as everywhere else:
`SsmlDocumentTests` (no `xml:lang` is the normal case), `VoiceChoiceTests` (ours
is never chosen; the language default wins; the current language is the fallback),
`AudioRingTests` (wrap-around, overflow accounting, the fade-out tail,
`truncateWithFade`, and that the consumer never blocks), and
`CaptureControllerTests` (silent emits text and no audio; non-silent emits both;
a cancel is an ordinary path and not a fault).

**Deleted:** `drive.sh` and `keyboard.sh`. Their findings are written into specs
0041 and 0043, and their function is replaced by the bridge itself.

**Two amendments to the table above, made while implementing 13.2 on
2026-08-29**, each riding in the PR with its why, per the workflow rule:

1. **`Adapters/CaptureEventLine.swift` is added** — a named supporting construct
   in the adapters layer: the one rendering of a `CaptureEvent` as a JSON line,
   used by both sinks. The table lists the two sinks and no shared renderer,
   because in the spike the rendering lived in the single `note()` both routes
   went through, and splitting the sinks split that. The two routes emitting the
   **same bytes** is precisely what makes them interchangeable when the sandbox
   denies one of them, and a property held by two copies of a function lasts
   until somebody edits one of them. It is an adapter-layer construct and not a
   domain one for the same reason JSON-lines framing is an adapter in the NVDA
   bridge: JSON is a wire vocabulary. It carries a test.
2. **The extension stub is `Sources/CaptureVoiceExtension/Stub.swift`, not
   `main.swift`** — SwiftPM identifies *any* `main.swift` as an executable
   target and warns about the manifest, while an `.appex`'s entry point is
   `_NSExtensionMain` and the target must therefore be a library. The name was
   the spike's; the constraint is SwiftPM's.

**Measured after the refactor, on 2026-08-29, on the same machine within the
same minute** -- because a decomposition of working audio code is exactly the
kind of change that is verified by assertion and regresses in seconds. The old
spike's probe was rebuilt from git and interleaved with the new one, five runs
each, same utterance:

| | Old (spike) | New (decomposed) |
|---|---|---|
| Added latency, first sample | 0.207 -- 0.231 s | 0.219 -- 0.237 s |
| Audio produced | 23,552 frames, peak 0.557 | identical |
| Realtime contention drops | 0 | 0 |

Parity, within noise. Two things were found by measuring rather than reasoning,
and neither was guessable:

1. **The first `AVSpeechSynthesisVoice(language:)` in a process costs about
   150 ms; every one after it costs 0.4 ms.** The system relaunches this
   extension freely, so without intervention the FIRST utterance after every
   relaunch is 150 ms late -- in the one place a screen-reader user notices,
   between a keystroke and the answer. `CaptureController.warmUp()` pays it at
   construction instead, off the request path. The probe warms up too, or its
   stopwatch reports a process start-up cost as per-utterance latency: that
   mis-measurement read as a 0.35 s regression against spec 0041's 0.218 s, and
   there was no regression at all.
2. **`VoiceChoice.resolve` takes its candidate list as an autoclosure**, because
   rule 2 means the common path never needs it and enumerating every voice is
   work done inside the user's screen reader once per utterance. The rules stay
   in one pure place; only the fallback pays.

**What the promotion deliberately did NOT rename.** The app bundle
(`VoiceOverCaptureSpike.app`), the app and extension bundle ids, and the declared
voice identifier are all unchanged, `spike` and all. VoiceOver stores the voice a
user selected **by an identifier derived from the extension's bundle id**, so
renaming any of it makes the selected voice vanish from VoiceOver's list and
costs every user a trip to VoiceOver Utility. 13.2 promotes code; **13.11 owns
packaging and identifiers**, and is where that one-time cost is paid once rather
than twice. Everything that does not affect the published identifier *was*
renamed — the Swift module is `CaptureVoice`, matching its SwiftPM target.

**The extension gains unit tests here**, per Part 3's element 1: the spike had
none because it was throwaway, and the six fixes that each cost a live round
against a real reader become assertions rather than comments. This is the whole
reason spec 0043 kept the code instead of only the measurements.

**Amendment to board 13.2, with its why.** That entry says to delete the probe
along with the driver and the keyboard script. **The probe is kept**, because
checklist rule (c)(4) makes it a checklist *dependency* — it is what answers
"is the capture voice published?" — and the 2026-08-22 rule says a live
checklist's dependencies are versioned rather than improvised.

**Tier declaration:**

| Tier | Hosts | Tools | Tasks |
|---|---|---|---|
| `headless` | `macos` | `swift` | `swift test --package-path bridges/voiceover` |
| `package` | `macos` | `swift`, `codesign` | `bash bridges/voiceover/build.sh` |
| `live` | `macos` | — | the live-VoiceOver scenarios, opt-in |

Reason string for all three: *"VoiceOver is macOS, and the bridge is Swift
against macOS frameworks."* Verified by the doctor on both hosts: on macOS two
bridges are selected with NVDA's `live` tier skipped in NVDA's own words; on
Windows, VoiceOver is skipped entirely in its own words.

### 13.3 — the wire contract's second binding

Module `ScreenReaderWire`. Hand-written per spec 0043, gated against
`specs/wire/v1/schema.json` by `scripts/drift.py`, because no language server
crosses this boundary any more than it crosses the Go↔Python one.

| File | Role |
|---|---|
| `ProtocolVersion.swift` | entity — the version constant and the equality rule |
| `Envelope.swift` | entity — `Request`, `Response`, and the exactly-one-of `result`/`error` |
| `ValidationError.swift` | entity — the failure type `from_dict`'s Swift counterpart raises |
| `Command.swift` | entity — the command-name enum. **`Request.cmd` stays a raw `String`**, so an unknown command is a clean error rather than a decode crash |
| `Capability.swift` | entity — the capability vocabulary and its set, retaining unknown strings |
| `CaptureMode.swift` | entity — `silent` / `live` |
| `SpeechEntry.swift` | entity — the entry shape `getSpeech` and friends share |
| `Commands/<Command>.swift` | entity — one file per command, holding **its** params and result together, mirroring `domain/controllers/commands/` and the rule that a DTO lives with what owns it |

Codable conformance and validation live here; **framing does not** — that is
`JsonLinesChannel`, an adapter, for the same reason it is one in the NVDA bridge.

`scripts/drift.py` gains a third comparison. Its failure message names the
schema, the binding and the field, since a drift an agent cannot locate is a
drift it will paper over.

### 13.4 — channel and session

**Ports** (`Sources/VoiceOverBridgeDomain/Ports/`)

| File | Role | Collaborators |
|---|---|---|
| `Clock.swift` | port | `now()`, `sleep(_:)`. Injected, never patched. |
| `MessageChannel.swift` | port | `send`/`receive`; owns `Timeout` and `ChannelClosed` in the same file. |
| `Transcript.swift` | port | the human-readable session record; supplies `logPath`. |
| `AdapterFactory.swift` | port | owns `AdapterSet`. Built by `Wiring`; called by the `hello` handler once the mode is known. |
| `SessionSignals.swift` | port | session-start and session-end cues for the human. |
| `BridgeConfig.swift` | port | endpoint kind and name, the attended flag. |
| `EventBus.swift` | port | session activity, for the dialog to observe. |

**Entities**

| File | Role | Why it is an entity |
|---|---|---|
| `LocalSocketPath.swift` | entity | The POSIX rendezvous derivation, pure, taking `LocalSocketDirs` **values**. The deliberate mirror of the server's `local_socket.go`: both halves must compute it identically or never meet, so both compute it in tested domain code and neither reads the environment to do it. Owns the 103-byte limit, checked at construction. |
| `TeardownReason.swift` | entity | every way a session ends. |
| `ConnectionMode.swift` | entity | silent / live, and the defaults each implies. |

**Controllers**

| File | Role | Collaborators |
|---|---|---|
| `Session.swift` | controller | Lifecycle only: handshake, one dispatch loop over a pre-hello/established state, the heartbeat and inactivity watchdogs, and teardown that runs restoration on **every** path. Holds ports; never a concrete adapter. |
| `Commands/CommandHandler.swift` | port-shaped interface | The handler protocol plus `CommandError`. `resetsInactivity` and `availableBeforeHello` are declared here so the loop needs no `if cmd == …`. No test file, like a port. |
| `Commands/SessionContext.swift` | **parameter object** | The per-session bundle — clock, transcript, speech buffer, `AdapterSet` — plus exactly one lifecycle capability, `close(reason)`. **Not an adapter**: it does no IO. This is the mislabelling `AGENTS.md` records as a learned mistake, named correctly here. |
| `Commands/Registry.swift` | controller | An explicit hand-written map, read top to bottom. No decorator registration. |
| `Commands/Hello.swift` | controller | The bootstrap command. Holds the `AdapterFactory`, builds the adapter set from the declared mode, populates the context, and composes `HelloResult` — reader identity, the capability set for this build, `attended`, `silenceCap`. |
| `Commands/Ping.swift` | controller | The only handler with `resetsInactivity == false`. |
| `Commands/Echo.swift`, `Commands/Bye.swift` | controllers | |

**Adapters** (`Sources/VoiceOverBridgeAdapters/`)

| File | Role | Collaborators |
|---|---|---|
| `Ports/Transport.swift` | adapter seam | bytes in, bytes out. |
| `Ports/Listener.swift` | adapter seam | accept one connection. |
| `Ports/FileWriter.swift` | adapter seam | for the transcript. |
| `JsonLinesChannel.swift` | adapter | Implements `MessageChannel` over `Transport`. Framing and encoding decisions; unit-tested against a fake transport. |
| `LocalSocketListener.swift` | adapter | **Every listener obligation `protocol.md` §1 states**: create the directory mode `0700`, unlink the socket path before binding, unlink again on exit. Holds them because they are decisions. |
| `UnixSocketBinder.swift` | leaf adapter | bind, listen, accept. No decisions, no test file. |
| `TCPListener.swift` | adapter | the loopback alternative the dialog selects. |
| `TCPBinder.swift` | leaf adapter | |
| `BridgeServer.swift` | adapter | The accept loop, wrapping each session so **no session fault can break it** — lane 1's crashed-client lesson, carried over rather than re-learned. |
| `FileTranscript.swift` | adapter | transcript vocabulary, over `FileWriter`. |
| `TextFileWriter.swift` | leaf adapter | |
| `RealClock.swift` | leaf adapter | |
| `SimpleEventBus.swift` | adapter | |
| `VoiceOverAdapterFactory.swift` | adapter | Implements `AdapterFactory`. **The only place that knows what a mode means**, because mode is known only after `hello`. |

### 13.5 — the capture feed

| File | Role | Collaborators / why |
|---|---|---|
| `Ports/SpeechSource.swift` | port | start/stop and delivery; owns `CapturedUtterance` (text, `emittedAt`, the raw SSML, the voice). |
| `Entities/SpeechBuffer.swift` | entity | Append-only, unbounded within a session, half-open ranges, `emittedAt` per entry. **It assigns the indices**, and its header says why: the extension's sequence counter restarts whenever the system relaunches it, so a bridge that trusted those numbers would have its ordering reset without warning. |
| `Entities/SpeechText.swift` | entity | SSML → the plain text an entry carries. Pure, and the one place `<prosody>`, `<break>` and entity decoding are decided. |
| `Adapters/Ports/LineTailer.swift` | adapter seam | deliver appended lines from a file. |
| `Adapters/ContainerFileSpeechSource.swift` | adapter | Every decision: JSON parsing, discarding the extension's own counter, mapping to `CapturedUtterance`. Unit-tested against a fake tailer — so the capture feed's logic is tested with no extension and no VoiceOver. |
| `Adapters/FileLineTailer.swift` | leaf adapter | real reads on the container file. |
| `Commands/GetSpeech.swift`, `GetLastSpeech.swift`, `GetNextSpeechIndex.swift`, `WaitForSpeech.swift`, `WaitForSpeechToFinish.swift` | controllers | one file each, one test each. |

The container file — not a socket — is the only door: an extension holding
`com.apple.security.network.client` is silently skipped by macOS (spec 0041, B1).

### 13.6 — capture mode, hard invariant 3, and the silence cap

| File | Role | Collaborators / why |
|---|---|---|
| `Ports/SilenceControl.swift` | port | `suppress()`, `passThrough()`, `isSuppressing`. Separate from `SpeechSource` because capture is **identical** in both modes here — only rendering differs, and the extension does the rendering. |
| `Ports/ProviderLifecycle.swift` | port | **Element 2, named rather than hidden inside a health check.** `state() -> ProviderState`, `register()`, `unregister()`. Detection and installation are one component because they are one state machine, and the dialog's capture-voice row is a view of it. |
| `Entities/ReaderCondition.swift` | entity | The named conditions: `scriptingChannelDead`, `captureVoiceNotSelected`, `providerNotRunning`. **This entity is spec 0041's sharpest requirement made structural** — each is reported by name, with its recovery, instead of surfacing as an empty read-back. |
| `Entities/ProviderState.swift` | entity | The lifecycle as a state machine: `notRegistered` → `registered` → `published` → `selected` → `capturing`. Pure, and the point of it is that **each state has a different diagnosis and a different instruction for the human** — "registered but not published" is a build problem, "published but not selected" is a settings-pane problem the bridge cannot fix, and "selected but not capturing" is a dead provider that only a reader restart re-binds. One boolean would collapse three different answers into one unhelpful one. |
| `Entities/SilenceCap.swift` | entity | `protocol.md` §6.1 — the warn and lift thresholds and the "time since the human last heard their own machine" clock. Reset only by sound the human actually hears. |
| `Adapters/MarkerFileSilenceControl.swift` | adapter | the marker file the extension reads, over `FileWriter`. |
| `Adapters/Ports/ProcessRunner.swift` | adapter seam | run a tool, return its output. |
| `Adapters/PluginKitProviderLifecycle.swift` | adapter | Every decision: what `pluginkit` output means, that **`lsregister -f` on the app must precede `pluginkit -a` on the extension and that the first alone is not enough** (spec 0041, C1), and that the published voice identifier is the extension's bundle id followed by ours — so it is matched **by suffix, never by the identifier the unit declared**. Unit-tested against a fake runner. |
| `Adapters/SubprocessRunner.swift` | leaf adapter | |

`Session` gains the **third watchdog**. macOS earns it: silent mode here renders
silence in the provider, so the reader is *mute* rather than merely intercepted,
and the lift is cheaper than NVDA's — delete the marker file and the next
utterance passes through, with the agent's indices and timestamps unchanged.
`attended` and `silenceCap` are both sent in `HelloResult`, derived from one
source (`BridgeConfig`), per §3's rule.

**Restoration is unconditional.** Pass-through is restored on every teardown
path, in a `defer`, because the default must never be the setting that mutes a
screen reader.

### 13.7 — input: commands

| File | Role | Collaborators / why |
|---|---|---|
| `Ports/GestureSender.swift` | port | `press(commands:)`; owns `GestureError` with `unknownCommand` and `scriptingChannelDead` as distinct cases. |
| `Ports/ReaderLiveness.swift` | port | `readerAnswersItsOwnName()`. The port that makes "the reader answers its own name but not its own state" a **detectable** condition rather than an empty answer. |
| `Entities/CommandVocabulary.swift` | entity | Gesture ids are **English command names** — the `SCRStringsToCommandsMap` vocabulary — and nothing else. Key combos are refused by name, because synthesizing one needs Accessibility and admitting them would silently widen the grant 13.8 exists to keep lazy. Also: there is no `GestureResolver` port, because VoiceOver does its own dispatch. |
| `Adapters/Ports/AppleScriptRunner.swift` | adapter seam | **The most load-bearing seam in the lane.** Run a script; return a string or an `OSStatus`. |
| `Adapters/VoiceOverGestureSender.swift` | adapter | Every decision, and therefore every one of spec 0041's error-code findings, as unit tests against a fake runner: `6` → unknown command; `-1728` / `-1708` → the scripting object model died; anything else → a reported fault. |
| `Adapters/VoiceOverLiveness.swift` | adapter | `tell application "VoiceOver" to return name`, and what its success alongside another call's failure means. |
| `Adapters/OSAScriptRunner.swift` | leaf adapter | ~15 lines. The only untestable part of the whole AppleScript edge. |
| `Commands/PressGesture.swift` | controller | dispatch, then the grace window. |
| `Commands/Observation.swift` | supporting construct | The grace window itself — the bookmark-dispatch-wait-report sequence shared with `typeText`. **`state` is never sampled**, because this bridge announces no `state` capability. |

### 13.8 — input: typing

| File | Role | Collaborators / why |
|---|---|---|
| `Ports/TextTyper.swift` | port | `type(_:)`; owns `TypingError.accessibilityNotGranted`. |
| `Ports/PermissionBroker.swift` | port | `status(of:)` and `request(_:)`; owns `Permission` (`automationVoiceOver`, `accessibility`) and `PermissionState`. **The macOS-only port with no NVDA analogue.** |
| `Adapters/Ports/EventPoster.swift` | adapter seam | post a key event. |
| `Adapters/AccessibilityTextTyper.swift` | adapter | chunking, Unicode injection, and the **lazy** grant check — the request is made here and only here, on the first `typeText` of a session. |
| `Adapters/CGEventPoster.swift` | leaf adapter | |
| `Adapters/TCCPermissionBroker.swift` | leaf adapter | `AXIsProcessTrustedWithOptions`, `AEDeterminePermissionToAutomateTarget`. |
| `Commands/TypeText.swift` | controller | `graceMs` defaults to 0, as the contract says. |

Its header carries the finding: **the target application rewrites what was
typed** — two lines sent to TextEdit came back autocapitalized. "Send this
keystroke" is not "this text arrives".

**The lazy-Accessibility lever, restated precisely** now that 13.9 also wants
the grant: *a session that only presses commands and reads speech never triggers
an Accessibility request.* Still true, still checkable, and still something no
NVDA bridge can say.

### 13.9 — focus

| File | Role | Collaborators / why |
|---|---|---|
| `Ports/FocusInspector.swift` | port | `focusInfo()`; owns `FocusSnapshot` (`name`, `role`, `states`, `value`, `appModule`). |
| `Adapters/Ports/AccessibilityTree.swift` | adapter seam | focused element of a pid, and an attribute of an element. |
| `Adapters/Ports/FrontmostApplication.swift` | adapter seam | who is frontmost. |
| `Adapters/VoiceOverFocusInspector.swift` | adapter | **Holds three seams and all the decisions**: `AccessibilityTree` when the grant exists, `AppleScriptRunner` (`text under cursor of vo cursor`) when it does not, and `FrontmostApplication` always. Fully unit-tested across both routes with no reader present. |
| `Adapters/AXAccessibilityTree.swift` | leaf adapter | **Uses `AXUIElementCreateApplication(pid)`, never `AXUIElementCreateSystemWide()`** — a comment states the measured `-25204 kAXErrorCannotComplete`, and that it is not `kAXErrorAPIDisabled`, so nobody "fixes" it with a permission. |
| `Adapters/WorkspaceFrontmostApplication.swift` | leaf adapter | `NSWorkspace`; no permission at all. |
| `Commands/GetFocusInfo.swift` | controller | |

**What it answers.** With Accessibility granted: `name`, `role`, `states` and
`value` from the accessibility tree, `appModule` from `NSWorkspace`. Without it:
`name` from the VoiceOver cursor and `appModule` from `NSWorkspace`, the rest
empty. **The bridge never requests the grant in order to serve focus** — it uses
one that typing already obtained.

**The two cursors, settled.** The dictionary exposes a `vo cursor` and a
`keyboard cursor`, each with its own `text under cursor`, and the accessibility
tree is a **third** view. `getFocusInfo` answers from the *keyboard/accessibility*
view, because that is the structured one and the one `role`/`states`/`value` come
from. An agent wanting VoiceOver's own rendering — what the user actually hears —
uses `pressGesture ["describe item in voiceover cursor"]` and reads the captured
speech. Both are available; the wire shape decides which one `getFocusInfo` means,
and this paragraph is where it is written down.

**No `state` capability**, per Part 2. Board 13.9 is amended accordingly.

### 13.10 — the control dialog, and the human channel

**Views** — driving actors, not adapters: they consume ports rather than
implement one, exactly as `views/bridge_dialog.py` does (spec 0011).

| File | Role |
|---|---|
| `App/BridgeApp.swift` | driving actor — the `NSApplicationDelegate` |
| `App/BridgeWindowController.swift` | driving actor — the window |
| `App/EndpointSection.swift` | driving actor — endpoint **kind and NAME**, per board 11.37: a dialog written from scratch pays nothing to include the name field the NVDA dialog must retrofit |
| `App/PreconditionsSection.swift` | driving actor — the three rows that exist only here |
| `App/ActivitySection.swift` | driving actor — connection state and session activity |
| `App/Wiring.swift` | **composition root** — picks adapters, stacks them, hands the controller its ports. Read top to bottom, it is the answer to "who connects what". Stays pure enough to type-check. |

| File | Role | Collaborators / why |
|---|---|---|
| `Ports/Announcer.swift` | port | `announce(_:)` — the bridge→human channel. |
| `Ports/UserPrompter.swift` | port | `askUser` / `waitForUserReply`; owns the prompt and reply types. |
| `Ports/ReaderScriptingSetting.swift` | port | is AppleScript control of VoiceOver enabled? Returns *unknown* as a third answer. |
| `Entities/Precondition.swift` | entity | The **unfixable precondition** vocabulary: things the bridge can observe, cannot set, and cannot work without. AppleScript enablement and capture-voice selection are both instances; naming the kind is what stops the dialog growing three unrelated ad-hoc rows. |
| `Adapters/Ports/SpeechOut.swift` | adapter seam | speak these words on this machine. |
| `Adapters/SynthesizerAnnouncer.swift` | adapter | **Speaks with the bridge's own synthesizer, outside VoiceOver entirely.** That is what makes `announce` audible in a silent session, where the provider is rendering the reader mute — a cleaner bypass than NVDA's, and the reason `interact` is announceable at all. Excludes our own capture voice by identifier suffix. |
| `Adapters/AVSpeechOut.swift` | leaf adapter | |
| `Adapters/AppKitUserPrompter.swift` | adapter | the prompt window and its reply. |
| `Adapters/Ports/PlistReader.swift` | adapter seam | read a plist at a path. |
| `Adapters/VoiceOverPrefsScriptingSetting.swift` | adapter | Knows both Sequoia locations — the Group Container `default.plist` key `SCREnableAppleScript`, and the legacy `/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled` — and that the Sequoia move was an **addition**, not a replacement. |
| `Adapters/FilePlistReader.swift` | leaf adapter | |
| `Commands/Announce.swift`, `AskUser.swift`, `WaitForUserReply.swift` | controllers | |

The dialog carries everything spec 0011 gives the NVDA bridge, plus the three
rows that exist only here: whether AppleScript control is enabled, which
permissions are granted with a way to trigger the requests, and whether the
capture voice is selected — the last of which is a **view of `ProviderState`**
(13.6) rather than a boolean the dialog computes for itself.

**The main-thread rule of Part 3, element 5, is enforced here**: the views
observe the session through `EventBus` and marshal every update to the main
thread, and no view call blocks it. Teardown paths are fire-and-forget, so a
main-thread caller can never wait on the thread it is joining.

### 13.11 — packaging, CI, guidance, and the live run

| File | Role | Collaborators / why |
|---|---|---|
| `Sources/VoiceOverBridgeDomain/Entities/Documents/*.md` | documents | The persona guidance texts, as **files**, per `AGENTS.md`: a document served to an agent is never a string literal. |
| `Entities/GuidanceDocuments.swift` | entity | Loads them and **throws** when one is missing, rather than returning `""` — an empty document reads to an agent as "this reader has nothing to say", which is a much worse answer than "the build is broken". |
| `Ports/…` | — | none needed; documents are pure resources. |
| `Commands/GetGuidance.swift` | controller | Takes no parameters; the persona was fixed at `hello`. |
| `server/config/defaults.json` | shipped config | gains `{"name": "voiceover", "endpoints": ["local:voiceoverMcpBridge", "tcp:127.0.0.1:8765"]}`. |
| `.github/workflows/*` | CI | a macOS job that builds and headless-tests the bridge. |
| `scripts/drift.py`, `poe conformance` | gates | the real Go binary against the real Swift bridge. |

**The endpoint name is `voiceoverMcpBridge`**, satisfying `protocol.md` §1's
`<reader>McpBridge` convention against `reader.name = "voiceover"`, and resolving
to `~/.screenreader-mcp/voiceoverMcpBridge.sock` on this host.

**Sharing TCP port 8765 with the NVDA reader is deliberate and safe**, and worth
one sentence because the reasoning is not obvious: the two readers cannot run on
one host — NVDA is Windows, VoiceOver is macOS — so the defaults cannot collide
in practice, and a second default port would be a divergence bought for nothing.

**The third rendering of the embedded-document trap.** Go embeds at compile time;
Python ships and reads at run time; **Swift resolves through `Bundle.module`**,
which is a SwiftPM-generated resource bundle that `build.sh` must copy into the
app's `Contents/Resources`. If it does not, the failure is a runtime trap rather
than a compile error. So `build.sh` copies it, `GuidanceDocuments` throws rather
than returning empty, and `scripts/doctor.py` counts
`bridges/voiceover/Sources/**/Documents/*.md` among the bundle's build inputs —
the same staleness check the server's `//go:embed` documents already get.

**What the guidance document says**, since this is where the toggles become
usable: gesture ids on this reader are **English command names**, not keystrokes;
the shape of the 415-command vocabulary; **the toggles that matter and the fact
that each announces its own result**, which is how an agent reads state on a
reader that cannot be asked; and that braille content, a reader log and a
settable state do not exist here.

**Two costs this entry states rather than discovers:** updating the provider
costs a VoiceOver restart, every time, for every user; and VoiceOver crashes
routinely, which is why the checklist rules in Part 1(c) exist.

**Amended 2026-08-29 by [spec
0047](0047-selecting-the-capture-voice-without-a-human.md): the restart is
SCRIPTED, not manual.** `tell application "VoiceOver" to quit` then `activate`
completes in 13.8 s and needs only the AppleEvents grant the bridge already
holds — never Accessibility, which is the grant 13.8 exists to keep lazy. The
cost stands; what changes is who pays it, and this entry's documentation should
say "the bridge restarts the reader" rather than "ask the user to restart the
reader". The same spec records a risk that lands on **13.7** rather than here,
and it is the more serious of the two findings.

### 13.12 — can VoiceOver be asked what mode it is in?

A **measurement entry**, in the shape of spec 0041 and for the same reason: the
alternative is to assume. One question — **does the preferences plist track a
toggle at the instant it fires, or only later?** — with a probe and a pass
condition, run against a live reader.

If it is live and prompt, a **read-only** `state` becomes implementable and earns
its own entry. If it is not, the answer is written down permanently and nobody
re-opens it. Either way lane 3 ships v1 without `state`, and the question is
settled by evidence rather than by this spec's judgement.

It adds no production class, so it carries no layout — exactly as spec 0041 did.

## Testing

`Tests/` mirrors `Sources/` file for file, one test module per source module, and
a source file with no test file is a deliberate statement — all unchanged from
`AGENTS.md`. The lane-specific parts:

- **Fakes** live in a `Fakes` test target, one file per fake, mirroring the port
  they stand in for, each conforming to the port's protocol.
- **`FakeClock.sleep` is an instant advance**, so the watchdog and grace-window
  tests run in microseconds.
- **`Tests/Integration/`** holds headless scenarios that drive the real session
  stack over a `LoopbackTransport` with a fake reader edge. They run in CI on
  macOS. Live-VoiceOver scenarios live behind the `live` tier and never run in
  CI.
- **swift-testing preferred, XCTest acceptable.** The choice does not change the
  layout, and 13.4 makes it once for the lane.
- **No test compares reader strings.** VoiceOver renders under the tester's own
  locale — this machine speaks Portuguese — so structure is compared and text
  never is, which is `scripts/live_pages/README.md`'s rule in its macOS instance.

## What is deliberately not built

- **A `BrailleSource` port.** Part 1(b).
- **A `state` capability, and any toggle-based `setState`.** Part 2.
- **A `getLog` over the unified system log.** Part 2 — a different thing wearing
  that name.
- **`getDocumentSnapshot`.** It needs a full accessibility-tree walk that must
  not move the reading position and must not speak; that is a large piece of work
  behind the grant 13.8 keeps lazy, and no lane-3 entry covers it.
- **Guidepup's portable-preferences mechanism**, which replaces the user's own
  VoiceOver configuration. Recorded in Part 2 so it is refused explicitly rather
  than rediscovered as an idea.
- **A bridge-side panic gesture.** Command-F5 is the OS's own, and a dead
  provider falls back to a working voice rather than to silence.
- **Generating the Swift wire binding.** Spec 0043 says hand-written; the drift
  gate is what makes that safe, and a second generator is a second thing to
  maintain.

## Honest limits

- **`bridges/voiceover/pyproject.toml` contains no Python.** `scripts/bridges.py`
  reads a bridge's declaration from `pyproject.toml`, so that is where the
  declaration goes. It is a wart: a `pyproject.toml` in a directory with no
  Python is an invitation to treat it as a Python project. The cheap fix — teach
  `bridges.py` to accept a `bridge.toml` as well — is **not taken here**, because
  it is a change to shared tooling made for a single case. If a second non-Python
  bridge appears, that is the moment.
- **`getFocusInfo` answers differently depending on a permission.** Richer with
  Accessibility, thinner without. The wire shape has nowhere to say which route
  answered, so the guidance document and the control dialog carry it. An agent
  reading empty `role` and `states` cannot tell "no grant" from "the element has
  none".
- **The three named conditions are detected, not prevented.** Nothing the bridge
  does stops VoiceOver's scripting object model from dying, and only a reader
  restart recovers it.
- **`AXIsProcessTrusted` was already `true` for the shell used to measure**, so
  the AX route was proven on a machine that already holds the grant. The bridge
  is a different bundle and needs its own; that the API works says nothing about
  how the grant is obtained.

## Open questions

1. **Reader toggles as observations.** If lane 3 later wants state, the shape is
   named toggles carrying *last observed* values and the instant each was
   observed — explicitly a cache, never a live read — and not `getState`'s four
   fields. A v1-successor conversation, recorded so it is not lost.
2. **Distribution.** Registration needs no Developer ID, no notarization and no
   Team ID for local use (spec 0041, C1). What shipping to other people costs was
   never measured, and 13.11 does not answer it.
3. **The reverse direction and tail latency of the container file.** Spec 0041's
   B2 measured the extension→bridge direction only.

## Board amendments this spec makes

Each rides in the PR that carries this spec, per hard invariant 6.

- **13.2** keeps `Sources/CaptureProbe/` rather than deleting the probe, because
  a live-checklist dependency is versioned.
- **13.9** becomes focus-only. `getState` is removed from it; the reason is
  Part 2.
- **13.11** gains the `guidance` capability and its documents, because the
  document can only be written against a vocabulary that already works.
- **13.12** is new: the plist-liveness measurement.
- **13.1** is marked Done by the PR that carries this file, and so is **13.2**:
  the spec and its first implementation ship together, which is what the
  workflow's "spec before code, on the implementing PR's branch" means when the
  spec covers a whole lane.
