# Spec 0048 — pressing a chord on a reader whose gestures are command names

**Status:** **Decided and implemented** — board entry 13.17, 2026-08-31. §7's
open questions were settled by asking what lane 1 does (see §7), and the
amendments made while implementing are recorded in §8 with their reasons, as the
workflow requires.

**Board entry:** [13.17](../ROADMAP.md), lane 3. **A v1 blocker for the `user`
persona.**

**Raised by:** Marlon, 2026-08-31, in the sharpest available form:

> All blind users will use chords to operate, no matter what. If chords aren't
> pressable, we need a driver.

He is right, and the entry exists because the gap had sat unnoticed through four
entries while being described as something it is not.

## 1. The gap, measured

*Written before the entry was implemented, and kept in the present tense as the
record of what was true on 2026-08-31 before this PR.*

Neither of this bridge's two input routes can send Command-L.

| Route | What it does | Why a chord does not come out of it |
|---|---|---|
| `pressGesture` | dispatches VoiceOver's own command names through the reader's `commander object` | the vocabulary has single keys and modifier commands, and **the modifiers do not compose** — measured 2026-08-30, four runs, re-runnable as `bash scripts/voiceover_modifiers.sh`. `CommandVocabulary` therefore refuses a keystroke id outright |
| `typeText` | synthesizes a `CGEvent` with `virtualKey: 0` and a **Unicode payload** (`CGEventPoster.post(unicode:keyDown:)`) | that is how a *character* arrives. It never presses a key with a modifier held |

So the bridge can drive the reader, and can enter text, and **cannot press
Command-L, Command-F, Command-W or Command-T** — which is how everybody actually
uses a Mac.

### 1.1 It is OUR gap, not the platform's, and the wrong framing is why it lasted

Core Graphics sends chords perfectly well given a virtual keycode and
`event.flags`; this bridge already holds the Accessibility grant that costs.
During 13.11's live run the limitation was stated as though it were a fact about
VoiceOver —

> I cannot press Cmd-L, because chords are not expressible through
> `press_gesture` on this reader

— and the guidance document shipped a sentence that was worse, because it pointed
at a route that does not exist either:

> A chord needs `type_text`'s route, which synthesizes real system events and
> costs the Accessibility grant.

`typeText`'s route synthesizes events, and it cannot press a chord. **A true
statement about one command was generalised into a false statement about the
bridge**, and because it read like a platform limit nobody looked for the missing
feature behind it. That sentence is corrected on this branch ahead of the code,
because an agent reading it today would draw the same wrong conclusion.

### 1.2 Why it blocks v1 for the `user` persona

That stance's whole claim is that a task is driven with what an ordinary user
has. On macOS that includes chords in the first minute of any session: opening a
location, finding on a page, switching windows, closing a tab. A `user` run that
cannot press them is not a *restricted* stand-in but an *incomplete* one — and
worse, its "the task failed" findings would be about the bridge rather than about
the interface under test, which is the one thing a persona's report must never
be.

## 2. Decisions

### 2.1 Keystrokes ride on `pressGesture` — they are not a new command

`protocol.md` §5 calls a gesture id **"the reader's own user-facing command
notation"**, and on NVDA that notation *is* keystrokes (`kb:NVDA+f7`). Accepting
them here is therefore **consistent with the contract rather than a stretch**;
`CommandVocabulary`'s blanket refusal is the thing that has to narrow.

**A new wire command was considered and declined.** `pressKeys` would mean a
schema change propagated through three bindings and the server, to express
something the existing command already means. It would also push a bridge
implementation detail — *which of my two routes carries this* — into the agent's
vocabulary, when the whole point of a gesture id is that the bridge decides how
to deliver it.

**What changes for an agent** is documentation, not shape: this reader's guidance
gains a section saying that command names go to the reader and keystroke notation
goes to the system, and that both are `pressGesture`.

### 2.2 The notation, and how it is told apart from a command name

A keystroke id is `+`-joined, lower-cased, modifiers first:

