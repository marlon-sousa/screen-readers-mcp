# 0056 — The voice a session leaves behind

**Status:** Proposed (2026-09-03)
**Board entries:** 13.24, 13.32 and 13.33 (lane 3), bundled — see §0.
**Amends:** [0050](0050-the-handshake-climbs-the-ladder.md) §2.7 (what rung 4 records),
[0053](0053-the-bridge-prepares-the-reader.md) §3.10 (what the repair script does)

## 0. Why three board entries are one spec

They are three failure points on **one setting**: the voice a session leaves
selected on somebody's machine. All three were produced by 13.31's own live
checklist on 2026-09-03, on the maintainer's machine, in this causal order:

1. **13.33** — the session never reaches teardown. `askUser` kills the launcher
   with SIGILL, so nothing is put back.
2. **13.24** — even when teardown does run, the identifier it writes back may no
   longer resolve, and the reader falls back to its default with nothing
   anywhere saying so.
3. **13.32** — the tool that exists to recover from either one reports the
   journal instead of the machine, does not apply on `--apply`, and prints a
   command that would write a voice id into `SCRKeysToUseForVOModifier`.

They also share **one design question** — what a session may do with a voice
identifier that does not resolve — which is settled once, in §2, and answered
identically in all three places. Splitting them would mean asking it three times
and risking three answers. Marlon approved the bundle on 2026-09-03.

The order below is the implementation order, and it is not negotiable: this PR's
live checklist has to deliberately kill a session and recover from it, and today
that ends in SIGILL before anything can be observed.

## 1. 13.33 — the launcher has no main run loop

### 1.1 What happens

`BridgeListener` dies with **SIGILL (exit 132)** the moment `askUser` opens its
AppKit window, preceded by *"Attempting to add timer to main runloop, but the
main thread has exited"*.

`Sources/BridgeListener/main.swift` ends with `dispatchMain()`, which parks the
main thread **by exiting it**. AppKit needs a real main run loop, so
`AppKitPromptWindow.open` schedules `DispatchQueue.main.async` onto a run loop
that is not there.

It is **pre-existing and not caused by 13.31** — `main` was built in a git
worktree as a control and crashes identically. What hid it is that `askUser` is
only reached by `poe live`, whose script asks its question last and prints its
closing summary before the process dies.

### 1.2 The two candidates, and the one taken

The board entry named two: the launcher runs an `NSApplication` of its own, or
`UserPrompter` is not reachable from it and refuses **by name** rather than
crashing.

**The launcher runs an `NSApplication`.** Three arguments:

- **It does not pre-empt 13.14.** That entry gives the **shipped bundle**
  (`VoiceOverBridgeApp`) a control dialog wired through `Wiring.controlSurface`.
  `BridgeListener` is a dev launcher that `build.sh` deliberately does not copy
  into the bundle. Borrowing AppKit's run loop is not designing a UI, and 13.14
  is free to design one without reference to this.
- **The refusal costs the live tier its only human channel.** `askUser` and
  `waitForUserReply` are half the `interact` capability, and until 13.14 the
  launcher is the only way a bridge is started on this platform. Refusing by
  name would make that half of 13.10 unexercisable live, indefinitely.
- **It is five lines and no new file.** The alternative is a new refusing
  adapter, its fake, its tests, and a `Wiring` fork keyed on which executable is
  running — for the privilege of making a working feature not work.

`.accessory` activation policy: no Dock icon and no menu bar, which is what a
launcher wants, and `NSApp.activate(ignoringOtherApps:)` in `PromptPanel` still
works for an accessory app.

### 1.3 What is NOT claimed

There is no headless test for this, and there must not be one: a real
`NSApplication` in a test process takes focus from whatever the developer is
doing and announces itself out loud on a machine with a screen reader running —
which is `AppKitPromptWindow`'s own no-test-file rule, one layer up. It is
proved by the live checklist and by nothing else.

## 2. 13.24 — the identifier that is used without being resolved

### 2.1 The correction that decides everything below

The board entry says *"a voice identifier is used without ever being resolved"*,
and the natural reading — that this is the 13.20 shape and should therefore be
refused the way 13.20 refuses an unusable capture voice — **is wrong, and the
distinction is the whole of this section.**

There are two identifiers, and only one of them is unresolved:

| Identifier | Resolved today? | By what |
|---|---|---|
| **The capture voice** (ours) | **Yes** | `PluginKitProviderLifecycle.publishedCaptureVoice()` matches by suffix against the machine's real published list, and rung 4 fails by name when there is no match |
| **The user's own voice** | **No** | recorded verbatim from the preference at rung 4, and used twice afterwards without ever being checked against the machine |

