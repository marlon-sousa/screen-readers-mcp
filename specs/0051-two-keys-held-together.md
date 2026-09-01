# Spec 0051 — two keys held together

**Status:** **Proposed** — board entry 13.22, lane 3. The measurement in §2 is
done and re-runnable; the decisions in §3 are **not yet agreed** and no
implementation exists. Per the workflow, code starts after this is approved in
conversation.

**Board entry:** [13.22](../ROADMAP.md), lane 3. Stacked on
[PR #95](https://github.com/marlon-sousa/screen-readers-mcp/pull/95) (13.20 and
13.21) and to be opened once that merges — at most one open PR per lane.

**Found by:** an agent driving this bridge, relayed by Marlon on 2026-09-01:

> the other agent complained it could not activate quick nav because the command
> would be left and right arrows pressed together, and it can't press keys
> together. This needs to be generalized, if possible. On mac this is common.

## 1. The gap, exactly

`Keystroke.parse` requires every token before the last to be a **modifier**:

```swift
for token in tokens.dropLast() {
    guard let modifier = Modifier(token: token) else {
        throw KeystrokeMalformed(id: id, reason: reasonNoSuchModifier(token))
    }
    modifiers.insert(modifier)
}
```

So `kb:leftArrow+rightArrow` fails with *"'leftarrow' is not a modifier this
bridge knows"* — which is true, unhelpful, and points at the wrong thing. A
keystroke on this bridge is *modifiers plus exactly one key*, and there is no way
to say **two ordinary keys held at the same time**.

That shape is not exotic on macOS. Arrow-key Quick Nav — Left and Right together
— is the one an agent meets first, and it is how an ordinary VoiceOver user turns
on the navigation mode they then use all day.

### 1.1 The reported blocker was not one, and that half is already fixed

Measured out of `SCRStringsToCommandsMap.scrconfig` on macOS 15.0, all three
Quick Nav toggles exist as **command names**:

- `toggle single-key quick nav on or off`
- `toggle arrow-key quick nav on or off`
- `toggle arrow-key and single-key quick nav on or off`

and this bridge's own guidance document already named them in two places. The
agent had a working route that costs no Accessibility grant and announces which
way the toggle went — the chord does neither. It reached for the chord from
general Mac knowledge instead.

**That is the third time this lane has paid for the same shape**: spec 0048 §1.1
(a true claim about one channel generalised into a false one about the bridge)
and spec 0049 §1.1 (a capability reachable through the wrong tool). So the
documents were fixed first, in PR #95, before any of this: `common.md` now says
to use the command name *rather than the chord you may know from Apple's
documentation*, and *"What this reader does not offer"* names the limit in
general — with an instruction to **report** any such act that has no command
name, rather than working around it with `type_text`, which sends characters and
not keys.

**This entry is therefore not urgent, and it is still worth doing.** The notation
gap is real, the failure message is misleading, and "press what a person presses"
is the whole premise of the `user` persona. What it must not do is displace the
command name as the recommended route (§3.5).

## 2. The measurement

Re-runnable as `bash scripts/voiceover_two_key_chord.sh`. Run 2026-09-01, macOS
15.0, on the maintainer's machine.

**The question that could not be reasoned out:** does VoiceOver's chord detection
accept *synthesized* simultaneity at all? [Spec 0048](0048-pressing-a-chord.md)
§2.5 is the reason for asking rather than assuming — there, setting modifier
flags looked right, read well in review, and did not work; the events had to be
real transitions. And the 2026-08-30 finding that the reader's own modifier
*commands* do not compose is a standing warning that this reader's input handling
has surprises.

**How the answer is readable.** VoiceOver answers no query about any of its 45
toggles, so the state is read from the preference it writes:

    SCRCInvertedTCommanderCaptureEnabled   (arrow-key Quick Nav, 0 or 1)

in `~/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences/com.apple.VoiceOver4/default.plist`.
**That key was found rather than recalled**, by the state-comparison technique in
[`docs/how-we-found-the-voice-store.md`](../docs/how-we-found-the-voice-store.md):
snapshot the plist, toggle arrow-key Quick Nav through the reader's own command
name, snapshot again, read the diff. Nothing in this repo had named it before.

**The experiment is a control, a probe and a control** — the 2026-08-29 rule about
probes:

| step | what was sent | the flag |
|---|---|---|
| start | — | `0` |
| **control** | Left, then Right, each down **and up** | `0` — unchanged |
| **probe** | both down in order, both up in reverse | `1` — flipped |
| **control** | the same chord again | `0` — back |

**The sequential control is what makes this worth anything.** Without it the probe
proves only that two arrow presses do *something*, which is the weaker claim that
would have let a wrong design through. With it, the reader is demonstrably
detecting **simultaneity**, and a synthesized chord satisfies it.