```
command+l          control+option+space          shift+command+4
```

Modifiers: `command`, `control`, `option`, `shift`, `fn`. The key is a single
character, or one of the named keys the vocabulary already needs (`space`,
`return`, `tab`, `escape`, `delete`, `forwarddelete`, `left`, `right`, `up`,
`down`, `home`, `end`, `pageup`, `pagedown`, `f1`–`f20`).

**The discriminator is the existing hyphen rule, applied to `+`:** a `+` counts
as keystroke notation **only in an id with no spaces at all**. Every real command
name that carries a separator carries spaces too (`mute sound toggle`, `command
key`), and no command name in the 414-entry vocabulary is a bare `+`-joined
token. So `command key` still goes to the reader and `command+l` does not, and
the rule that decides is one this file already lives by.

**VoiceOver's own `VO-D` notation stays refused**, and by name. It is neither a
command the reader will dispatch nor a keystroke this bridge can construct
without knowing how the user has configured their VO modifier — which is exactly
the mistake `CommandVocabulary` was written to catch. The refusal message tells
the agent to send `control+option+d` if that is what it meant.

### 2.3 The lazy-grant lever survives, and narrows by one sentence

13.8's claim is stated in eleven places across this bridge's source, tests and
manuals — **a count inherited from spec 0046's amendment 13 and found to be wrong
while implementing: it is 27 inside the bridge and 13 more outside it. See §8.6.**

> a session that only presses commands and reads speech never triggers an
> Accessibility request

It stays **true and checkable**, and it narrows: the grant is requested on the
first **keystroke**, exactly as on the first `typeText`. A session that presses
only reader command names and reads speech still asks for nothing, which is the
property worth having and the one the counting-broker scenario asserts.

**Every one of those statements is rewritten in the PR that adds the caller** — the obligation spec 0046's amendment 13 already placed on 13.14, now
falling due here first. A claim that quietly becomes false is worse than one that
was never made.

### 2.4 The hard part is the keyboard LAYOUT, and it must not be underestimated

A `CGEvent` carries a **virtual keycode**, and which keycode produces `l` depends
on the active layout. The maintainer's machine is Brazilian. **A hard-coded ANSI
table would pass review, pass every test written by whoever wrote the table, and
press the wrong key on his keyboard** — the exact shape of failure this lane keeps
paying for.

So the mapping goes through `TISCopyCurrentKeyboardInputSource` and
`UCKeyTranslate`, building a reverse map (character → keycode) for the layout that
is actually active. Two consequences:

- **The map is cached, keyed by the input source's id**, and the id is re-read per
  press. That is one cheap call, and it means switching layouts mid-session is
  handled without a notification observer to get wrong.
- **A character unreachable on the current layout is a NAMED failure**, never a
  wrong key. "This layout has no key that produces `\`" is a real answer an agent
  can act on; pressing something else is not.

Named keys (`return`, `f5`, the arrows) are layout-independent constants and skip
the translation entirely.

### 2.5 Modifiers are flags on the key event — **AMENDED: they are also pressed and released**

*The decision as proposed:* `event.flags = [.maskCommand]` on both the key-down
and the key-up of the main key. That is what menu shortcuts respond to and what
the system's own automation does. **Separate modifier key-down/up events were
considered and are not in v1** — a few applications watch for the raw modifier
transitions rather than the flags, and if one turns out to matter it is an
amendment with a measurement behind it, not a guess baked in now.

**The measurement arrived within the hour of the first live run, and it is not
the one that was anticipated.** Flags alone deliver the chord perfectly — the very
first `command+l` through the bridge opened Safari's location bar and VoiceOver
announced *"Abrir Localização…"*. What flags alone do **not** do is put the
modifier back. Measured 2026-08-31 on the maintainer's machine, straight after
that press:

```
CGEventSource.flagsState(.combinedSessionState)  ->  command: true
```

