# Spec 0052 — the keys a VoiceOver user presses

**Status:** **Agreed and implemented** — board entry 13.25, lane 3. The
measurements in §2 were made first, on the maintainer's machine on 2026-09-02,
and are re-runnable as `scripts/voiceover_vo_modifier.sh` and
`scripts/voiceover_default_bindings.py`; the decisions in §3 were agreed in
conversation on 2026-09-02 and the implementation rides in the PR named below.
Amendments made while coding are marked **Amended** where they apply.
The direction is **Decided** and is not re-opened here: *"an agent has to do what
the user does, and what the user does is pressing keys, like in nvda"* (Marlon,
2026-09-02). What this spec settles is HOW.

**Board entry:** [13.25](../ROADMAP.md), lane 3. Branch
`13.25-a-blind-user-presses-keys`, from `main` at 7b6d02e, with no other PR open
in this lane.

**Found by:** [the field report of 2026-09-02](../docs/feedback/2026-09-02-acter-run.md),
an outside agent driving this bridge against a real product for two days, and the
three rounds of argument recorded in the board entry.

## 1. The gap, exactly

A VoiceOver user reaches the menu bar by pressing **VO-M**. This bridge dispatches
the command name `go to menu bar` through the reader's `commander object`, and
13.7 made that the RECOMMENDED route — it is the first section of
`screenreader://reader-guidance`, and every persona document points at it.

Those are two different paths through the machine:

- a **keystroke** goes out through the window server, past the focused
  application, and reaches VoiceOver's event tap;
- a **command name** is dispatched INSIDE the reader over an AppleEvent and never
  passes the application at all.

**So the recommended route can hide the exact defects this tool exists to find.**
An application that swallows or reinterprets VO-M is invisible to `perform
command`, which reports the command succeeding while a real user is stuck. The
persona contract — *"drive exactly as an ordinary user drives, so that reachable
means the same thing in your report as in theirs"* — is not honoured by a session
reaching the reader through an automation channel no user has.

### 1.1 The reason this took three rounds, recorded because it is the lesson

It was raised twice before it was accepted, and the bridge's answers each time
were that the field report's agent had used the route the guidance recommends
(true), and that the recommendation is earned by the permission lever (also true,
and beside the point). **Neither answers the premise.** The tool's whole claim is
that an agent stands in for a user; a user presses keys.

That is the same shape as spec 0048 §1.1 and spec 0051 §1.1: a true statement
about one channel, generalised into a claim about what the bridge should do, left
standing because every individual sentence in it was correct.

### 1.2 What this entry does NOT explain

The field report's menu-bar near-miss — `go to menu bar` reaching **Finder's**
menu bar — was caused by an unbundled binary that macOS never makes the active
application. `VO-M` would have landed in Finder's menu bar too. That case is about
knowing WHICH application you are in, and belongs to its own entry.

## 2. The measurements

### 2.1 What `vo` is bound to, and where that is written

Re-runnable as the first section of `bash scripts/voiceover_vo_modifier.sh`.

VoiceOver's modifier is **Control-Option**, or **Caps Lock**, or **either** — the
person chooses, in VoiceOver Utility. Apple documents the three choices and not
the preference. The key was therefore extracted from the **dyld shared cache** on
2026-09-02, because the `ScreenReader` framework's binary is not on disk as a
file:

    SCRKeysToUseForVOModifier     SCRVOModifierControlOption
                                  SCRVOModifierCapsLock
                                  SCRVOModifierControlOptionOrCapsLock

**VoiceOver records only DEVIATIONS from its defaults**, so an ABSENT key is the
Control-Option default and a present one is the person's own choice. That is the
same shape `VoiceOverPrefsScriptingSetting` already encodes for
`SCREnableAppleScript`, and it is why "readable and not mentioned" is an answer
rather than a gap. Measured on the maintainer's machine: absent, in both
locations, so VO is Control-Option there.

