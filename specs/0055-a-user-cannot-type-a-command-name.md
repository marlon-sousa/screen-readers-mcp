# 0055 — A user cannot type a command name, so neither may we

**Status:** Draft — awaiting approval in conversation
**Board entry:** 13.31 (lane 3)
**Supersedes in part:** [0052](0052-the-keys-a-voiceover-user-presses.md) §3, [0053](0053-the-bridge-prepares-the-reader.md) §1 and §3.1

## 0. The sentence this entry is built on

Marlon, 2026-09-03, on reading the inventory below:

> *"command name … if a user cannot type a command, why should we have to?"*

No VoiceOver user has the command-name channel. A person cannot dispatch
`go to menu bar` by name; they press VO-M, and for an act with no key they open
the Commands menu, type the name and press Enter. This bridge exists to press what
a user presses. Every remaining use of AppleScript in it is a way of driving the
reader that no human being has, and 13.25 already found what that costs: the
dispatch route reported success on chords a real user was stuck on, hiding the
defect class the tool exists to find.

So the channel goes, entirely. Not demoted again — deleted.

## 1. The second reason, which is not about fidelity

*"Allow VoiceOver to be controlled with AppleScript"* lets **any** process on the
machine drive the screen reader a blind person depends on. Until this entry, a
person who wanted to be tested by this bridge had to leave that door open. That is
a bad thing to ask for at all, and an indefensible thing to ask for in exchange
for a route no user has.

After this entry the bridge never sends an AppleEvent, never reads the switch, and
never mentions it. Somebody who has it off stays that way; somebody who has it on
may turn it off and lose nothing.

## 2. What is being deleted — read off the code on 2026-09-03

Every AppleScript in shipped code goes through one adapter seam,
`Adapters/Ports/AppleScriptRunner.swift`, implemented once by `OSAScriptRunner`
over `SubprocessRunner` (`/usr/bin/osascript`). There is no `NSAppleScript`
anywhere and no second route. Five callers:

| Caller | What it sends | What replaces it |
|---|---|---|
| `VoiceOverGestureSender` | `perform command "<name>"` through the `commander object` | **Nothing — the capability goes.** §3 |
| `ReaderEdgeSetup` rung 5 | `speak the time and date`, to prove capture | `captureProbeKeystroke` (`vo+f7`), already beside it since 13.26 |
| `TCCPermissionBroker` | `tell application "VoiceOver" to return name`, to read the Automation grant | **Nothing — the grant stops mattering.** §4 |
| `VoiceOverFocusInspector` | the VoiceOver cursor, used only when Accessibility is **not** held | **Nothing — that session can no longer exist.** §5 |
| `VoiceOverLiveness` | holds `readerNameScript`; has not used it since 13.26 | already replaced, by the running-application list |

Four of the five delete with no capability loss whatsoever. The rest of this spec
is about the first row and about the cascade the deletions set off.

## 3. What a session loses, and what it does instead

### 3.1 Acts with no factory keystroke

Measured on macOS 15.0, 2026-09-02, and recorded in `common.md`: `find next
button`, `find next text field`, `toggle web navigation dom or group`, `mute
speech toggle` and `pause or resume speaking` ship with no key.

**A user reaches them, so the bridge can.** The Commands menu — `vo+h` pressed
twice, type the name, Enter — is keystrokes plus typed text, and this bridge has
had both since 13.8. It is slower and it is exactly what a person does. The
guidance documents already describe that route in four places; this entry makes it
the only answer instead of the fallback.

