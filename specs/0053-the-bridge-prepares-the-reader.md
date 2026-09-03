# Spec 0053 — the bridge prepares the reader, and puts it back

**Status:** **Decided** — agreed in conversation with Marlon on 2026-09-02; board
entry 13.26, lane 3. Rides on the same branch and
PR as [spec 0052](0052-the-keys-a-voiceover-user-presses.md) (13.25), which is
what makes it possible: keys are now a route to this reader, so the AppleScript
channel stops being the only one.

**Board entry:** [13.26](../ROADMAP.md), lane 3.

**Asked for by Marlon, 2026-09-02.** It began as one question about the
AppleScript switch and became the frame for the whole handshake:

> if we don't need apple script control for the operation, and we shouldn't need,
> letting it on is an ask for doing "wrong stuff". a normal user doesn't need it,
> so either I have a solid reason to let it on or it will be disabled.

> so the bridge has to "prepare voiceover". This makes sure voice is the way it
> should, vo keys are the way they should, and vo is started.

> And restore should kind of do the same in reverse.

**The requirement, in one sentence:** a blind person must be able to leave "Allow
VoiceOver to be controlled with AppleScript" **off** — because that switch lets
any process on the machine drive the screen reader they depend on — and this
bridge must still establish a session, drive the reader, and prove it can hear it.

## 1. What the AppleScript channel is actually used for

Read off the code on 2026-09-02 rather than recalled. Five callers, and only the
first genuinely needs the switch:

| User | What it asks | Needs the SWITCH |
|---|---|---|
| `VoiceOverGestureSender` | `perform command "<name>"` through the `commander object` | **Yes — it IS the channel** |
| `ReaderEdgeSetup` rung 5 | makes the reader speak, to prove capture | Only through the row above |
| `VoiceOverLiveness` | `tell application "VoiceOver" to return name` | **No** — measured, §2.1 |
| `VoiceOverFocusInspector` | the VoiceOver cursor, used only when Accessibility is NOT held | No, when Accessibility is held: it reads the accessibility tree |
| `TCCPermissionBroker` | sends the liveness script to read the Automation grant | Only because events are sent at all |

And rung 1 demanded **every** `Permission` case, so a machine that had never
granted Automation got no session at all, whatever it intended to do.

## 2. The measurements

All on the maintainer's machine, macOS 15.0, 2026-09-02, with him at the keyboard
and listening where a machine could not observe.

### 2.1 With the switch off: what dies, and what does not

Re-runnable as `bash scripts/voiceover_without_applescript.sh`.

| Question | Answer |
|---|---|
| Where is the switch recorded? | `SCREnableAppleScript` → `0`, **and** the root-owned marker `/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled` is **absent**. VoiceOver Utility clears both. |
| Does the shipped `VoiceOverPrefsScriptingSetting` read that right? | **Yes** — `disabled`. The "either location saying yes is a yes" rule does not go stale, which was a real worry and is now closed. |
| `tell application "VoiceOver" to return name`? | **Still answers**, exit 0. The switch gates the **scripting object model**, not all AppleEvents — so `TCCPermissionBroker` can still read the Automation grant the way it does. |
| `perform command`? | Fails. **The number is NOT distinctive — see below.** |

**CORRECTED ON 2026-09-02 BY THE LIVE RUN, and the correction is the point of the
row.** This section first recorded `-10000` and concluded *"the three states are
distinguishable"*. Re-measured through the shipped call shapes, on the switched-off
machine, with `SCREnableAppleScript => 0` and the marker absent:

| What was asked | Answer with the switch OFF |
|---|---|
| `tell application "VoiceOver" to return name` | `VoiceOver` — **answers** |
| `… to return version` | `10` — **answers** |
| `… to return commander` | **-1728**, *"can't get commander"* |
| `… to tell commander to perform command "go to menu bar"` | **-1708**, *"doesn't understand the message"* |
| `… to perform command "go to menu bar"` | **-1708**, the same |