**Two locations, and Sequoia MOVED the file rather than adding to it** (confirmed
against published reports, 2026-09-02): `~/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/com.apple.VoiceOver4/default.plist`
now, `~/Library/Preferences/com.apple.VoiceOver4/default.plist` before. Both are
read, the group container first, because a machine that was upgraded may still
carry the older one and reading it costs nothing.

### 2.2 The reader acts on a synthesized VO chord

The question that could not be reasoned out, and the reason 0051 §2 exists: does
VoiceOver's event tap see a **synthesized** chord at all? Spec 0048 §2.5 is the
standing warning — there, setting modifier flags looked right, read well in
review, and did not work.

**How the answer is readable.** VoiceOver answers no query about any of its 45
toggles, so the state is read from the preferences it writes, and the two toggles
chosen are the two whose default bindings differ by a single Shift:

| binding | command | preference |
|---|---|---|
| VO-Q | `toggle single-key quick nav on or off` | `SCRCUserDefaultsIndependentSingleLetterQuickNavEnabled` |
| VO-Shift-Q | `toggle arrow-key quick nav on or off` | `SCRCInvertedTCommanderCaptureEnabled` |

Those bindings were read off the machine with §2.4's instrument rather than
recalled. The experiment is **a control, a probe and a control** — the 2026-08-29
rule:

| step | what was sent | single-key Quick Nav |
|---|---|---|
| start | — | `0` |
| **control** | `q` alone, no modifier | `0` — unchanged |
| **probe** | `control+option+q` | `1` — flipped |
| **control** | the same chord again | `0` — back |

**The bare-letter control is what makes this worth anything.** Without it the
probe proves only that pressing `q` does something. With it, the MODIFIER is
demonstrably what the reader acted on, and a synthesized VO chord satisfies it.

### 2.3 And the event has to carry the right CHARACTER — the finding of this entry

**This was not looked for. It was found by the shift half of §2.2 failing**, and
it is a defect in the shipped presser rather than a limit of the new feature.

Posted the way this repository already posts a chord — Shift held as a real
`flagsChanged` transition, `.maskShift` set on the key event — `control+option+shift+q`
toggled **single-key** Quick Nav. It reached **VO-Q**, not VO-Shift-Q. It reported
success.

The cause, isolated by stamping the event's unicode string and re-running:

| the same chord | the event carries | what moved |
|---|---|---|
| `control+option+shift+q` | `q` | single-key Quick Nav — **the wrong binding** |
| `control+option+shift+q` | `Q` | arrow-key Quick Nav — the right one |

A `CGEvent` built from a keycode carries the **unshifted** character whatever
flags are set on it and whatever transitions preceded it. An **application**
matches the keycode and the flags, so this is invisible there — which is why
13.17's `command+l` worked on the first try and nothing has caught it since. **The
READER matches on the character.**

So a shifted keystroke sent to this reader today lands on a different binding and
says it succeeded, which is the worst shape a failure can have and the one this
lane keeps paying for. `scripts/voiceover_chord_press.swift` now stamps the
character the active layout produces on the requested layer, and keeps `--raw` so
the control above stays re-runnable.

### 2.4 The reader's own key bindings are readable from the machine

Re-runnable as `python3 scripts/voiceover_default_bindings.py`. It presses
nothing, changes nothing and needs no grant.

**13.7's "no table of key combinations, and one would be worse than useless"
rested on a binding being unknowable from here. It is not.** macOS ships the
factory bindings beside the command vocabulary, and the two join on the command
identifier:

- `SCRStringsToCommandsMap.scrconfig` — 415 English command names, each mapped to
  an identifier (`go to menu bar` → `SCRWorkspace.menubar`).
- `ScreenReaderConfiguration.archived-scrconfig` — an `NSKeyedArchiver` archive
  whose `SCRCConfigurationKeyboardKeyToCommands` maps 282 key SPECIFICATIONS to
  the identifiers they run.

Joined: **301 name ⇄ keystroke rows, read off this machine on 2026-09-02.**