So an unresolvable identifier here **never makes `getSpeech` meaningless**, and
13.20's precedent does not transfer. What it actually costs is:

- **In live mode**, pass-through re-speaks the reader's utterances in a
  substitute voice for the session's whole duration.
- **At teardown, in both modes**, the bridge writes a dead identifier into the
  preference. The write succeeds, the read-back confirms it, and VoiceOver falls
  back to its default at speech time — so every call involved reports success
  and the person is left on a voice they did not choose.

### 2.2 The decision

Put to Marlon on 2026-09-03, with the correction above. His answer:

> *"I would like to have a default voice, but that handshake announcement must
> let the user know and give them instructions to install the voice."*

**Decided: resolve and report; never refuse. In both modes.** The reasoning the
recommendation was made on, recorded because it is what the next entry will have
to argue against:

- The machine was **already** in that state before the session connected. The
  session did not cause it and cannot fix it, and refusing a handshake for a
  pre-existing condition denies testing on a reader that is otherwise perfectly
  capable of everything the session wants.
- Refusing does not put the voice back. In silent mode pass-through renders
  nothing at all, so the user's own voice is unused for the entire session and
  the only cost is at teardown — which a refusal does not reach.
- **The defect 13.24 names is the SILENCE, not the fallback.** A fallback that
  says so by name, out loud, to the person who can act on it is not the failure
  this entry exists to kill.

### 2.3 The honest limit, stated rather than discovered

The resolution asks the same authority the capture voice's does:
`AVSpeechSynthesisVoice.speechVoices()`, through the existing `PublishedVoices`
seam. That list contains voices which are **advertised and not installed** —
13.15 measured exactly that, with `com.apple.eloquence.pt-BR.Reed`, which is the
maintainer's own voice: every request for it falls back to Luciana, in `say` and
in VoiceOver itself as much as here, and the two render byte-identical audio.

**So this check catches a voice that was REMOVED, and not one that was never
installed.** It is the difference between "the system does not publish this
identifier" and "the system publishes it and cannot speak with it", and the
second is board entry 13.15's, unanswerable from this layer and not claimed
here. The port method is named `systemPublishesVoice` for exactly that reason —
a name like `voiceIsInstalled` would be a sentence this bridge cannot back up.

It also decides the live checklist: **the warning cannot be demonstrated with
the maintainer's own voice**, because his machine publishes it. It is
demonstrated with a synthetic identifier — see §5.

### 2.4 One resolution covers both call sites

Both places that use the recorded identifier consume the **same** field,
`SessionContext.previousVoice`, so one check at rung 4 covers both:

- **Teardown** (`Session.teardown` → `providerLifecycle.restoreVoice`).
- **Live pass-through** (`ReaderEdgeSetup.openSilenceChannel` →
  `silenceControl.begin(preferredVoice:)` → the marker file → the extension).

And the extension end is **already correct**: `VoiceChoice` rule 0 degrades
rather than assumes, `CaptureController` records
`passthrough_voice_asked` / `passthrough_voice_in_catalogue` as two separate
facts, and 13.11's header says why. So the marker keeps carrying the identifier
unchanged — dropping it would lose the `in_catalogue: no` evidence — and what
this entry adds is the sentence **above** the extension that nobody was saying.

### 2.5 What teardown does, and what it deliberately does not

Teardown **still writes the dead identifier.** That is not a compromise, it is
the correct act: writing it is what takes the reader **off the capture voice**,
and leaving the capture voice selected is 13.23's hazard — the next reader
restart finds it unpublished, falls back to the default *and persists the
fallback*, destroying the record of the person's own voice. A restore that
refused to write would be a cleanup that caused the disaster it was cleaning up
after.

What changes is that it **says so**: the transcript records that the restore was
degraded and names the identifier.

**The journal line is NOT touched.** `FileChangeJournal`'s contract is that a
restore is *the same line with `restored` true*, which is what makes pairing
work and is asserted in `FileChangeJournalTests`. A degraded restore is still a
restore — the change is closed, the capture voice is off — so it journals
exactly as a clean one does, and the detail lives in the transcript.

**Teardown does not announce.** Marlon asked for the announcement at the
handshake, and that is where it goes. Teardown is the moment a person is getting
their reader back, and a spoken paragraph into that is noise. **The gap this
leaves is stated:** a voice removed *mid-session* is announced to nobody, only
noted. That requires somebody to uninstall a voice while a test runs, which they
would know they had done — and if it ever proves wrong it is one line, not a
redesign.

