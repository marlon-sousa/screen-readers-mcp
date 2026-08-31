# Spec 0048 — pressing a chord on a reader whose gestures are command names

**Status:** proposed — the layout below is the review gate, and code starts only
once it is agreed in conversation.

**Board entry:** [13.17](../ROADMAP.md), lane 3. **A v1 blocker for the `user`
persona.**

**Raised by:** Marlon, 2026-08-31, in the sharpest available form:

> All blind users will use chords to operate, no matter what. If chords aren't
> pressable, we need a driver.

He is right, and the entry exists because the gap had sat unnoticed through four
entries while being described as something it is not.

## 1. The gap, measured

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
manuals:

> a session that only presses commands and reads speech never triggers an
> Accessibility request

It stays **true and checkable**, and it narrows: the grant is requested on the
first **keystroke**, exactly as on the first `typeText`. A session that presses
only reader command names and reads speech still asks for nothing, which is the
property worth having and the one the counting-broker scenario asserts.

**Every one of those eleven statements is rewritten in the PR that adds the
caller** — the obligation spec 0046's amendment 13 already placed on 13.14, now
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

### 2.5 Modifiers are flags on the key event

`event.flags = [.maskCommand]` on both the key-down and the key-up of the main
key. That is what menu shortcuts respond to and what the system's own automation
does.

**Separate modifier key-down/up events were considered and are not in v1.** A few
applications watch for the raw modifier transitions rather than the flags, and if
one turns out to matter it is an amendment with a measurement behind it — not a
guess baked in now. This is written down so the next person knows it was a choice.

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
- **What arrives is still not what was sent.** `AccessibilityTextTyper`'s rule
  holds for this path too — the target application may rewrite, swallow or
  reinterpret. A check that needs to know what arrived asks the application or the
  reader.
- **This does not give VoiceOver's own commands a keystroke route**, and must not
  be used as one. `VO-D` stays refused; the reader's commands go to the reader by
  name, where they cost no grant.

## 7. Open questions for the spec conversation

1. **Should a keystroke `pressGesture` announce itself in the transcript
   differently from a command?** The transcript's vocabulary grows one verb per
   entry that produces the event; `PRESS command+l` and `PRESS mute sound toggle`
   are arguably different acts on different targets.
2. **Does the `gestures` capability still describe both halves?** They now cost
   different permissions, which is the argument 13.8 used to split `typing` from
   `gestures` in the first place. The counter-argument is that an agent chooses a
   gesture id by what it wants to happen, not by which grant it costs — and that
   `getGuidance` is where the difference is explained. **My recommendation is one
   capability**, because splitting would make an agent ask "which kind of gesture
   is this?" before every press.