**Command was held down on somebody's own keyboard**, by this bridge, with
nothing anywhere saying so. Every keystroke on that machine afterwards was a
chord. The symptom that surfaced first was `typeText` reporting `typed: 11` into
an empty Safari address bar — no error, no speech, and a field the reader read
back as empty — because each character had arrived as a Command-chord. The
diagnosis took a `flagsState` read; nothing in the bridge, the reader or the
application could have named it.

That is not an application-compatibility nicety, which is the class of reason
this decision was deferred for. It is hard invariant 3's argument in a different
costume: a bridge gives the machine back. So **v1 posts the transitions**:

1. a `flagsChanged` per modifier, in a fixed order, each carrying the
   **cumulative** state so far — which is what such an event means;
2. the key down, then the key up, both carrying the full flags;
3. a `flagsChanged` per modifier in **reverse**, each carrying the state with that
   modifier removed, ending at `[]`.

**Step 3 runs even when step 2 failed**, from a `defer`, and its own failures are
swallowed: there is nothing a caller could do with "the chord failed AND the
release failed", and reporting the second in place of the first would hide the one
that matters. As a side effect this also satisfies the applications that watch raw
transitions, which was the deferred reason — but it is not why it was done.

**What should have caught it, and did not.** `scripts/voiceover_modifiers.sh` had
carried a header warning about exactly this hazard for a day — *"a sticky modifier
that stays down would make every subsequent keystroke on the machine a chord"* —
and that script proves the keyboard is clean after every probe. The instrument
written for **this** entry did not, on its first version, and so reported a
successful chord on a machine it had just broken. It does now, in the same shape:
one plain Delete after the chord must remove exactly one character. **A probe that
provokes a hazard must assert the hazard is gone**, and the sibling script was
already the worked example.

## 3. Class/file layout

The review gate. Every file the implementing PR adds or changes, with its role
and its collaborators.

### 3.1 Domain — `Sources/VoiceOverBridgeDomain/`

| File | Role | Collaborators / why |
|---|---|---|
| `Entities/Keystroke.swift` | **new** — entity | Parses `command+l` into modifiers and a key, and refuses a malformed id **by name**. Pure, no ports. Owns the modifier and named-key vocabulary. |
| `Entities/CommandVocabulary.swift` | entity — **amended** | Stops *refusing* keystrokes and starts **classifying**: returns `readerCommand(String)` or `keystroke(Keystroke)`. Keeps refusing `VO-D` by name (2.2). Its named refusal test is **deleted in the commit that makes the promise keepable** — the pattern 13.6 and 13.10 both followed. |
| `Ports/KeyPresser.swift` | **new** — port | `press(_ keystroke: Keystroke) throws`. The domain's way to press a chord, knowing nothing about `CGEvent` or keycodes. Owns its error type. |
| `Ports/AdapterFactory.swift` | port — **amended** | `AdapterSet` gains `keyPresser`. |
| `Controllers/Commands/PressGesture.swift` | controller — **amended** | Routes on the classification: a command name to `GestureSender` as today, a keystroke to `KeyPresser`. **Requests the Accessibility grant on the first keystroke of a session**, through the `permissions` broker already on the `AdapterSet` — the same shape `TypeTextHandler` uses, and the second and last caller of `request`. |

### 3.2 Adapters — `Sources/VoiceOverBridgeAdapters/`

| File | Role | Collaborators / why |
|---|---|---|
| `Ports/KeyboardLayout.swift` | **new** — adapter seam | `keyCode(for:) -> UInt16?` and `keyCode(named:) -> UInt16?`. The seam that keeps the decisions above it testable without a real keyboard. |
| `CurrentKeyboardLayout.swift` | **new** — LEAF adapter | `TISCopyCurrentKeyboardInputSource` + `UCKeyTranslate`, reverse map cached by input-source id. Makes no decisions; no test file, by the leaf rule. |
| `CGKeystrokePresser.swift` | **new** — adapter | IMPLEMENTS `KeyPresser`. Holds every decision: key → keycode through the layout seam, modifiers → flags, the down/up order, and the named failure when a character is unreachable. Unit-tested against fake seams. |
| `Ports/EventPoster.swift` | seam — **amended** | Gains `post(keyCode: UInt16, flags: CGEventFlags, keyDown: Bool) throws` beside the Unicode one. Two shapes, because they are two different events — and every decision stays above the seam, as 13.8's header requires. |
| `CGEventPoster.swift` | LEAF — **amended** | Implements the new shape. Still ~15 lines with nothing to decide. |
| `Wiring.swift` | composition root | Builds `CGKeystrokePresser` over `CurrentKeyboardLayout` and the existing poster; hands it to `VoiceOverAdapterFactory`. |
| `VoiceOverAdapterFactory.swift` | adapter factory | Carries the key presser into the `AdapterSet`. |