**Three things the format hides**, each established by joining against bindings
Apple publishes rather than guessed at:

- **`vo` is implicit.** Every entry belongs to the VoiceOver commander, so the
  modifier is held for all of them; `go to menu bar` is stored as the bare
  character `m`.
- **`commanded` is the COMMAND key**, not the commander. `find previous list` is
  stored `commanded` with the character `X`, and Apple documents it as
  VO-Command-Shift-X.
- **Shift is spelled two ways** — in a letter's own CASE (`Q` is Shift-Q), and in
  a `shifted` flag for keys that have no case (the function keys, the arrows).
  That second fact is why §2.3's defect exists at all.

**And some commands have NO key at all**, which is the fact that keeps §3.5 from
being a demotion to nothing. Measured in the same join: `find next button`, `find
next text field`, `toggle web navigation dom or group`, `mute speech toggle` and
`pause or resume speaking` ship unbound. A user reaches those through the rotor or
the Commands menu; a session reaches them by name, and for them the command name is
the only route there is.

**What this is not.** These are the FACTORY bindings on this macOS release. A
person who rebound a command in VoiceOver Utility gets their own, recorded as a
deviation this instrument does not read — which is exactly why the reader's own
command name stays the **diagnosis** when a key does nothing.

## 3. Decisions

### 3.1 `vo` is a modifier in the notation that already exists

    press_gesture { gestures: ["vo+m"] }              # go to the menu bar
    press_gesture { gestures: ["vo+shift+w"] }        # read the whole window
    press_gesture { gestures: ["vo+command+h"] }      # find the next heading
    press_gesture { gestures: ["kb:vo+m"] }           # the same, said explicitly

No new separator, no new command, no new source. `vo+m` contains a `+` and no
space, so `CommandVocabulary` already classifies it as a keystroke; the `kb:`
prefix stays optional exactly as it is for `command+l`, and required only for a
keystroke with no modifiers at all.

**It is the counterpart of lane 1's `nvda`, not a synonym for two keys.** NVDA's
gesture ids carry `NVDA+f7` and NVDA resolves that symbol from its own
configuration (Insert, Extended Insert, Caps Lock). This bridge posts the events
itself, so it must resolve the symbol itself. That makes the contract's two
readers say the same thing in the same shape — a reader-modifier symbol, resolved
by that reader's bridge — and it is why `Keystroke`'s cross-reader rule needs
amending rather than breaking: `vo` and `nvda` are **not physical keys**, so "every
token this file accepts names the same physical key on the other reader" now has
one stated exception with its reason.

### 3.2 It is resolved from the machine, at press time, in the pure entity

`Keystroke.parse` takes the machine's binding as a parameter and expands `vo` into
`control`+`option` **while parsing**. Three consequences, and the second is the
point:

1. The `Keystroke` that reaches `CGKeystrokePresser` contains only pressable
   modifiers. The adapter can never see `vo`, and there is no way to construct a
   half-resolved keystroke that reaches the machine.
2. **The decision is in the domain and the reading is behind a port**, which is
   this repo's own rule rather than a preference: the entity says what `vo` means,
   a port says what the machine is set to, and the adapter that reads a plist
   knows nothing about keystrokes.
3. The binding is read **per call**, not cached for the session — the same rule
   `CurrentKeyboardLayout` follows for the layout, and for the same reason:
   somebody who changes it mid-session gets the right keys on the very next press,
   with no observer to register, forget to remove, or receive on the wrong thread.

### 3.3 Caps Lock alone is a named failure, and so is "cannot tell"

| the machine says | `vo` resolves to |
|---|---|
| nothing recorded | `control+option` — the default |
| `SCRVOModifierControlOption` | `control+option` |
| `SCRVOModifierControlOptionOrCapsLock` | `control+option` — either is accepted, so these keys are correct |
| `SCRVOModifierCapsLock` | **refused by name; nothing is pressed** |
| neither file readable | **refused by name; nothing is pressed** |