**Also measured: no delay is needed.** Posting the four events back to back
toggles it exactly as a 15 ms spacing does. So the presser needs no timing
machinery, which is one fewer thing to get wrong on a machine under load.

### 2.1 The chord is NOT a clean toggle of one setting, and that cost a correction

The first version of the instrument watched the arrow-key flag alone, on the
reasonable assumption that Left+Right toggles one boolean. It does not. Measured
2026-09-01, starting from `arrow=0 single=1`:

| step | arrow-key | single-key |
|---|---|---|
| start | `0` | `1` |
| chord | `1` | `1` |
| chord again | `0` | **`0`** |

So the chord took **single-key Quick Nav down with it**, and a probe watching one
flag reported "restored" while it had quietly turned off a setting the maintainer
uses every day. It was caught by reading both keys afterwards, and put back
through the reader's own `toggle single-key quick nav on or off`.

**Three things follow, and they are the useful part of this entry.**

- **The instrument now snapshots and restores BOTH**, and restores through the
  **command names** rather than by pressing the chord again — each command moves
  exactly one setting, and restoring with the very thing under test is what left
  the setting off the first time. That is the 2026-08-29 rule doing its work: a
  probe must assert the hazard is gone, and it can only assert about what it looks
  at.
- **It sharpens §3.5 rather than weakening it.** The command names are not merely
  cheaper than the chord, they are *more precise*: each moves one setting and says
  which way it went. The chord moves two and says nothing. An agent that reaches
  for the chord to turn arrow-key Quick Nav on may silently change how letter keys
  behave as well.
- **It is a fact about the READER, not about this bridge**, so a person pressing
  those two keys gets the same compound effect. Nothing here should try to
  "correct" it — the bridge presses what a person presses.

## 3. Decisions (proposed)

### 3.1 The notation is `+`, and there is no new separator

    press_gesture { gestures: ["kb:leftArrow+rightArrow"] }

`+` already means "these together" for modifiers; extending it to ordinary keys
is the same idea, not a second one. A separate separator would make an agent
learn two ways to say "at the same time" and would make `command+leftArrow+rightArrow`
unspellable in either.

**It is probably cross-reader, and that is read rather than assumed.** NVDA's
`KeyboardInputGesture.fromName` splits on `+`, takes everything before the last
token as held keys, and `_generalizeModifiers` only rewrites left/right variants
of real modifiers — it does **not** filter non-modifiers out, and `send()`
presses the held keys down before the main key
(`../nvda/source/keyboardHandler.py` at `release-2026.1`, read 2026-09-01). So
`kb:leftArrow+rightArrow` is at least *parseable and sendable* there. **Not tested
on a live NVDA**, and this entry does not claim it works — see §6.

### 3.2 The parse rule: modifiers first, then one or more keys

`Keystroke` becomes *zero or more modifiers, then one or more keys*:

1. Leading tokens that are modifiers are modifiers, as today.
2. **The first token that is not a modifier begins the key list**; every token
   from there on must be a key.
3. A modifier appearing **after** a key is the existing named failure, unchanged:
   `l+command` still fails rather than being quietly reordered. Lane 1's
   `press_order` modifier hoisting exists to undo NVDA's own alphabetical
   normalizer; there is no such normalizer here and there must not be one.

`described` writes modifiers in the enumeration's order, then the keys **in the
order given** — because the order is what "down in order, up in reverse" means,
and a transcript line has to be replayable.

### 3.3 The press: all down in order, all up in reverse, and the release is a `defer`