### 3.3 Tests

| File | Tier | Asserts |
|---|---|---|
| `Tests/VoiceOverBridgeDomainTests/Entities/KeystrokeTests.swift` | unit | parsing, modifier order independence, named keys, and that a malformed id fails **by name** |
| `Tests/VoiceOverBridgeDomainTests/Entities/CommandVocabularyTests.swift` | unit — amended | the classification, both ways; the space rule (`command key` is a command, `command+l` is not); `VO-D` still refused with its message |
| `Tests/VoiceOverBridgeAdaptersTests/CGKeystrokePresserTests.swift` | unit | flags assembled per modifier; down then up, both carrying the flags; **an unreachable character is a named failure and posts nothing** |
| `Tests/Fakes/KeyPresser.swift`, `Tests/Fakes/KeyboardLayout.swift` | fakes | one per port/seam, mirroring their files |
| `Tests/Integration/SessionRoundTripTests.swift` | integration — amended | a keystroke off a real wire reaches the **event** path and **not** the AppleScript runner; and the counting-broker scenario keeps its claim: a session of command names and speech reads is asked nothing |

### 3.4 Documents and instruments

| File | Change |
|---|---|
| `Entities/Documents/common.md` | the chord section rewritten: command names to the reader, keystroke notation to the system, both through `press_gesture`; the false `type_text` sentence gone |
| `bridges/voiceover/AGENTS.md` | the gesture and typing sections; the eleven-places claim narrowed (2.3) |
| `scripts/voiceover_chords.sh` | **new** — the versioned instrument: presses a chord into a scratch document and shows what arrived. A check's dependencies are versioned (the 2026-08-22 rule) |

## 4. The live checklist this earns

The one Marlon asked for on 2026-08-31, and it is the demonstration that the
entry worked: **open a URL in Safari with the keyboard alone.** `command+l`, then
`type_text` the address, then `return key` — the sequence an ordinary user
performs without thinking, and the one this bridge could not perform at all.

Plus: `command+f` on a page; a chord on a **non-US layout**, which is the check the
layout decision exists for.

## 5. What is deliberately not built

- **Separate modifier key events** (2.5) — flags only, until something measured
  needs more.
- **Key repeat / held keys.** A gesture is a discrete press and release; that is
  already the contract's position (`protocol.md`, and lane 1's `alt+tab` note),
  and holding a modifier across several keys stays inexpressible everywhere.
- **A keycode table in this repo.** The layout answers, or the press fails by
  name.

## 6. Honest limits

- **The layout map is only as good as `UCKeyTranslate`'s answer** for the active
  source. Dead keys and input methods that compose (Japanese, Chinese) are out of
  scope: a chord is a chord, but the reverse map for a *character* may be
  ambiguous or empty there, and the named failure is what an agent gets.
  **Measured on the maintainer's machine, 2026-08-31**, on
  `com.apple.keylayout.Brazilian-Pro`: 110 characters mapped; `a`, `l`, `f`, `t`
  and `4` on the same keycodes an American layout uses (ABNT2 is QWERTY, so the
  letters coincide — which is exactly why a hard-coded table would have *seemed*
  to work); `$` on the **shifted layer** of the `4` key; and **`ç` unreachable**,
  because it is composed rather than sitting on either plain layer. That last one
  is the named failure doing its job on a real keyboard, and it is what `press`
  reports instead of pressing something else.