On a Caps-Lock machine, `control+option` is **not** the VoiceOver modifier, so
pressing it would be the "wrong keys with total confidence" failure this lane
refuses everywhere else. The refusal names the reader's own command name as the
route that works whatever the modifier is, and says explicitly that
`control+option+…` is not the substitute — because that is exactly what an agent
would try next.

**Whether a synthesized Caps Lock can act as the modifier is NOT measured**, and
this entry does not guess. It is named in §7 as the thing a later entry may
measure; until then a refusal is the honest answer and a wrong press is not.

`unknown` is refused for the reason `ScriptingSetting.unknown` exists: "I could
not look" and "it is at the default" are different facts, and only one of them
justifies pressing keys at somebody's screen reader.

### 3.4 The key event carries the character a real keypress would carry

§2.3, as a rule: **the character the active layout produces for that keycode on
the requested layer is stamped onto the event.** Shift held → the shifted layer's
character.

- **Character keys are stamped, always.** Unshifted it is what the system fills
  anyway, so the rule is one rule rather than a special case for Shift, and it is
  the accurate description of what a keyboard does.
- **Named keys are never stamped.** An arrow or an F-key is layout-independent,
  its character is a private-use code point this repository has no business
  inventing, and the system fills it correctly — measured, since `vo+leftArrow`
  and the arrow-key chords of 13.22 work today.
- **The decision stays above the seam.** `KeyboardLayout` gains the forward
  question — *what does this keycode produce on this layer* — and `EventPoster`
  gains the character to stamp. Neither leaf decides anything, which is the
  layering rule this bridge is built on.

**This fixes a defect that exists today**, independently of `vo`:
`press_gesture ["control+option+shift+q"]` currently reaches VO-Q. So the change
is not scoped to the new modifier and must not be.

### 3.5 The command name is demoted, not removed

**Amended 2026-09-02, and the amendment is sharper than what it replaces.** This
section first said the command name stays available to every stance as a
convenience and a diagnosis aid. Marlon put the question that settles it:

> can a user send commands directly? No? Then so cannot the agent.

He is right, and the exception I was defending does not survive it. **A person
cannot dispatch one of the reader's commands by name** — that channel is
AppleScript, which no user has and which a careful user switches OFF, because it
lets any process on the machine drive their screen reader. What a person does with
an act that has no bound key is open the **Commands menu** (`vo+h` pressed twice,
read out of the factory bindings), type the name and press Enter. That is keys.

So the split is by STANCE rather than by convenience:

- **`user` and `validator` press keys, always**, and reach an unbound command
  through the Commands menu the way a person does. A key that does nothing is a
  FINDING — the application swallowed it, or the person rebound it — and not
  something to resolve by switching to a route no user has.
- **`expert` keeps the dispatch channel**, precisely because it stands in for
  nobody: bypassing the input path is what makes the comparison diagnostic.

The four reasons this section originally gave for keeping the command name in
every stance's hands are answered rather than ignored: acts with no key have the
Commands menu; the ring is something a user lives with; a session that cannot
press cannot drive as a user drives and should say so; and diagnosis is `expert`
work.



It stops being the recommended way to stand in for a user, and becomes what it
is:

- **an automation convenience** — it costs no Accessibility grant, works whatever
  the person has rebound, and is the only route on a machine that will not grant
  one;
- **a diagnosis aid** — a key that does nothing while its command name works is a
  finding about the application under test, and an unknown name fails cleanly with
  `Command does not exist (6)`, which is still the cheapest way to ask this reader
  what it can do.

**The two routes disagreeing IS a finding**, and that sentence is the guidance's
payoff. It is the defect class the field report went looking for and could not
see.

### 3.6 The cost, stated rather than discovered

13.8's lever was the sentence *"a session that presses only the reader's command
names and reads speech is never asked for Accessibility"*. **A faithful
user-persona session presses keys, so it needs the grant, and that sentence stops
describing ordinary driving.** It becomes a statement about **reading-only**
sessions — the `validator` and `expert` stances observing rather than driving, and
any session that only reads speech.