So the switch does not fail the *event*: it removes the **scripting object
model**, and what is left answers the application's own properties. The numbers
that come back are **exactly** `-1728` and `-1708` — the pair this lane's guidance
attributes to *"VoiceOver's scripting object model dead while VoiceOver itself is
alive"*, whose stated recovery is a reader restart.

**Two consequences, and the second is a shipped defect.**

1. A switched-off machine and a wedged reader **cannot be told apart by error
   number**. The only signal that separates them is the preference itself, which
   this bridge already reads (`VoiceOverPrefsScriptingSetting`, `disabled`).
2. **The shipped failure message is therefore wrong on exactly the machine this
   entry exists to support.** Measured live: `press_gesture ["go to menu bar"]`
   answered `scriptingChannelDead: VoiceOver answers its own name but not its own
   state. Recovery: restart the reader …`. Every clause of that is true and the
   recovery is useless — no restart brings back a switch the person deliberately
   turned off. 13.26 must consult the setting **before** classifying, and say
   "the person has switched this off, press the key instead".

### 2.2 The reader can be driven, and proved, by keys alone

- A synthesized VO chord reaches the reader and makes it speak: from a
  `describe window` baseline, `control+option+f7` produced a battery status
  (§2.4 explains why the battery and not the time).
- The probe command **`speak the time and date`** moves nothing, always speaks,
  and exists on both routes — chosen by Marlon over `go to dock`, which is equally
  reliable and **moves the VoiceOver cursor**: a connect that quietly walked
  somebody's cursor to the dock would be a small invisible edit to where they were
  standing, every time.
- Its key is `vo+f7`, read out of the reader's factory bindings, and function keys
  are **not** eaten by the system shortcut layer.

### 2.3 A synthesized Caps Lock is invisible to the reader

Measured with Marlon listening, on a machine he had set to Caps Lock:

- `control+option+q` moved nothing — **confirming** that on a caps-bound machine
  those two keys are not the modifier, which is the premise of spec 0052 §3.3's
  refusal.
- Caps Lock sent four ways — as a `flagsChanged` transition, as a bare
  `.maskAlphaShift` on the key event, as an ordinary held key, and held for 300 ms
  — produced **no reader command at all**, and the letter landed in the text
  editor that had focus.

**And the platform explains it**: `CGEventFlags.maskAlphaShift` *reports* that
Caps Lock is down; posting it does not make the system believe it, because Caps
Lock is a system-level toggle. The only route to it is HID-level remapping
(`hidutil`, IOKit seizing the device) — a driver-class intervention on somebody's
keyboard, which this bridge will not do.

### 2.4 The multi-press ring, which is documentation rather than code

`vo+f7` is three commands — time and date, battery, wifi — and the reader picks
between them by press count. Measured: four presses two seconds apart cycled
wifi → time → battery → wifi; **a different key reset it and ten seconds of
waiting did not**. Apple documents the form as "press twice", which reads as
"twice in quick succession", and that is not what the machine does.

**The consequence for this spec is a rule about the probe**: rung 5 must never
assert *which* answer came back. Any utterance is the proof; a rung expecting a
time would fail on a healthy machine whenever the ring stood elsewhere.

### 2.5 The modifier can be replaced — but the reader reads it only at STARTUP

**READ §3.3 BEFORE ACTING ON ANY OF THIS.** Everything below is accurate and it is
not the whole story: the live run found that VoiceOver ALSO puts a modal question
on screen when that key changes under a running reader, which is what took the
whole replacement design out of this entry. "The reader reads it only at startup"
was true and was read as "the running reader ignores a write". It does not.

The measurement that decided §3.3, and it went both ways:

| step | result |
|---|---|
| write `SCRVOModifierControlOption`, no restart, press `control+option+q` | **nothing** |
| same file, press `control+option+d` with Marlon listening | **nothing** |
| restart the reader, press `control+option+d` | **"we are in dock"** |
| write `SCRVOModifierCapsLock` back, restart | his own Caps Lock modifier is in force again |