- **Only the two plain layers are mapped** — unshifted and shifted. A character
  reachable only with Option held (`ç` above, and most accented characters on this
  layout) is unreachable to a chord and reported as such. `type_text` enters those
  characters perfectly well; what cannot be expressed is *chording* on one.
- **What arrives is still not what was sent.** `AccessibilityTextTyper`'s rule
  holds for this path too — the target application may rewrite, swallow or
  reinterpret. A check that needs to know what arrived asks the application or the
  reader.
- **This does not give VoiceOver's own commands a keystroke route**, and must not
  be used as one. `VO-D` stays refused; the reader's commands go to the reader by
  name, where they cost no grant.

## 7. The open questions, and how lane 1 settled them

Both were put to Marlon on 2026-08-31. His answer to each was the same: **find
out what NVDA does.** It does one thing, consistently, and it points the same way
in both cases — plus a third way nobody had asked about.

**What NVDA does with gesture nomenclature.** Its gesture ids are *keystrokes and
nothing else* — `NVDA+f7`, `control+l`, `escape`. There is no command-name
namespace on that wire at all: NVDA's internal script names
(`script_moveToNextHeading`) are never exposed as gesture ids. The bridge
normalises an id in `bridges/nvda/.../adapters/keyboard_gesture_name.py` — strip
a legacy `kb:` prefix, then `press_order` — and hands it to
`KeyboardInputGesture.fromName`; `inputCore.manager.emulateGesture` then decides
whether NVDA consumes the key (`NVDA+t`) or the application receives it
(`control+o`). **The bridge never classifies which.** One route, one verb, one
capability. The two readers are mirror images, and VoiceOver is the one that now
takes both notations.

### 7.1 One transcript verb, `gesture`, for both — Decided

Lane 1 writes `control+o` and `NVDA+t` on identical transcript lines, and a
transcript is read *across* readers: a verb only this bridge could emit would
make two runs of the same task structurally different for the same wire command.
The notation itself says which route an id took. `Transcript.gesture`'s doc
comment ("one command dispatched to the reader") was reworded in this PR so it
stops being false, and the line records the **canonical spelling** — what the
bridge understood — rather than an echo of what the agent typed.

The rejected alternative was a `keystroke` verb, on the argument that the two are
different acts against different targets at different permission costs. True, and
outweighed: the transcript's job is to let somebody reconstruct a run, and one
vocabulary shared with the other reader serves that better than a distinction the
id already carries.

### 7.2 One capability, `gestures` — Decided

Capabilities gate **command groups** (protocol.md §4), and both halves are the
same command. NVDA announces `gestures` for exactly this mix of ids. Splitting
would mean inventing a capability that gates a *notation*, propagating a schema
change through three bindings and the server, and making an agent ask "which kind
of gesture is this?" before every press. `hello` stays at six.

### 7.3 The key goes LAST — settled for free, and not by us

Asking the question turned up a rule this spec had assumed without noticing:
NVDA's `fromName` treats the **last** token as the key and every earlier one as a
modifier, which is why lane 1 carries `press_order` to hoist modifiers to the
front (NVDA's own normalizer sorts a gesture's parts alphabetically, so it holds
"read the whole window" as `b+nvda`, and pressing *that* presses NVDA with B
held). `Keystroke.parse` follows it. So `command+l` is the same string on both
readers in this contract, `l+command` is a named failure on both, and the order
of the modifiers among themselves is irrelevant on both.

## 8. Amendments made while implementing (2026-08-31), each with its why