### 2.6 Where the sentence lives

`ReaderCondition` gains a fifth case, `usersVoiceNotAvailable`. It is the
entity that already exists for exactly this — a diagnosis and its measured
recovery, rendered once so the two cannot travel apart — and its `recovery` is
already written for **the human at the machine**, which is the audience Marlon
named.

**It is the first case that is not about the capture voice**, and no
`ProviderState` maps to it: it is read directly by `ReaderEdgeSetup` and
`Session`. That is stated in the case's own comment rather than left for
somebody to find surprising.

The recovery names the path in full: **System Settings > Accessibility > Spoken
Content > System Voice > Manage Voices.**

## 3. 13.32 — the restore script does not restore

Three defects, in the entry's order of how badly they mislead. **The journal
half works and is not touched** — the change was recorded correctly, with the
right previous value; only the recovery half was never exercised against a real
open change.

### 3.1 It reports the JOURNAL rather than the MACHINE

`describe()` prints `it is now: {change.get('now')}` — a field the journal wrote
when the change was made. After the voice had been put back by another route it
went on printing *"it is now: the screen-readers-mcp capture voice"* as a
statement of fact.

It is a log reader presenting log state as machine state, and the person reading
it is by definition somebody recovering from a crash — the worst moment to be
told a false thing confidently.

**Fix:** read `com.apple.SpeakSelection` once, at the top of `main`, and print
what the machine says beside what the journal says. When they disagree because
the voice is no longer ours, say so — *"already put back, by something other
than this script"* — and do not offer to apply.

The read is a separate function and `describe()` takes the machine's answer as a
parameter, so the reporting stays pure. `scripts/` is linted but not
type-checked and has no test harness (that is the existing shape for every
script in that directory), so purity here buys reviewability rather than a test.

### 3.2 `--apply` did not apply

`restore_voice()` is defined and **never called**. `acted` is never set, so the
summary line is wrong in both directions.

This landed broken in one commit — `git log` shows the file has exactly one,
b558c6e (13.26) — as a botched removal of the modifier branch: the
`if kind == "voice":` half that called `restore_voice` was deleted along with
the modifier kind, and its `else` survived as `if True:`.

**Fix:** call it, set `acted`, and re-read the machine afterwards so the closing
line reports what is true rather than what was attempted.

### 3.3 The instructions name the WRONG KEY

It offers:

```text
PlistBuddy -c 'Set :SCRKeysToUseForVOModifier com.apple.eloquence.pt-BR.Reed'
```

— setting the **VoiceOver modifier** to a voice identifier. A human following it
would put a voice id into the setting that decides what `vo` is, which is the
setting 13.26 already learned not to write: VoiceOver puts a modal question on
screen when it changes under a running reader, which blocks the reader from
quitting. This one is close to dangerous rather than merely wrong.

**Fix: the whole block is deleted**, together with the `if True:` that made it
unconditional. Nothing in this repository writes VoiceOver's own preferences,
`PlistReader`'s header says so, and a script that prints an instruction to do it
is that rule broken in the place a human is most likely to obey.

### 3.4 A fourth defect, found by fixing the first — and a fifth, by the live run

**The headline counted the journal too.** *"1 setting(s) still changed"* is the
first thing somebody reads, and it was computed from entries with no `restored`
line — so it said one thing was still changed over a machine that had already
been put back. That is §3.1 one level up, and it is the sentence that would send
a person recovering from a crash looking for a problem that no longer exists.
`is_open_on_the_machine` now keeps the two questions apart, with **"I could not
read the preference" counting as open** — the same rule `process_is_running`
applies to a pid it does not own.

**And the fix for §3.1 committed §3.1 again, which the live run caught.** The
machine was read **once**, on the reasoning that every change should be reported
against one consistent snapshot. That is a good rule for a report and the wrong
one here, because **this loop mutates the machine it is describing.** Measured
2026-09-03 on the maintainer's machine with two open changes in the journal: the
first was applied, and the second was then described against the pre-write
snapshot — printing *"which IS the capture voice. This change is still open."*
about a reader that had just been put back, and writing it a second time.

It was harmless on that run only because both entries recorded the same previous
voice. **Two entries recording different voices would have had the second
overwrite the first's repair**, which is a repair tool undoing its own work. So
`current` means "what the machine says now" and is refreshed after every write.