`CGKeystrokePresser` already holds modifiers as real transitions and releases
them in a `defer` so a failed press cannot leave Command down (spec 0048 §2.5,
reversed with a measurement after it left the maintainer's Command key held).
**That rule generalises and is the sharpest thing in this entry:** the keys are
released in a `defer` too, in reverse, so a post that fails partway cannot leave
an arrow key held down. A stuck ordinary key is quieter than a stuck modifier and
just as bad — every subsequent keystroke repeats it.

No delay between events (§2).

### 3.4 The grant is unchanged, and so is the lever

A multi-key chord is a `CGEvent`, so it costs Accessibility exactly as a
single-key one does, through the same `AccessibilityGrant` call in
`PressGestureHandler`. **`PermissionBroker.request` still has two callers**, so

> a session that presses only the reader's COMMAND NAMES and reads speech never
> triggers an Accessibility request

is unchanged, word for word, for the third entry running. No sweep.

### 3.5 The command name stays the recommended route, and the guidance says so

`toggle arrow-key quick nav on or off` costs nothing, announces its result, and
works on a machine that has never granted Accessibility; the chord costs a
consent dialog and tells you nothing. This entry adds an expression, not a
recommendation — the paragraph shipped in PR #95 stands, and gains one sentence
saying the chord is now *expressible* and still not the way to do it.

### 3.6 No cap on how many keys — considered and declined

An arbitrary limit of two would be a number nobody could defend, and the code is
identical for three. What bounds it in practice is that every token must be a
named key this bridge knows.

## 4. Class/file layout

The review gate. **No new files and no new ports** — which is the shape a
notation entry should have.

| File | Role | Change |
|---|---|---|
| `Entities/Keystroke.swift` | entity — **amended** | `key: Key` becomes `keys: [Key]` (one or more). §3.2's parse rule; §3.3's ordering in `described`. The "modifier after a key" failure keeps its wording. |
| `Entities/CommandVocabulary.swift` | entity — **unchanged** | the `+`/space/`kb:` rules already classify `kb:leftArrow+rightArrow` as a keystroke. Recorded because "no change" is the reviewable claim. |
| `Ports/KeyPresser.swift` | port — **amended** | the DTO carries the key list; the port's shape is otherwise untouched. |
| `Controllers/Commands/PressGesture.swift` | controller — **unchanged** | it routes on the classification and asks for the grant when any gesture `isKeystroke`. Both already right. |
| `CGKeystrokePresser.swift` | adapter — **amended** | every key down in order, then a `defer` releasing in reverse; the modifier transitions around it are untouched. |
| `Tests/.../KeystrokeTests.swift` | unit — amended | a two-key keystroke parses and round-trips through `described`; order is preserved; `l+command` still fails; a modifier after a key fails by name |
| `Tests/.../CGKeystrokePresserTests.swift` | unit — amended | the event order is down-down-up-up **reversed**; a post that fails partway still releases every key it pressed |
| `Tests/Integration/SessionRoundTripTests.swift` | integration — amended | `kb:leftArrow+rightArrow` off a real wire reaches the key presser as two keycodes and not the AppleScript runner; the counting-broker scenario keeps its claim |
| `Entities/Documents/common.md` | document | one sentence: the chord is expressible now, and the command name is still the route |
| `scripts/voiceover_two_key_chord.sh`, `voiceover_chord_press.swift` | instrument | **already landed with this spec** — the measurement of §2 |

## 5. The live checklist this earns

1. `bash scripts/voiceover_two_key_chord.sh` passes: control, probe, control,
   and arrow-key Quick Nav ends where it started.
2. `press_gesture ["kb:leftArrow+rightArrow"]` toggles arrow-key Quick Nav, and
   the reader says so.
3. Pressed a second time it toggles back — the same causation check, through the
   bridge rather than the probe.
4. `press_gesture ["kb:leftArrow", "kb:rightArrow"]` as a **batch** does not
   toggle it, which is the contract's own distinction between two gestures and
   one chord.
5. After a failed chord (an unknown key name in the list), the keyboard is clean:
   `CGEventSource.flagsState` is `[]` and typing into a scratch document produces
   exactly what was typed.
6. A session that pressed only command names still raised **no** Accessibility
   dialog.

## 6. Honest limits

- **Cross-reader is unverified.** §3.1's reading of NVDA's source says the
  notation is parseable and sendable there; nobody has pressed it on a live NVDA.
  A cross-reader script that relies on it is relying on a code reading.
- **The reader may still ignore it.** What was measured is one chord —
  Left+Right — against one detector. Another VoiceOver chord could be detected
  some other way, and "this bridge can express it" is not "the reader will act on
  it". §5 item 2 is what turns the expression into evidence.
- **What the chord actually does is compound** (§2.1), and this entry does not
  model it. `pressGesture` reports what it PRESSED and never what the reader did
  with it — which is the contract's own rule (protocol.md §7.3) and is right here:
  an agent that wants to know where Quick Nav ended up reads the speech, or uses
  the command names, which move one setting each.
- **`SCRCInvertedTCommanderCaptureEnabled` is not a public API.** It is the key
  the reader happens to write, found by state comparison; it is used by the
  *instrument* and by nothing that ships. No adapter reads it, and this entry
  does not propose one — VoiceOver's toggles remain unqueryable, which is why
  this reader announces no `state` capability.
- **It does not make the platform's chords discoverable.** An agent still has to
  be told which acts are chords. That is the guidance document's job, and the
  sentence added in PR #95 telling an agent to *report* an act with no command
  name is the mechanism for finding the rest.

## 7. Open questions

1. **Should lane 1 accept the same notation?** NVDA's source suggests it already
   would. Nothing here needs it, and changing NVDA's documented gesture form is a
   lane-1 entry with its own live checklist.
2. **Are there other macOS chords that matter, and do they have command names?**
   Quick Nav is the one that surfaced. The right way to find out is the
   instruction now in the guidance — an agent that meets one reports it — rather
   than a table in this repo that goes stale every release.