**The known limit, stated rather than discovered.** The dispatch names were
English and machine-independent; the Commands menu is rendered in the machine's
own language. On the maintainer's Portuguese machine the reader answers `área de
rolagem` where the tree answers `AXTextArea` (measured 2026-08-30, spec 0046), so
typing an English name into that menu may match nothing. This is not a fidelity
break — a Portuguese user types the Portuguese name, and a session standing in for
one should too — it is a **lookup this bridge does not have**. It belongs to
**13.27**, which is already a decoding job against `SCRStringsToCommandsMap`, and
this spec does not attempt it. Until it lands, the honest statement in the
guidance is: *the Commands-menu route is verified on an English-locale machine,
and on another locale you may need the reader's own name for the act.*

### 3.2 The diagnosis aid

"The key did nothing but the name worked" currently separates a rebinding from an
application swallowing the keystroke. It goes, and `PressGestureHandler.explain`
collapses from three conditions to two: the reader is gone, or the keystroke did
not land.

This is a real loss and it is the right trade. The signal is one no user has
either, it costs every user leaving the door of §1 open, and 13.25's finding was
that this same channel *hid* a defect class rather than exposing one. 13.27 —
reading the machine's real bindings — answers the rebinding half properly, from
the person's own preferences, with no channel at all.

### 3.3 The zero-permission route

A machine that will not grant Accessibility currently still gets a session,
driving entirely by name. After this entry it gets none: rung 1 requires
Accessibility and a pressable `vo`, and says so.

That is the point rather than a casualty. A session that can only drive the reader
in a way no user does is a session selling fidelity it does not have.

### 3.4 If an expert genuinely needs AppleScript

It asks the human to switch it on and runs `osascript` itself. An agent driving
this bridge has a shell; the bridge does not have to be the conduit, and the
capability does not have to be shipped to every session to be available to the one
that can justify it. **This is Marlon's own resolution of the question**, recorded
because it is what makes the deletion total rather than a carve-out — an earlier
turn of the same conversation proposed keeping the channel for the `expert` stance,
and it was declined for this: a persona is self-declared, so it gates nothing, and
a capability nobody can be refused is a capability everybody has.

## 4. The cascade

Deleting the command-name route makes several things unreachable. Each is deleted,
not left as dead code.

**The Automation permission.** `Permission.automationVoiceOver` had exactly one
consumer, rung 1, and the only reason to read it was the channel. It goes, and
`Permission` is left with `accessibility` alone. A one-case enum is kept as an
enum deliberately: `PermissionBroker.request` still exists for the Accessibility
grant that `typeText` and a keystroke `pressGesture` pay, and the vocabulary is
the place a second permission would arrive.

**The AppleScript switch.** `ReaderScriptingSetting` (port),
`VoiceOverPrefsScriptingSetting` (adapter) and `Precondition` (entity, whose only
case is `readerScripting`) all delete. A bridge that never uses the channel has no
business reading whether it is on.

*The cost, named:* the control dialog (13.14) planned a preconditions row for it,
and there is now no precondition to show. That is a smaller dialog, not a missing
feature — the row existed because the bridge could not work without the switch,
and it can.

**`Gesture` stops being a choice.** `CommandVocabulary.classify` returns a
`Keystroke` or refuses. The `Gesture` enum, its `.readerCommand` case and
`isKeystroke` all delete; `PressGestureHandler` loses its route branch and the
`GestureSender` port and `GestureError` go with it. `kb:` survives untouched — it
is how a lone letter is a key (13.19) and has nothing to do with this.

**A refused id must teach.** An id containing a space is no longer a command name;
it is a mistake, and the refusal names the Commands-menu route rather than saying
"unknown gesture". This is the one place the deleted capability must stay visible,
because an agent carrying stale guidance will send one.

**`VoiceOverFocusInspector` loses its cursor route.** With Accessibility mandatory
for any session, the branch is unreachable. The `AccessibilityTrust` seam is
**kept**: a grant revoked mid-session must produce a failure naming the grant, not
a silent empty answer. So the read stays, the second route does not.

**`ProcessRunner` / `SubprocessRunner` stay.** `VoiceOverLiveness.activate` and
`VoiceOverRestart` run `open` and `killall` through them, and neither is
AppleScript.

## 5. Rung 1 after this entry

One route, stated once:

> Accessibility is granted **and** `vo` resolves to something this bridge can
> synthesize (Control-Option, or Control-Option-or-Caps-Lock).

The refusal names one fix instead of two: the Accessibility grant, and the
VoiceOver modifier under VoiceOver Utility → Commands. The machine that still gets
no session is the one whose `vo` is Caps Lock alone, which is **13.28** and
unchanged by this entry.

## 6. The file layout

### Deleted

| File | Role |
|---|---|
| `Sources/VoiceOverBridgeAdapters/Ports/AppleScriptRunner.swift` | adapter seam + `AppleScriptError` |
| `Sources/VoiceOverBridgeAdapters/OSAScriptRunner.swift` | adapter — the `osascript` edge |
| `Sources/VoiceOverBridgeAdapters/VoiceOverGestureSender.swift` | adapter — `perform command` |
| `Sources/VoiceOverBridgeDomain/Ports/GestureSender.swift` | port + `GestureError` |
| `Sources/VoiceOverBridgeDomain/Ports/ReaderScriptingSetting.swift` | port + `ScriptingSetting` |
| `Sources/VoiceOverBridgeAdapters/VoiceOverPrefsScriptingSetting.swift` | adapter — reads `SCREnableAppleScript` |
| `Sources/VoiceOverBridgeDomain/Entities/Precondition.swift` | entity — its only case was the switch |
| `Tests/Fakes/AppleScriptRunner.swift`, `Tests/Fakes/GestureSender.swift`, `Tests/Fakes/ReaderScriptingSetting.swift` | port doubles |
| `Tests/VoiceOverBridgeAdaptersTests/OSAScriptRunnerTests.swift`, `VoiceOverGestureSenderTests.swift`, `VoiceOverPrefsScriptingSettingTests.swift` | their unit tests |
| `Tests/VoiceOverBridgeDomainTests/…/PreconditionTests.swift` | if present; confirmed at implementation |

### Amended

| File | Change |
|---|---|
| `Sources/VoiceOverBridgeDomain/Controllers/ReaderEdgeSetup.swift` | rung 1 asks one question (§5); `Routes` collapses to `modifier` plus a boolean, or deletes; `captureProbeCommand` deletes and rung 5 always presses `captureProbeKeystroke` |
| `Sources/VoiceOverBridgeDomain/Controllers/Commands/PressGesture.swift` | one route; `explain` collapses to two conditions; the space-containing id gets the teaching refusal (§4) |
| `Sources/VoiceOverBridgeDomain/Entities/CommandVocabulary.swift` | `classify` returns a `Keystroke`; `Gesture` and `isKeystroke` delete |
| `Sources/VoiceOverBridgeDomain/Ports/PermissionBroker.swift` | `Permission` loses `automationVoiceOver` |
| `Sources/VoiceOverBridgeAdapters/TCCPermissionBroker.swift` | loses the `scripts` dependency and the automation branch; stays the `AccessibilityTrust` implementation |
| `Sources/VoiceOverBridgeAdapters/VoiceOverLiveness.swift` | `readerNameScript` deletes |
| `Sources/VoiceOverBridgeAdapters/VoiceOverFocusInspector.swift` | tree route only; `AccessibilityTrust` kept for a named failure |
| `Sources/VoiceOverBridgeDomain/Ports/AdapterFactory.swift`, `Sources/VoiceOverBridgeAdapters/VoiceOverAdapterFactory.swift`, `Wiring.swift` | drop `gestures`, `readerScripting`, `appleScriptRunner` |
| `Sources/VoiceOverBridgeAdapters/VoiceOverPreferencesFile.swift` | now serves one derivation (the modifier), not two |
| `Entities/Documents/common.md`, `user.md`, `expert.md`, `validator.md` | the dispatch channel goes; the Commands-menu route becomes the answer; §3.1's locale limit is stated |
| `CONTRIBUTING.md` | §3 deletes; the permissions paragraph names Accessibility only |
| `AGENTS.md`, `ROADMAP.md` | the lane-3 narrative, and 13.31 flipped to Done |
| `Tests/Integration/SessionRoundTripTests.swift` and the affected unit tests | a command name off the wire is now a refusal |

### Added

Nothing. This entry adds no file, which is most of the argument for it.

## 7. What this does not decide

- **13.27**, the machine's real bindings, and with it the localized command names
  §3.1 needs. Unchanged in scope and now more valuable.
- **13.28**, the Caps-Lock machine. Unchanged: it was never the AppleScript route
  that saved it, since that route is what this entry deletes.
- **13.30**, whether the character stamp is needed at all. Untouched.
- **Whether `announce` should mention the Commands menu.** No.

## 8. Live checklist

Run on a machine with *"Allow VoiceOver to be controlled with AppleScript"*
**OFF**, which is now the only state this bridge is written for.

1. `connect_reader` in `silent` mode establishes a session; the transcript shows
   rung 5 pressed `vo+f7` and an utterance arrived.
2. `connect_reader` in `live` mode does the same.
3. `press_gesture` with `vo+m` reaches the menu bar; `get_speech` shows it.
4. `press_gesture` with `go to menu bar` is **refused**, and the refusal names the
   Commands-menu route.
5. An act with no factory key — `mute speech toggle` — is reached the user's way:
   `vo+h`, `vo+h`, `type_text`, `kb:enter`. Record what the menu accepted, which is
   §3.1's open locale question answered for this machine.
6. With Accessibility **revoked**, `connect_reader` is refused by rung 1 naming the
   grant and the modifier, and nothing else.
7. `get_focus_info` answers from the tree, and `poe live` is green.