**That is the entry's own thesis landing on the entry**, and it is written down
rather than quietly fixed: a reading taken before the thing you did is not a
report of the machine, however carefully the read itself was written.

### 3.5 §2.2's decision, in the script

A person running this is recovering from a crash, so the case they are most
likely to hit is the one §2 is about: the recorded previous voice is gone.

The script **does not resolve identifiers** — there is no `speechVoices()` from
stdlib Python, and `say -v '?'` prints names rather than identifiers and answers
about a cache that spec 0047 finding 18 measured lying for an hour. Inventing a
resolution mechanism here would be inventing a second authority that can
disagree with the bridge's.

So it does what §2.5 decided teardown does: **it writes the identifier**, which
takes the reader off the capture voice, then re-reads the machine and prints the
one sentence that covers the case honestly — *if the reader still does not sound
like your own voice, that voice is no longer installed*, with the Manage Voices
path.

## 4. The file layout

### Amended — `bridges/voiceover/`

| File | Role | Change | Collaborators |
|---|---|---|---|
| `Sources/BridgeListener/main.swift` | launcher (not in the bundle) | `import AppKit`; `NSApplication.shared` with `.accessory` policy, created on the main thread; `app.run()` replaces `dispatchMain()`. **Header fold-in:** the AppleScript and Automation rows went with 13.31 and the header still advertises them (§6). | unchanged — `Wiring`, `SimpleEventBus` |
| `Sources/VoiceOverBridgeDomain/Ports/ProviderLifecycle.swift` | port | adds `func systemPublishesVoice(_ identifier: String) -> Bool`. Never throws: "the system does not publish it" is an **answer**, in the same way `state()` never throws. Its doc comment carries §2.3's limit. | implemented by `PluginKitProviderLifecycle` and `FakeProviderLifecycle` |
| `Sources/VoiceOverBridgeAdapters/PluginKitProviderLifecycle.swift` | adapter | implements it over the `PublishedVoices` seam it already holds — the same authority `publishedCaptureVoice()` uses, read a second time rather than duplicated | `PublishedVoices` |
| `Sources/VoiceOverBridgeDomain/Entities/ReaderCondition.swift` | entity | fifth case `usersVoiceNotAvailable`, with its summary and its measured recovery (Manage Voices). First case not about the capture voice, and mapped to by no `ProviderState` — said in the case's own comment | read by `ReaderEdgeSetup` and `Session` |
| `Sources/VoiceOverBridgeDomain/Controllers/ReaderEdgeSetup.swift` | controller | rung 4 resolves `previous.identifier` and, when the machine does not publish it, `warn()`s the human — the existing announcer path, audible in silent mode because it goes around the reader — and notes it. **Records the identifier anyway**, per §2.5 | `AdapterSet.providerLifecycle`, `AdapterSet.announcer`, `SessionContext` |
| `Sources/VoiceOverBridgeDomain/Controllers/Session.swift` | controller | teardown asks `systemPublishesVoice` before restoring and notes a degraded restore by name. Still writes, still journals `restored` | `AdapterSet.providerLifecycle`, `Transcript` |

**No new Swift file, and no new field on `SessionContext`.** Teardown asks the
port rather than reading a flag the handshake set, so the two places cannot come
to disagree about a machine that changed between them.

### Amended — `scripts/`

| File | Role | Change |
|---|---|---|
| `scripts/voiceover_restore.py` | the journal's reader | reads the machine once (§3.1); `describe()` takes that answer as a parameter and reports both; `--apply` calls `restore_voice` and sets `acted` (§3.2); the `if True:` / PlistBuddy block is deleted (§3.3); the closing summary re-reads the machine; the not-installed sentence is added (§3.4) |

### Amended — tests

| File | What it gains |
|---|---|
| `Tests/Fakes/ProviderLifecycle.swift` | `systemPublishesVoice`, over a settable set of identifiers, defaulting to "publishes everything" so no existing test changes meaning |
| `Tests/VoiceOverBridgeAdaptersTests/PluginKitProviderLifecycleTests.swift` | the new method against the fake published list, both answers |
| `Tests/VoiceOverBridgeDomainTests/Controllers/ReaderEdgeSetupTests.swift` | a handshake whose previous voice the machine does not publish **establishes**, announces once, and still records the identifier — the three halves of §2.2 |
| `Tests/VoiceOverBridgeDomainTests/Controllers/SessionTests.swift` | teardown restores a voice the machine no longer publishes, journals it as restored, and notes the degradation |
| `Tests/VoiceOverBridgeDomainTests/Entities/ReaderConditionTests.swift` | the new case renders with its recovery, if that file exists; otherwise the rendering is asserted where the callers are |

