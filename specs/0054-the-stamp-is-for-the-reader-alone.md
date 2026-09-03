# 0054 — The character stamp is for the reader alone

**Status:** Decided (2026-09-03)
**Board entry:** 13.29 (lane 3)
**Supersedes part of:** [0052](0052-a-blind-user-sends-keys.md) §2.3

## 1. What went wrong

An agent driving this bridge against a real application reported that it could
not send application chords. Everything it tried — `command+k`, `command+/`,
`command+m`, `command+a`, `command+c`, `command+shift+a` — came back as
`pressed` with an empty speech span and changed nothing on the machine. The same
chords sent through System Events, in the same application, in the same field,
seconds apart, worked.

That is the worst failure shape this bridge has: a report of success over an act
that did not happen. It stood for a week, across two merged board entries, in the
one direction the tool exists to exercise — what a person actually presses.

### 1.1 What the repository said instead

The guidance document lists `command+l`, `command+f`, `command+t`, `command+n`,
`command+s`, `command+a`, `command+z` and `command+shift+tab` under *"the chords
an ordinary Mac user presses in the first minute"* and tells the agent to use
them the way a person would. The unit tests asserted the chords went out. 13.25's
live checklist recorded one of them working. Every artifact in the repo agreed
the capability was present, and none of them was a measurement of an unshifted
application chord.

## 2. The cause

13.25 added one line to `CGEventPoster.post(keyCode:flags:characters:keyDown:)`:

```swift
if let characters {
    let units = Array(characters.utf16)
    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
}
```

It was added for a real defect. A `CGEvent` built from a virtual keycode carries
the **unshifted** character whatever flags are set on it, and VoiceOver matches
its bindings on the event's character — so `control+option+shift+q` reached VO-Q
rather than VO-Shift-Q and reported success (0052 §2.3). Stamping the character
the active layout produces for the layer in force fixes that, and it does.

It also takes the chord away from every application.

### 2.1 The measurement

2026-09-03, eight legs against TextEdit. The probe replicates the presser's exact
event sequence — `flagsChanged` in, key down, key up, `flagsChanged` out, keycodes
resolved through `UCKeyTranslate` against the live ABNT2 layout — with the stamp
as the only variable. Control–probe–control throughout: System Events sent the
same chord before and after, and passed both times.

| Chord | Observable | Stamped | Not stamped |
|---|---|---|---|
| `command+a`, `command+c` | clipboard | sentinel unchanged | document text copied |
| `command+shift+c` | TextEdit window count | 1 → 1 | 1 → 2 (Colors panel) |

Both rows were run in both orders. No modifier was left held on any leg.

### 2.2 It is the call, not the character

`command+c` was stamped with `"c"` — byte for byte what the system had already
put on the event — and the chord died exactly as it did with any other value. So
the obvious narrowing ("stamp only when the stamp changes something") is not
available: setting the payload **at all** is what stops it.

The mechanism is inference and is recorded as such: one `CGEvent` carries one
Unicode string, and overriding it collapses the `characters` /
`charactersIgnoringModifiers` pair that AppKit's key-equivalent matching reads.
The correlation is measured; the explanation is not.

### 2.3 A Shift is not an escape either

The second obvious narrowing — stamp only when a Shift is in force, since that is
the layer the event lies about — is killed by the same table. `command+shift+c`
fails stamped exactly as `command+c` does.

That row also settles what happened to 13.25's checklist. It contains exactly one
Command chord, `command+shift+c`, recorded as opening the Colors panel. **It does
not reproduce on the code that shipped**, in either order, and the presser did not
change between that measurement and now (13.26 touched the file only to add a
comment). One measured chord, of the one shape that would have looked like a
control if it had failed, is how this passed review.

## 3. The decision

**A chord aimed at the reader is stamped. Every other chord is left exactly as
the window server built it.**

The bridge already reasons in exactly these two routes, and this is that same
line drawn one layer lower. VoiceOver is the only consumer the stamp serves and
every other consumer it harms, so the stamp follows the reader and nothing else.

### 3.1 What counts as "aimed at the reader"

A keystroke holds the reader's modifier when its modifier set contains **every**
modifier this machine's reader uses for its own commands, read from
`SCRKeysToUseForVOModifier` through the existing `ReaderModifierSetting` port.

- `vo+m` and a literal `control+option+m` are the **same fact** and get the same
  treatment. An agent that spelled the modifier out is not punished for it.
- `control+a` and `option+b` hold *half* of it and are not the reader's.
- On a machine whose `vo` is Caps Lock, or whose preference could not be read,
  **nothing** is the reader's: `control+option` is not the modifier there, so a
  chord holding it is aimed at whatever has focus. This is 13.19's rule — the
  bridge does not guess — applied to a second question.

The residual ambiguity is an application whose own shortcut is
`control+option+X`. It is stamped and may not reach that application. This is
accepted: on a Mac with VoiceOver running, `control+option+X` *is* a reader
command and the reader consumes it first.

### 3.2 File and class layout

No new files, no new ports, no new seams.

| File | Role | Change |
|---|---|---|
| `Sources/VoiceOverBridgeDomain/Entities/Keystroke.swift` | entity | Gains `holdsReaderModifier: Bool`, set by `parse` from the `ModifierSetting` it already receives. Gains `readerModifierKeys(_:)`, the one place the setting maps to modifiers, which `resolveModifier` now also uses so `vo` and this flag cannot drift into two answers. |
| `Sources/VoiceOverBridgeAdapters/CGKeystrokePresser.swift` | adapter | Stamps only when `holdsReaderModifier`. One guard; the stamping logic itself is unchanged. |

`CGEventPoster` does not change: it still stamps what it is handed and decides
nothing, which is the layering rule holding up under a fix. `KeyPresser`'s
signature does not change either — the fact rides on the entity that was already
crossing the port.

### 3.3 Why the entity carries it rather than the adapter asking

The adapter is where every decision on this edge lives, so "let
`CGKeystrokePresser` ask `ReaderModifierSetting`" is the reasonable alternative.
It is rejected for two reasons. The setting is read **once per `pressGesture`**
and handed to `parse` already, so a second reader would be a second read of the
same preference with a window between them in which they can disagree. And the
question — *is this chord the reader's?* — is answerable with no machine access
at all, which makes it a domain fact; putting it in the pure entity is what lets
it be tested without posting an event.

## 4. What this does not decide

**Whether the stamp is needed at all.** Every event in this bridge is built with
`CGEvent(keyboardEventSource: nil, ...)`. A real `CGEventSource` may make the
window server perform the layout translation itself and fill both character
fields correctly — in which case 13.25's defect disappears, and the stamp and
`holdsReaderModifier` both delete. Answering it means driving the reader and
checking that `vo+shift+q` reaches VO-Shift-Q; it is board entry **13.30** and it
is a live measurement, not a code change.

**Removing AppleScript from the gesture path.** Raised by Marlon in the same
conversation. Keystrokes already never touch it — `vo+m` has gone through
`CGKeystrokePresser` since 13.25, and the `vo` modifier is read from a property
list file, not a script. What remains is the **command-name** route, which
dispatches through VoiceOver's `commander object` over an AppleEvent. Replacing
it means resolving each command name to the keystroke this machine has bound to
it, which is board entry **13.27**, and it is a decoding job against an
`NSKeyedArchiver` archive rather than a change to this edge.

## 5. The test that would have caught it

An unshifted application chord, measured by its effect on the application, in the
live checklist. 13.29 adds it, and adds the unit assertion underneath it: an
application chord's events carry no character payload at all — asserting the
**absence of the call**, since 2.2 shows the value is irrelevant.