A lever bought by driving the reader in a way no user does is bought with the
fidelity this tool sells. That is the trade, it was made deliberately, and this
spec states it rather than re-opening it. The assertion in the tests stays,
because it is still true of what it now describes; what changes is its name and
the sentence beside it, in `bridges/voiceover/AGENTS.md`, the root `AGENTS.md`
layout entry, and `common.md` — **no copy of the old sentence is left standing
where it is now false.**

### 3.7 `VO-D` stays refused, and the refusal finally names the fix

VoiceOver's own hyphen shorthand remains a named failure, and the message changes
from *"send the command name, or write out `control+option+d`"* to *"write it as
`vo+d`"*.

**Accepting `VO-M` itself was considered and declined.** Apple also writes
`VO-Shift-M`, so accepting the separator means maintaining a second complete
notation for one act — with its own modifier-order rules, its own refusals and its
own tests — for an id shape whose fix is now one token long. A refusal that names
the exact rewrite costs one round trip.

### 3.8 What the record says was pressed

`Gesture.described` reports the **resolved** keys: `vo+m` is recorded and returned
as `kb:control+option+m`.

The alternative — echoing `vo+m` back — was declined because a resolution read off
somebody's machine is exactly the thing a run's record must not hide: two machines
whose `vo` differs would produce identical transcripts. The resolved spelling is
also still replayable, so it loses nothing. And it means **one press tells an agent
what the binding resolved to**, which is this entry's answer to the field report's
seventh ask without touching the wire.

## 4. Class/file layout

The review gate.