### Not changed, and each is a decision

- **The wire.** `HelloResult` has no notes field, and adding one is a protocol
  change across three bindings for a message whose audience is **the person at
  the machine**, who has already been told out loud and more effectively. The
  agent's only action would have been to tell them. Stated as a limit, not
  hidden.
- **`ReaderChange` and `FileChangeJournal`.** §2.5.
- **The capture voice and `VoiceChoice`.** §2.4 — already correct.
- **`ProviderState`.** The new condition is not a state of the capture voice.

## 5. Live checklist

Every item drives the maintainer's real VoiceOver and is asked for before it is
run. Two of them need a fixture, and per the 2026-08-22 rule it is versioned in
this PR rather than improvised: **`scripts/live_pages/` gains nothing** — the
fixture here is a *synthetic voice identifier*, which lives in the checklist
item itself because it is one string and a file for it would be worse.

The identifier is `com.apple.voice.compact.xx-XX.NoSuchVoice`, chosen so that it
cannot collide with anything the machine publishes.

- **13.33 — `askUser` no longer kills the launcher.** Start `BridgeListener`,
  connect, `ask_user`, answer the window, `wait_for_user_reply`. The process is
  still alive afterwards and the answer came back.
- **13.33 — the control.** The same, with `main` built in a worktree, confirming
  SIGILL / exit 132 there. Recorded as the before, not as a pass.
- **13.24 — a voice the machine does not publish is announced.**
  `voiceover_voice.py set com.apple.voice.compact.xx-XX.NoSuchVoice`, connect
  live, and hear the announcement name the voice and the Manage Voices path. The
  session **establishes**.
- **13.24 — and it is put back anyway.** Disconnect; the preference holds the
  synthetic identifier again and not the capture voice; the transcript says the
  restore was degraded. Then
  `voiceover_voice.py set com.apple.eloquence.pt-BR.Reed` and verify.
- **13.24 — the ordinary machine is unchanged.** Connect and disconnect with the
  real voice selected: no announcement, a clean restore, and
  `voiceover_voice.py show` reports `com.apple.eloquence.pt-BR.Reed`.
- **13.32 — the crash, and the recovery.** Connect silent, `kill -9` the
  launcher after the handshake, then `voiceover_restore.py`: it reports one open
  change and **what the machine currently says**. Then `--apply`: the voice is
  put back and the closing line says so. Then run it again: nothing is open.
- **13.32 — it does not lie about a repair somebody else did.** Reproduce the
  open change, put the voice back with `voiceover_voice.py`, then run
  `voiceover_restore.py` with no flags: it reports the change as already put
  back rather than as still open.
- **The crash census**, from both sources, per spec 0046 part 1(c):
  `~/Library/Logs/DiagnosticReports/` (and `Retired/`) and
  `SCRCUserDefaultsUnplannedShutdownCount`.

**One source of the census was unavailable on this run, and that is worth
recording rather than glossing.** The reader's own counter lives in
`com.apple.VoiceOver4/local.plist` (spec 0046 part 2), and **that file does not
exist on this machine** — the group container holds only `default.plist` and
`journal.plist`. So the census had one source, not two, and the reason the rule
asks for two is exactly that they can disagree. Nothing was inferred from the
missing one.

**And do not reach for `PlistBuddy -c Print` to read it.** On a file that is not
there it answers *"File Doesn't Exist, Will Create"*, which reads like a warning
that it has written something. It has not — only `Save` writes — but the sentence
is alarming enough on a blind person's screen reader preferences to be worth
knowing before you type it. Verified after the fact: both files' timestamps
predate this run.

## 6. The fold-in

`Sources/BridgeListener/main.swift`'s header still says the launcher prints
*"whether AppleScript control of VoiceOver is on"* and that *"the permission
rows cost a subprocess since 13.11, because the automation one is a fact about
the channel"*. Both rows went with 13.31, and the code block at the bottom of
the same file already records that they did. The header is corrected in this PR
because it is the file this entry is editing and a header that contradicts its
own code is worse than no header.

## 7. What this does not decide

- **13.15** — a voice that is advertised and not installed. §2.3.
- **13.14** — the control dialog. §1.2 borrows AppKit's run loop in a dev
  launcher and designs no UI.
- **13.28** — a machine whose `vo` is Caps Lock alone.
- Whether the **agent** should learn at `hello` that the user's voice is gone.
  §4, "Not changed".