And the write itself was clean: **120 keys before, 120 after, one line different**
— pitch, rate, voice, Quick Nav and the rest untouched.

## 3. Decisions

### 3.1 The handshake PREPARES the reader, and that is the frame

Rungs stop being a ladder of *checks that may fail* and become a sequence of
*things made true*, in this order:

1. **the reader is running** — start it if it is not;
2. **the capture voice is registered and published**;
3. **the reader speaks with the capture voice**;
4. **capture is proved** — make the reader speak and require the utterance to
   arrive.

Teardown reverses **the session state and only that**: the voice. The
registration is machine state and stays, which is 13.20's rule unchanged.

**Step 4 was removed by the live run** — see §3.3. It read "the VoiceOver modifier
is one this bridge can press", and it is not a rung any more.

**One ordering argument survives it, and is kept because the next attempt will
meet it.** Anything that restarts the reader at teardown must run **after** the
voice has been put back, because a restart re-reads the voice selection: restart
first and the reader comes up unable to publish the capture voice, falls back to
the system default **and persists the fallback**, which is 13.23's hazard reached
by the cleanup itself.

### 3.2 The handshake MAY restart the reader — reversing 13.20

**This overturns a rule marked Decided**, in these words: *"no handshake in this
bridge may decide on a restart — it takes the reader away from somebody who is
using it."* Marlon reversed it on 2026-09-02: *"restarting vo is not a problem for
capturing as a bridge handshake, if needed."*

The bounds, which are the point of writing it down:

- **Only for a named reason** — a capture voice that is registered but not
  published, or a modifier that had to be replaced. Never speculatively, and never
  as a way past a failure the bridge cannot explain.
- **Announced first**, through the bridge's own synthesizer, which is audible even
  when the reader is silenced — so nobody is dropped into silence unwarned.
- **Quit, WAIT for the process to exit, then `open -a`.** Measured 2026-08-31:
  `killall` alone does not bring the reader back, and the `&&` one-liner races.
- **It unblocks the one rung 13.20 could not climb**: a newly registered capture
  voice is published only after a restart, and that failure becomes a step.

### 3.3 The modifier is NOT replaced — the live run killed this, and it is 13.28

**This section proposed borrowing the VoiceOver modifier**, on a machine where
`vo` is bound to Caps Lock alone and this bridge therefore cannot press it: read
the person's setting, write Control-Option, restart, write their own value
straight back into the file, and restart once more at teardown. The file would
never hold our value for more than a moment, so a crash would cost only "the
reader is on Control-Option until it next restarts".

**IT WAS IMPLEMENTED, RUN LIVE ON 2026-09-02, AND REMOVED THE SAME EVENING.** The
sequence itself worked exactly as written — announced, wrote, restarted, wrote
their value back, all visible in the transcript. What the design got wrong is a
fact about the reader:

> **VoiceOver watches that key, and when it changes under a running reader it puts
> a modal question on screen asking the person whether they want to use
> Control-Option instead.**

§2.5 had measured that a write does not take EFFECT without a restart, and that
was read as "the running reader ignores it". It does not ignore it. Three
consequences, and none of them is a patch:

1. **The dialog blocks the reader from quitting**, so the teardown restart cannot
   run. Measured: *"VoiceOver was asked to stop and was still running 10 seconds
   later."* The reader is then left on the borrowed modifier with no session alive
   — precisely the state the design existed to make impossible.
2. **It changes the stored setting to something nobody chose.** The maintainer's
   `SCRVOModifierControlOption` came back as `SCRVOModifierControlOptionOrCapsLock`
   from a dialog he does not remember answering. Restored by hand, with the reader
   stopped, and verified byte-for-byte against a pre-run snapshot.
3. **A second defect the dialog hid.** Step 3 writes the person's value straight
   back, so every later read of `ReaderModifierSetting` returns *their* modifier
   and not the borrowed one — and the capture probe and every `vo+…` in the
   session are refused. The borrow accomplishes nothing even when it works.