1. **The layout seam is `key(for:) -> LayoutKey?`, not `keyCode(for:)` plus
   `keyCode(named:)`.** Two changes to §3.2's table.
   - **`keyCode(named:)` is gone from the seam**, and the named-key table lives in
     `CGKeystrokePresser`. §2.4 says named keys are layout-INDEPENDENT, so asking
     the layout about them is asking a question with a known answer — and putting
     a constant table in `CurrentKeyboardLayout` would put a decision in a **leaf**,
     which the layering rule forbids. A physical position is not a layout.
   - **The seam reports which LAYER the character sits on** (`LayoutKey` is a
     keycode plus `shifted`), which the original signature could not. Digits are
     unshifted on a Brazilian or American layout and **shifted** on a French
     AZERTY one, so a seam answering only a keycode would have made `command+4` a
     named failure on a machine where the person presses it daily. Reporting the
     layer keeps the decision — a shifted layer means an added `.maskShift` —
     above the seam, where it is an ordinary unit test.
2. **`Controllers/Commands/AccessibilityGrant.swift` is a new supporting
   construct**, and §3.1 has the handler call the broker directly. It is the rule
   `HumanWarning` (13.8) and `Observation` (13.7) were both created by: a decision
   two commands must not differ about becomes a file **at the entry that creates
   the second caller**. Two hand-written copies of a permission check would come
   to differ the first time one was reworded, and what they would differ about is
   whether somebody's machine raises a consent dialog.
3. **The grant is asked for ONCE PER BATCH, before the first dispatch**, rather
   than "on the first keystroke" inside the loop. Same argument as the vocabulary
   check that already ran up front: a mutating command should settle everything it
   can before anything moves, and a grant that failed in position three would
   leave the reader somewhere neither side asked for. So a batch mixing command
   names with a chord presses **nothing** when the grant is missing.
4. **`Gesture` — the classification — lives in `CommandVocabulary.swift`**, with
   `described` and `isKeystroke` on it. The repo's rule is that a type lives with
   the thing that owns it, and what owns this is the entity that decides it.
5. **A key with no modifier stays a COMMAND NAME**, which §2.2 implied and did not
   say. The `+` is the whole discriminator, so `return` alone is not keystroke
   notation — and that is the right answer rather than an accident of the rule:
   the vocabulary's 30 `… key` commands cost no grant, and routing a lone key
   through the event path would spend the grant for a keypress that never needed
   one. The guidance document says so in as many words.
6. **The "eleven places" figure in §2.3 was wrong, and it was inherited.** Spec
   0046's amendment 13 counted eleven; an exhaustive sweep found **27 inside this
   bridge** (source, tests and manuals) and **13 more outside it** — `specs/`,
   `ROADMAP.md`, the root `AGENTS.md` and five files in `scripts/`. All forty were
   rewritten in this PR. Two wordings would have escaped a literal search for the
   canonical sentence: `ROADMAP.md` and `scripts/voiceover_keyboard.sh` say "never
   *triggered*", and the root `AGENTS.md` says "never *asked for* Accessibility".
7. **The instrument is two files**, `scripts/voiceover_chords.sh` plus
   `scripts/voiceover_chord_press.swift`, on the precedent of `voiceover_focus.sh`
   plus `voiceover_ax_focus.swift`: the shell owns the scratch document and the
   safety, and the question needs Text Input Services and Core Graphics, which a
   shell cannot ask. The shell half's `report` mode presses nothing and is safe to
   run anywhere.
8. **Modifiers are pressed and released rather than merely flagged**, which is a
   reversal of §2.5 with a measurement behind it — the measurement §2.5 itself
   asked for. It is written up there rather than here because it changes a
   decision rather than a layout: the `EventPoster` seam gains a third shape
   (`postFlagsChanged(keyCode:flags:)`), `CGKeystrokePresser` owns the sequence
   and a table of the five modifier keycodes, and the release is in a `defer`. Two
   unit tests assert the whole ordered sequence and the release after a **failed**
   press, and `scripts/voiceover_chords.sh` proves the keyboard is clean again
   before it reports a result.
9. **`scripts/voiceover_modifiers.sh`'s header now says what its answer cost.**
   That probe measured a true fact about the reader's modifier commands, and §1.1
   records how it was generalised into a false claim about the bridge and then
   about the platform. The correction belongs in the file whose output produced
   it, where the next person to read the measurement will see it.