| File | Role | Change |
|---|---|---|
| `Domain/Ports/ReaderModifierSetting.swift` | **port — new** | *"what is the VoiceOver modifier bound to on this machine?"* Four answers (`controlOption`, `capsLock`, `either`, `unknown`) as a `ModifierSetting` enum in the port's own file, exactly as `ScriptingSetting` sits with `ReaderScriptingSetting`. Implemented by the adapter below and by `FakeReaderModifierSetting`. Built by `VoiceOverAdapterFactory`; used by the `PressGesture` handler and by nothing else. |
| `Adapters/VoiceOverPrefsModifierSetting.swift` | **adapter — new** | implements that port over the existing `PlistReader` seam. Reads `SCRKeysToUseForVOModifier` from the group container and then the pre-Sequoia location; readable-and-absent is `controlOption`, unreadable is `unknown`, an unrecognised value is `unknown`. Holds no path of its own — see the next row. |
| `Adapters/VoiceOverPreferencesFile.swift` | **supporting construct — new** | the one place that knows where VoiceOver keeps `default.plist`, and the only reason it exists is that a second adapter now needs it. `VoiceOverPrefsScriptingSetting.preferencesPath(home:)` moves here and that class calls it. Pure; no IO. |
| `Domain/Entities/Keystroke.swift` | entity — **amended** | `Modifier` gains nothing: `vo` is a token `parse` RESOLVES, not a case — so a `Keystroke` cannot hold an unresolved symbol and the adapter cannot see one. `parse(_:readerModifier:)` takes the binding; §3.3's two refusals; `reasonNoSuchModifier("nvda")` gains its counterpart sentence; the cross-reader header gains §3.1's stated exception. |
| `Domain/Entities/CommandVocabulary.swift` | entity — **amended** | `classify(_:readerModifier:)` passes the binding through; §3.7's rewritten `VO-D` refusal. The `+`/space/`kb:` rules are untouched. |
| `Domain/Controllers/Commands/PressGesture.swift` | controller — **amended** | reads the binding once per call from the new port and hands it to `classify`. The whole batch is still classified before anything is dispatched, so a refused `vo` presses nothing — which is what makes §3.3 safe. |
| `Domain/Ports/AdapterFactory.swift` | port — **amended** | `AdapterSet` gains the new port. |
| `Adapters/VoiceOverAdapterFactory.swift`, `Adapters/Wiring.swift` | wiring — **amended** | build it once, from the same `PlistReader` and `home` the scripting setting uses. |
| `Adapters/Ports/KeyboardLayout.swift` | adapter seam — **amended** | the forward question: `character(forKeyCode:shifted:)`. Its header states why a seam that answered only the backward one made §2.3's defect unfixable above the line. |
| `Adapters/Ports/EventPoster.swift` | adapter seam — **amended** | `post` takes the characters to stamp (nil for a named key). |
| `Adapters/CurrentKeyboardLayout.swift` | leaf — **amended** | one more `UCKeyTranslate` call. No decisions. |
| `Adapters/CGEventPoster.swift` | leaf — **amended** | `keyboardSetUnicodeString` when characters are given. No decisions. |
| `Adapters/CGKeystrokePresser.swift` | adapter — **amended** | §3.4: resolve the layer (requested Shift, or the character's own layer), ask the layout for the character, hand it to the poster. Named keys pass nil. |
| `Tests/Fakes/ReaderModifierSetting.swift` | fake — new | subclasses the port; answers what a test sets. |
| `Tests/Fakes/KeyboardLayout.swift`, `Tests/Fakes/EventPoster.swift` | fakes — amended | the forward question, and the characters recorded per posted event so a test can assert what was stamped. |
| `Tests/…/KeystrokeTests.swift` | unit — amended | `vo+m` resolves to control+option; `vo` with each of the four settings; Caps Lock and `unknown` refuse by name and produce no keystroke; `vo` alone is "a keystroke with no key"; `l+vo` is still a modifier after a key; `described` reports the resolved spelling. |
| `Tests/…/CommandVocabularyTests.swift` | unit — amended | `vo+m` classifies as a keystroke; `kb:vo+m` too; `VO-D`'s new refusal names `vo+d`; a command name containing "vo" is untouched. |
| `Tests/…/PressGestureTests.swift` | unit — amended | the binding is read from the port; a refused `vo` in position three presses nothing at all; a batch of command names still never touches the broker. |
| `Tests/…/CGKeystrokePresserTests.swift` | unit — amended | a shifted character stamps the shifted character; an unshifted one stamps the plain character; a named key stamps nothing; a character on the layout's shifted layer stamps its shifted character and adds the Shift. |
| `Tests/Integration/SessionRoundTripTests.swift` | integration — amended | `vo+m` off a real wire reaches the key presser as control+option+m and not the AppleScript runner; a Caps-Lock machine refuses over the wire with the command name named. |
| `Entities/Documents/common.md` | document | §5 — the rebuild. |
| `Entities/Documents/user.md`, `validator.md`, `expert.md`, `unknown.md` | documents | §5 — the stance halves. |
| `specs/wire/v1/protocol.md` §5 | contract | one paragraph: a reader's modifier SYMBOL in a gesture id is resolved by its bridge from the machine — `NVDA+f7` there, `vo+m` here — and is never a key the caller spells out. |
| `bridges/voiceover/AGENTS.md` | manual | the gesture section: `vo`, §2.3's character rule, and §3.6's corrected lever sentence. |
| `AGENTS.md` (root) | manual | the layout table's lane-3 entry: 13.25 in one paragraph, and the lever sentence corrected where it is quoted. |
| `ROADMAP.md` | board | 13.25 flipped to Done by this PR, and §7's follow-ups added as entries. |
| `scripts/voiceover_vo_modifier.sh` | instrument — **new, already landed** | §2.1, §2.2 and §2.3, control–probe–control. |
| `scripts/voiceover_default_bindings.py` | instrument — **new, already landed** | §2.4, the join. |
| `scripts/voiceover_chord_press.swift` | instrument — **amended, already landed** | stamps the character; `--raw` keeps §2.3's control re-runnable. |

**No new wire command, no schema change, no drift gate touched.** A gesture id is
opaque to the contract, and `vo` is this reader's vocabulary inside one.

## 5. The guidance, rebuilt

This is the deliverable, not a side effect of §3.

**`common.md`'s spine becomes what a VoiceOver user PRESSES.** Today the document
opens on the two notations and their dispatch channels; it will open on the keys,
with the notation stated once and the channels demoted to where they belong.

- **A table of what a user presses**, from §2.4's join and dated: moving with the
  VO cursor and the arrows, interacting, `vo+m` / `vo+d` / `vo+shift+d`, the item
  chooser, the rotor, the reading commands, web finding with `vo+command+…`, and
  the ordinary Mac chords a user presses in the first minute. Every row states the
  keystroke **and** the command name, because the pairing is what makes §3.5's
  diagnosis usable.
- **Stated as the factory bindings**, with the one honest limit: a person may have
  rebound them, and a key that does nothing where its command name works is either
  a rebinding or a finding — and the way to tell is one extra call.
- **The permission cost, plainly**: keys cost the Accessibility grant, it is asked
  for once per session, and a session that only reads is still never asked.
- **§2.3's rule where an agent will meet it**: a shifted chord reaches the binding
  a person reaches, because the bridge sends the character a keyboard sends. It is
  one sentence, and it exists so that a future reader of a failure knows this was
  measured rather than assumed.

**`user.md`** says the stance presses keys, that this is what an ordinary user
has, and that reaching for a command name to *rescue* a run is the same move as
reaching for a hot spot: allowed to characterise a failure, never to pass one.
The boundary itself does not move — the mouse commands and the hot spots stay
outside it, and VoiceOver cursor navigation stays inside.

**`validator.md`** gains the finding that this entry makes possible: the two
routes disagreeing is a defect in the application under test, and the way to state
it is to name both — what was pressed, what the command name did.

**`expert.md`** keeps the command name as an instrument and gains the same
comparison as a method.

**`unknown.md`** gains one sentence, since it names what a restricted stance may
not do.

## 6. The live checklist this earns

Every item is driven through the real MCP tools against the real reader, except
where it names a script.

1. `bash scripts/voiceover_vo_modifier.sh` passes: the bare letter moves nothing,
   the VO chord moves its setting, it moves back, and the stamped shifted chord
   reaches the *other* setting while `--raw` reaches the wrong one.
2. `press_gesture ["vo+m"]` reaches the menu bar, and the reader says so.
3. The `pressed` entry for it reads `kb:control+option+m` — the resolution is
   visible in the record (§3.8).
4. `press_gesture ["vo+shift+w"]` reads the whole window: a shifted VO chord
   reaches its own binding through the bridge, not only through the instrument.
5. `press_gesture ["vo+command+h"]` moves to the next heading on a page, which is
   the three-modifier case.
6. **The comparison that is the point of the entry**: the same act driven both
   ways on one application — `vo+m` and `go to menu bar` — and the result recorded
   whether they agree or not.
7. A shifted **application** chord (`command+shift+t` in a browser) does what it
   does on a keyboard — the half of §2.3 that has never been measured.
8. `press_gesture ["vo+d", "kb:nosuchkey", "vo+m"]` presses **nothing**: the batch
   is refused before dispatch.
9. After a failed press the keyboard is clean: `CGEventSource.flagsState` is `[]`
   and typing into a scratch document produces exactly what was typed.
10. A session that read speech and pressed only command names raised **no**
    Accessibility dialog — §3.6's lever, in what it now describes.
11. The Caps-Lock refusal, read as prose: temporarily set the modifier to Caps
    Lock in VoiceOver Utility, `press_gesture ["vo+m"]` refuses by name, and the
    setting is put back. *(Marlon's machine; asked for explicitly, not assumed.)*

## 7. Honest limits

- **Caps Lock is refused, not supported.** Whether a synthesized Caps Lock can act
  as the VoiceOver modifier is unmeasured. A later entry may measure it; a wrong
  press must not stand in for the measurement.
- **A rebound machine is not read.** §2.4 reads the FACTORY bindings. The person's
  own deviations are in their preferences and this entry does not decode them, so
  the guidance's table is what an ordinary machine presses and the command name is
  the diagnosis when a key does nothing. Reading the deviations is §8's first
  question.
- **The VO modifier LOCK is invisible.** `toggle the vo modifier lock on or off`
  makes the reader behave as though VO were held; nothing here can read that
  state, so a session driving keys while the lock is on will get different
  results and nothing will say why. The guidance names it; the bridge cannot
  detect it.
- **The character rule was measured on ONE reader binding.** VO-Shift-Q against
  VO-Q is a clean pair; other shifted bindings are inferred from it. Checklist
  item 4 is what turns the inference into evidence for a second case.
- **`fn` is not addressed.** The laptop row (`fn+vo+3` for `vo+f3`) exists in
  §2.4's output and this entry neither uses nor documents it, because whether
  `fn` is needed depends on `com.apple.keyboard.fnState` — the field report's
  seventh ask, and a different entry.

## 8. Open questions

1. **Should the bridge read the person's own rebindings?** The deviations are in
   the same preference file this entry already reads. It would make the guidance
   table true of the machine rather than of the release — lane 1's standard,
   exactly — and it is a decoding job with its own risks. A separate entry.
2. **Is AppleScript control of VoiceOver still a required precondition?**
   Evaluated below, because it stopped being obvious the moment keys worked.
3. **Should lane 1 learn `vo`?** No — `vo` is this reader's symbol as `nvda` is
   that one's. What lane 1 might gain is the same *shape* in its documentation,
   which costs nothing here.

### 8.1 The AppleScript precondition, evaluated

Asked by Marlon on 2026-09-02: *do we still need VoiceOver controlled by
AppleScript as a gate, to begin with?*

**What actually depends on it today**, read off the code rather than recalled:

| what | why it needs the channel |
|---|---|
| every command-name `pressGesture` | it IS the channel |
| `hello`'s rung 5, `captureProof` | it presses `describe item in voiceover cursor` to make the reader speak, and requires the utterance to arrive |
| `ReaderLiveness` | "the reader answers its own name" — the -1728 / -600 distinction |
| `getFocusInfo` without the Accessibility grant | the VoiceOver cursor route |

So it is not a gate the bridge chose: **`captureProof` cannot be climbed without
it**, and `captureProof` is what makes `getSpeech` mean anything (13.20). A
machine with the switch off gets no session at all, silent or live.

**What this entry changes.** `vo+f3` is `describe item in voiceover cursor` as a
KEYSTROKE. So the proof could be made without AppleScript — at the cost of the
Accessibility grant, which 13.20 deliberately never *requests* during a handshake
because a consent dialog would hang it. But it does READ both permissions, so on a
machine where Accessibility is already granted, the keystroke route is available
and asks nobody anything.

**The shape that follows**, and it is the same one `getFocusInfo` already has: a
proof with **two routes, chosen by what the machine already holds** —

1. AppleScript on → the command name, costing nothing;
2. else Accessibility already granted → `vo+f3`;
3. else fail, naming *both* fixes instead of one.

That would turn a hard precondition into a soft one and close the field report's
first and third complaints from a different direction.

**Recommendation: not in this PR.** It is a change to the handshake ladder, with
its own live checklist that needs a machine with the switch OFF — which means
turning the maintainer's off and back on, and getting it wrong leaves him without
a working session. It depends on `vo` existing, which is this PR. So it is
proposed as **board entry 13.26**, first in this lane after 13.25.

**And the bridge cannot turn the switch on itself**, which is worth stating
because it is the obvious escape: the setting is `SCREnableAppleScript` in
VoiceOver's own preferences plus a root-owned marker file, VoiceOver holds its own
copy in memory, and writing that file behind the reader's back is precisely the
manoeuvre that destroyed the maintainer's stored voice settings once already
(spec 0047, finding 17; the field report's §1). `Precondition` exists to say so
with its recovery, and that stays true.