**It is diagnosable only because a human said what was on his screen.** Nothing at
the bridge's layer can see a modal window, and three plausible hypotheses for the
failed quit — an auto-relaunch, a stale `NSRunningApplication` list, a race with
the launch — were all wrong. That is the same lesson as the wedged Finder: when
reads go quiet, ask what is in front of the person.

**The promising replacement is a launch argument rather than a write.** The
VoiceOver binary is a 16 KB launcher stub with no flags of its own, but it is a
Cocoa app, so `NSUserDefaults`' **NSArgumentDomain** may apply — `open -a VoiceOver
--args -SCRKeysToUseForVOModifier …` would set the modifier for one launch with
nothing persisted, nothing to restore and nothing for the reader to notice.
Unverified. **Board entry 13.28** owns it, and this spec claims none of it.

**What this costs 13.26, stated plainly:** a machine whose `vo` is Caps Lock alone
and whose AppleScript switch is off still gets no session. Rung 1 refuses it by
name, as it did before, and spec 0052 §3.3's refusal stands unchanged.

### 3.4 Writing that file: exactly one key, exported fresh, every time — NOT SHIPPED

**Nothing in this entry writes VoiceOver's own preferences.** §3.3's replacement
was removed by the live run, and this section went with it: `ReaderModifierStore`,
`VoiceOverPrefsModifierStore`, the `PlistWriter` seam and its leaf were all
implemented, tested and then deleted. It is kept here because the rules below are
right and whoever attempts 13.28 will need them the moment anything writes that
file again.

Marlon's requirement, and the hazard is real: **that file holds around 120
settings**, and `defaults import` replaces the whole domain.

- **Never keep a snapshot and import it later.** Export **fresh** at the instant of
  each write, set exactly one key, import. A snapshot taken at connect and imported
  at teardown would revert everything VoiceOver wrote in between — a Quick Nav
  toggle the person flipped, a rotor position, anything.
- **Verify the write took**, by reading the key back. A write that silently did not
  land is how spec 0047's finding 17 happened.
- **Count the keys either side, and treat a DROP as a failure** — loudly, in the
  transcript and in the session's error. Today's run was 120 → 120; that is what
  "accounted for exactly" looks like, and the check is what makes it checkable
  rather than hoped for.
- It is the same read → modify → write-back technique `SpeakSelectionVoiceStore`
  already uses, for the same reason: an old-style plist written with `defaults
  write` is re-read from `cfprefsd`'s cache and the evidence of the write is gone
  before you look.

**BUT NOT THROUGH `defaults`, AND THAT IS MEASURED.** The voice store reaches its
domain with `defaults export com.apple.SpeakSelection -`. The same call on
`com.apple.VoiceOver4` **returns an empty plist**: VoiceOver's settings live in a
**group container** (`~/Library/Group Containers/group.com.apple.VoiceOver/…`),
and `defaults` does not reach it. So this adapter addresses the **file**, and
`PlistBuddy` — which does work on it — was declined for one reason: the **key
count** is §3.4's safety check, and `PlistBuddy -c Print` answers it only as a
human-readable dump somebody would have to scrape. `PropertyListSerialization`
answers it exactly, round-trips the types for the same reason the voice store
parses rather than formats, and preserves the file's own on-disk format. The
adapter therefore holds a `PlistReader` and a new `PlistWriter` seam rather than
the `ProcessRunner` §4 first assumed, and it makes no subprocess at all.

### 3.10 One file records everything a session changed, so a crash is repairable

Marlon, 2026-09-02: *"If all changed files are recorded in one file, we have our
perfect snapshot."*

It answers ask 1 of
[the 2026-09-02 field report](../docs/feedback/2026-09-02-acter-run.md): *"Expose
an inventory of everything setup touches, and a `restore_reader_settings` call
that is safe to run blind."* The report's own recovery is what makes the case —
a handshake failed with the capture voice left selected, nothing in the MCP could
say what had been changed, and putting it back by hand **destroyed the user's
pitch, rate and volume and dropped them to a compact voice**. The information
needed to avoid that existed only in this repository's source.

- **One file, one fixed path**, appended to by every session:
  `~/Library/Logs/screen-readers-mcp/reader-changes.jsonl`. Beside the
  transcripts, because that is the directory `hello` already hands the agent a
  path into, and it is where a human already goes to find out what a run did.
  **Not** a per-session file: what a repair needs is *every* session's unfinished
  business, and a crashed session cannot be relied on to name its own file.
- **One JSON line per change**, and a matching line when it is put back. A change
  with no restore is an **open** change, and open changes are the whole product:
  they are exactly what a crashed session left behind.
- **Three kinds**, which is everything a session touches that is not machine
  state: `voice` (the selection), `modifier` (the preference file) and
  `runningModifier` (the reader's in-memory modifier, which is ours from the
  handshake's restart until teardown's).
- **`runningModifier` is recorded and is NOT repairable by editing anything**,
  and saying so is the point of it being its own kind. The FILE holds the
  person's own value the whole time (§3.3); what is ours is the running reader.
  The repair for it is a reader restart, and a tool that tried to "fix" it by
  writing the file would break the one thing §3.3 got right.
- **Nothing here throws**, which is `Transcript`'s contract for `Transcript`'s
  reason: a journal that could fail a session would be a record with more power
  than the thing it records. The cost is stated rather than hidden — a journal
  that could not be written is a change with no record, and it is the one failure
  in this design with no second line of defence.
- **`scripts/voiceover_restore.py` is the reader**, versioned in this PR because
  a checklist depends on it (the 2026-08-22 rule). It prints open changes, and
  `--apply` puts the voice back through the same export → modify → import
  mechanism `scripts/voiceover_voice.py` already carries.

**What this deliberately is NOT is a new wire command.** The field report asks for
a `restore_reader_settings` call; that is a change to the shared contract, the Go
binding, the capability gate and lane 1 as well as lane 3, and it is a board entry
of its own. The journal plus the script answers *"what did this leave behind, and
put it back"* today, with no protocol change, and it is what a wire command would
have to be built on anyway.

### 3.11 The `expert` may ask a HUMAN for the AppleScript switch, and that is all

Marlon, 2026-09-02: *"Then the expert can, if they need, request apple script
permission, and this has to be given by a human."*

**There is no mechanism to build, and that is the decision.** No API sets that
switch; writing VoiceOver's preferences behind the reader's back is the manoeuvre
that destroyed the maintainer's voice settings once already (spec 0047 finding
17); and it is read at reader startup. So "request" can only mean *ask the person
at the machine*, and this bridge has had that channel since 13.10 — `askUser`
speaks outside VoiceOver entirely and works in the one mode where the reader is
mute.

So it lands in two places and costs no port:

1. **§3.9's failure sentence** names the pane and tells the agent to `ask_user`
   for it and then reconnect — at the exact moment the agent discovers it wants
   the route.
2. **The `expert` document** says the same once, in the section that already tells
   that stance the channel may be unavailable.

`user` and `validator` are told nothing about it, per §3.8: a stance that may not
use the channel has no business asking somebody to open it.

### 3.5 Rung 1 asks for a ROUTE, not for every permission

The question becomes *is there a way to drive this reader at all?*

- **Accessibility granted AND `vo` pressable** → keys; or
- **Automation granted AND the AppleScript switch on** → command names.

Neither: refuse at rung 1, before anything is touched, naming **both** fixes —
because an agent told about one of them will send a human to grant the wrong
thing. `cannotTell` is not a route: it is read through a channel that may itself
be off, which is now the ordinary state.

Nothing here requests a grant. A handshake that waited for a modal nobody is
looking at is a handshake that hangs.

### 3.6 The capture proof has two routes, and the command name goes FIRST

1. **AppleScript available** → `perform command "speak the time and date"`;
2. **otherwise, keys** → press `vo+f7`;
3. **otherwise** → fail, naming both fixes.

**The command name first is deliberately the opposite of spec 0052's rule for
driving.** A keystroke passes the application under test and a command name does
not — that is the whole fidelity argument, and none of it applies to a probe,
which tests nothing in front of the person. The cheapest, least invasive route
wins: no grant, and no key event into whatever window they are sitting in.

### 3.7 Liveness stops being an AppleEvent

"Is VoiceOver running" is answered by the running-application list —
`com.apple.VoiceOver`, read out of the app's own `Info.plist` — which costs **no
permission** and cannot be switched off. The lookup is **case-sensitive** and a
wrong identifier answers "not running" forever with no error, so the spelling is a
constant with a test on it.

Spec 0041's distinction is not lost, it improves: the caller now combines this
answer with the switch's state and separates **three** conditions where the old
probe separated two.

### 3.8 Who may use the dispatch channel at all — the stance rule

Settled with 13.25 and recorded in both specs, because this entry is what makes it
consequential: with the switch off the channel is simply not there, so instructing
an agent to reach for it would be instructing it to fail.

- **`user` and `validator`: keys only.** A person cannot dispatch a command by
  name; an act with no bound key is reached through the Commands menu — `vo+h`
  twice, type, Enter — which is itself keys.
- **`expert`: the channel is an instrument**, and the guidance says plainly that it
  may be unavailable on the machine in front of it.

### 3.9 A failed command name says which of the three it is

| What is true | What the agent is told |
|---|---|
| the reader is not running | it is gone; start it |
| running, and the switch is off or unreadable | this machine does not offer that route — **press the key instead** |
| running, switch on, and it still failed | the object model is dead; the recovery is a reader restart |

## 4. Class/file layout

| File | Role | Change |
|---|---|---|
| `Adapters/Ports/RunningApplications.swift` | **adapter seam — new** | "is this bundle identifier running?" |
| `Adapters/WorkspaceRunningApplications.swift` | **leaf — new** | `NSRunningApplication`. No decisions, no test file. |
| `Adapters/VoiceOverLiveness.swift` | adapter — **amended** | answers over that seam; keeps `activate()` on the `ProcessRunner`; keeps the name script for the permission broker. |
| `Domain/Ports/ReaderLiveness.swift` | port — **amended** | `readerIsRunning()`, and the header carries §3.7. |
| ~~`Domain/Ports/ReaderModifierStore.swift`~~ | **written, then DELETED** | The write side of the modifier. Implemented, unit-tested and removed the same evening — see §3.3. |
| ~~`Adapters/VoiceOverPrefsModifierStore.swift`~~ | **written, then DELETED** | §3.4's read → modify → write-back. Its tests passed; the design is unsound on a running reader. |
| ~~`Adapters/Ports/PlistWriter.swift`~~, ~~`Adapters/FilePlistWriter.swift`~~ | **written, then DELETED** | The seam and leaf that let anything in this bridge write a plist. **Nothing does, and that is a property worth keeping** — `PlistReader` is read-only again and its header says why. |
| `Domain/Ports/ReaderRestart.swift` | **port — new** | quit, wait for exit, start again. Its own port rather than a method on `ReaderLiveness`, because §3.2 makes it an act with a policy attached rather than a question. **One caller as shipped**: the registration rung. |
| `Adapters/VoiceOverRestart.swift` | **adapter — new** | §3.2's sequence. Holds a `ProcessRunner`, the `RunningApplications` seam and a `Clock` — the wait for the process to be **gone** is the whole point, and a clock in an adapter is `PluginKitProviderLifecycle`'s existing shape. |
| `Domain/Ports/ChangeJournal.swift` | **port — new** | §3.10. Owns `ReaderChange`, its own DTO. Nothing throws, per `Transcript`. |
| `Adapters/FileChangeJournal.swift` | **adapter — new** | one JSON line per change, at the fixed path. Over the existing `FileWriter` seam, exactly as `FileTranscript` is. |
| `scripts/voiceover_restore.py` | **instrument — new** | reads the journal, prints open changes, `--apply` puts the voice back. |
| `Domain/Controllers/ReaderEdgeSetup.swift` | controller — **amended** | §3.1's preparation, §3.5's rung 1, §3.6's two-route proof, and the restart that PUBLISHES a newly registered voice — the rung 13.20 could not climb. |
| `Domain/Controllers/Session.swift` | controller — **amended** | teardown reverses the session state: the voice, and it closes the journal entry. |
| `Domain/Entities/SetupRung.swift` | entity — **unchanged as shipped** | A sixth rung for the modifier existed between `voiceSelection` and `captureProof` for an afternoon; §3.3 took it out again, and the enum has its five. |
| `Domain/Ports/AdapterFactory.swift` | port — **amended** | `readerScripting`, `readerRestart` and `changeJournal` join the set. |
| `Domain/Controllers/Commands/PressGesture.swift` | controller — **amended** | §3.9's three-way diagnosis, and §3.11's sentence. |
| `Entities/Documents/common.md` | document | what a session does to the machine, and what it puts back; the ring (§2.4); and that `killall && open -a` races. |
| `Adapters/PublishedVoices.swift` + `SystemPublishedVoices` | seam + leaf — **amended** | `refresh()`. **The live run's other finding**: a registered provider's voices do not appear until something asks the system to re-read them (`AVSpeechSynthesisProviderVoice.updateSpeechVoices()`). `CaptureProbe` had called it since 13.4 and the handshake never did, so the first connect registered, restarted the reader to publish the voice, and the voice had never been published. |
| `Domain/Ports/ProviderLifecycle.swift` | port — **amended** | `publish()`, separate from `register()` for the reason above, and it polls. |
| `Entities/Documents/expert.md` | document | §3.11: ask the human for the switch, and reconnect. |
| `scripts/voiceover_without_applescript.sh`, `voiceover_press_count.sh` | instruments — new | §2.1 and §2.4, already landed. |

## 5. The live checklist this earns

Run with the AppleScript switch **off**, which is the state this entry exists for.
**Run on 2026-09-02; results and the finding that removed items 5–8 are in
[PR #98](https://github.com/marlon-sousa/screen-readers-mcp/pull/98).**

1. `bash scripts/voiceover_without_applescript.sh` reports §2.1's four answers.
2. `connect_reader` establishes a silent session with the switch off.
3. `press_gesture ["vo+m"]` drives it and speech comes back.
4. `press_gesture ["go to menu bar"]` fails and names the switch, telling the agent
   to press the key — not "the reader is not responding".
5. The person's preference file is **byte-identical** before and after a whole
   session, key count included. *(This replaced four items about the modifier
   replacement, which §3.3 no longer does.)*
6. A session killed with SIGPIPE leaves an OPEN entry in the change journal, and
   `python3 scripts/voiceover_restore.py --apply` puts the voice back with pitch,
   rate and volume intact.
7. With the switch back **on**, a session still establishes and a command name
   still works — the control, so none of the above is bought by breaking the route
   that already worked.

## 6. Honest limits

- **The command-name route is genuinely gone** with the switch off, and with it the
  acts that have no key at all (spec 0052 §2.4). That is a real loss of capability
  for a real reduction in what the machine exposes, and the guidance says so.
- **A Caps-Lock machine with the switch off still gets no session at all.** §3.3
  was the answer to that and the live run withdrew it, so spec 0052 §3.3's refusal
  stands unchanged and rung 1 names it. **Board entry 13.28** owns the retry.
- **A registration still costs one reader restart**, because macOS publishes a
  newly registered voice no other way. It is paid only by whoever has just run
  `poe build`; a person who has not rebuilt anything pays nothing.
