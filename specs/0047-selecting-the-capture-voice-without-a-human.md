# Spec 0047 — selecting the capture voice without a human

**Status:** a measurement, in the shape of
[spec 0041](0041-can-voiceover-say-what-it-said.md) and for the same reason: the
alternative is to assume. Taken on **2026-08-29**, on **macOS 15.0 (24A335)**,
against the maintainer's live VoiceOver. It adds no production class and
therefore carries no class/file layout, exactly as spec 0041 did.

It exists because [spec 0043](0043-the-voiceover-bridge-is-one-swift-bundle.md)
states two costs and does not test them:

> Updating the provider means restarting the screen reader.

> The user must select the capture voice in VoiceOver Utility.

Both are stated as facts of the route. **One of them turns out to be false**, and
the investigation of the other found a third thing nobody was looking for, which
is a risk to [spec 0046](0046-the-voiceover-bridge-class-by-class.md)'s entry
13.7.

## The question, in the maintainer's words

> I wonder if you can't do it yourself, you can press keys, so perhaps you can
> restart. I wonder also whether it is possible to start VoiceOver with a given
> profile — if that is true, then you can create a profile with the voice and
> the problem would be solved.

And, once the shape was clear:

> We could just create a profile with only the voice, because it inherits the
> default configs.

That last sentence is the design this document evaluates, and **it is the right
design**. What defeats it is not its content but its activation.

## Finding 1 — restarting VoiceOver is scriptable, and needs no keystroke

**Measured, six times, all clean:**

```sh
osascript -e 'tell application "VoiceOver" to quit'      # gone in 2.0 s
osascript -e 'tell application "VoiceOver" to activate'  # back; 13.8 s round trip
```

`quit` is in VoiceOver's own dictionary (`VoiceOver.sdef`, `aevtquit`), so this
needs **only the AppleEvents-to-VoiceOver grant the bridge already requires** —
no Accessibility, no synthesized Command-F5, no `sudo`, no
`VoiceOverStarter`.

**This retires one of spec 0043's stated costs.** Updating the provider still
requires a reader restart — that is a fact of the platform, measured in spec 0041
C2 — but the restart is now a *scripted step* rather than a manual one, which is
a different thing to write in a README and a different thing to ask of a user.

**It is better than the keystroke route the question proposed**, and the reason
is a permission rather than a convenience: synthesizing Command-F5 needs
Accessibility, which is the *wider* grant that spec 0046's entry 13.8 works to
keep lazy. Scripted restart is available to a session that has never asked for
Accessibility at all.

**`VoiceOverStarter` takes no arguments.** Its only interesting string is
`******** Launching VoiceOver from starter application ********`. There is no
launch-time configuration switch of any kind.

## Finding 2 — the voice is one preference key, and writing it does nothing

The key was **read out of the system rather than guessed**, which matters because
spec 0046 already records that *absent* is ambiguous between "off" and "we
guessed the key name wrong":

```
SCRCategories_SCRCategorySystemWide_SCRSpeechComponentSettings_SCRVoiceIdentifier
```

- The leaf `SCRSpeechComponentSettings_SCRVoiceIdentifier` comes from the dyld
  shared cache, alongside `SCRVoiceUseCustomizedVoiceSettings`,
  `SCRPitchAsPercent`, `SCRRateAsPercent` and `SCRVolumeAsPercent`.
- The `SCRCategories_SCRCategorySystemWide_…` prefix is not inferred: the
  maintainer's own preferences already carry
  `SCRCategories_SCRCategorySystemWide_SCRSpeechComponentSettings_SCRDisableSpeech`.
- Its default value is `''`, and its sibling `SCRFallbackVoiceIdentifier` is
  `com.apple.voice.compact.en-US.Samantha` — both decoded from
  `ScreenReaderConfiguration.archived-scrconfig`. So the field holds an
  **`AVSpeechSynthesisVoice` identifier**, which is exactly the shape of a
  published provider voice.

**"Categories" are speech categories, not profiles.** The vocabulary is
`SCRCategoryAnnouncement`, `SCRCategoryContent`, `SCRCategoryCommand`,
`SCRCategoryGreeting`, `SCRCategoryGuide`, `SCRCategoryBraille`,
`SCRCategoryCaption` and more; `SCRCategorySystemWide` is the catch-all. So
VoiceOver can use a **different voice per category**, which is a capability
nothing in lane 3 currently uses and which is recorded here rather than
rediscovered.

**The experiment (reversible, and reversed):** back up the preferences, stop
VoiceOver so its in-memory copy cannot clobber the write, write the key, flush
`cfprefsd`, start VoiceOver, ask it to speak, then restore.

**Result: nothing.** Zero events reached the extension's container file during
the whole run — and critically **no `audio-unit-created` event**, so VoiceOver
never instantiated our voice, let alone spoke through it. The write itself was
sound: the value read back correctly and *survived* VoiceOver's session, so
VoiceOver neither consumed nor removed it. It simply ignored it.

Afterwards the preferences were verified **byte-identical** to the backup.

**All three hypotheses below are now DEAD**, killed by finding 10: setting the
voice by hand writes nothing to any of these files. They are kept because the
reasoning was sound and the elimination is the useful part.

Three hypotheses, in the order this document rated them:

1. **The write used the wrong door.** Guidepup — the state of the art — writes
   `defaults write com.apple.VoiceOver4/default SCREnableAppleScript -bool true`,
   naming the **CFPreferences domain**. This experiment wrote the *file path*.
   VoiceOver reads through CFPreferences, so a file-path write may be invisible
   to it even after a `cfprefsd` flush. **This is the cheapest thing to try next
   and it is not yet tried.**
2. **The journal is the index of what has been customised.** `journal.plist`
   sits beside the preferences and maps 38 customised settings to the
   `CFAbsoluteTime` each changed, including the maintainer's own
   `…SCRSpeechComponentSettings_SCRDisableSpeech`. The written key was never
   journalled. VoiceOver may honour only journalled keys.
3. **The voice needs a companion setting**, most likely
   `SCRVoiceUseCustomizedVoiceSettings`.

## Finding 3 — an activity carrying only the voice is the right design

Apple's documentation confirms the premise the maintainer proposed: an activity's
settings are customised by **ticking a checkbox and clicking Set for each
option**, so everything unticked **inherits**. An activity carrying only a voice
overrides one setting and nothing else.

**That is materially different from Guidepup's mechanism, and the difference is
the one spec 0046 cares about.** Guidepup's `getPreferences()` reads a portable
plist mounted from a disk image, and its setup **symlinks the user's VoiceOver
preference files to that image**. Spec 0046 refuses that outright, because it
replaces a blind developer's screen-reader configuration wholesale. A
one-setting activity does not: it is additive, it is visible in VoiceOver
Utility, and the user can delete it. **Spec 0046's objection does not apply to
this design**, and that is worth stating explicitly so nobody transfers the
refusal by association.

**Portable Preferences is, for the record, an Apple-supported feature** —
VoiceOver Utility → File → Set Up Portable Preferences, backed by a disk image.
It is not a hack. It is still wholesale replacement, so it stays refused for this
project's own machine, and the reason is now "wrong granularity" rather than
"unsupported mechanism".

**What defeats the design is activation.** Apple documents exactly three routes
and there is no fourth:

| Route | Scripted? |
|---|---|
| **VO-X**, Activity Chooser, arrow keys, Return | No — a UI chooser |
| **VO-X-X**, previous activity | Only through `perform command` |
| **Automatically, by app or website** | Yes, but bound to *which app is frontmost* |

Confirmed against the command table and the default keybindings:
`open activity chooser` → `SCRWorkspace.openProfiles`, press count 1 on `x`;
`previous activity` → `SCRWorkspace.previousProfile`, press count **2** on the
same key. **Activities are called *profiles* internally**, and the preference
vocabulary is `SCRCUserDefaultsCurrentProfile`, `SCRCUserDefaultsAllProfiles`,
`SCRCUserDefaultsProfileApplications`, `SCRCUserDefaultsCustomProfileKeys`, with
`SCRCDidChangeCurrentProfileNotification` and
`SCRCUserDefaultsUpdateProfilesNotification`.

**The third route deserves more thought than it first attracts.** Binding an
activity to an *application* is useless for a bridge that drives arbitrary apps —
but it is exactly right for the first use case this project was built for,
functional testing of one add-on or one app. It is recorded here as a live
option, not dismissed.

**The default configuration archive contains no profile template**, because
profiles are user data. So the storage shape cannot be learned by reading the
system: **one activity has to exist before it can be described**, which is the
concrete thing this document cannot do alone.

## Finding 4 — `perform command` is dead on this machine, and that is a risk to 13.7

Found while testing route 2 above, and it is the most consequential thing here.

| Channel | Result |
|---|---|
| `return name` | works |
| `content of last phrase` | works — returned a full Portuguese sentence |
| `text under cursor of vo cursor` | works — `"visualização por lista tabela"` |
| `output "…"` | works |
| `perform command` — **any** command | **error 4** |

A deliberately bogus command name also returns **4**, where spec 0041 recorded
**6** ("Command does not exist") for exactly that case. **So the failure is at
the dispatcher, before the name is looked up** — the command channel is dead
while every read channel is alive.

Ruled out, each by measurement rather than by argument:

- **Not a permission.** `AXIsProcessTrusted()` is `true` for the calling process,
  and AppleEvents to VoiceOver plainly work, since the reads answer.
- **Not the enablement flag.** `SCREnableAppleScript` is still `true`, and
  `/private/var/db/Accessibility/.VoiceOverAppleScriptEnabled` is still present.
- **Not stale state a restart clears.** VoiceOver was restarted and the channel
  came back in the same condition.
- **Not the syntax.** `perform command` takes a direct parameter of type text,
  per the dictionary, which is how it was called.

**Why this matters.** Spec 0046's entry 13.7 puts `pressGesture` — the whole
gesture capability, and with it the 45 toggles that stand in for `setState` —
entirely on `perform command`. Entry 13.11's guidance document is written around
that same vocabulary. If `perform command` is unreliable on Sequoia, the argument
that "the agent loses no power" loses its mechanism.

**It is a known-bad neighbourhood.** Sequoia moved VoiceOver's preferences into
the group container, and there are open reports against
`actions/runner-images` and `guidepup` that VoiceOver AppleScript automation
degrades on Sequoia even with the flag set. What is *new* here is the
separation: **reads survive, dispatch does not**, with a distinct error code.

**It also validates a design decision already taken.** Spec 0046 gives the
bridge a `ReaderLiveness` port precisely so that "the reader answers its own name
but not its own state" is a *detectable, named* condition rather than an empty
answer. This machine is currently in a state that port was designed for — except
that the split runs the other way than expected, so `ReaderLiveness` should
report **which channel** is alive rather than a single boolean.

## Finding 5 — a confound that reads exactly like a dead reader

The first pass of finding 4 reported `missing value` for every object-model read
and nearly recorded "the scripting object model is dead". It was not.

**`activate` brings VoiceOver to the front**, and spec 0046 already measured that
**VoiceOver publishes no accessibility tree of its own**. With VoiceOver itself
frontmost, the VO cursor sits on a process with nothing to read, so every read
returns `missing value` and every cursor command fails. With Finder in front, the
same reads return real text.

**The operational rule, which belongs to any bridge that restarts a reader:**
after restarting VoiceOver, hand focus to a real application before reading
anything. Otherwise the first reads of every session look exactly like a dead
reader, and the bridge would report a named fault that is really its own doing.

This is also a warning about the instrument rather than the subject: the same
session misread a capture-feed tail as fresh evidence when it was five hours old,
and only converting the timestamps caught it. **Both mistakes had the same
shape** — a plausible reading of real data that inverts on one more check.

## Finding 6 — the voice can vanish from VoiceOver's picker, and a restart does not bring it back

**This is the most consequential thing measured, and it explains finding 2.**

While driving VoiceOver Utility to select the voice by hand, its picker was
searched with a control and a test:

| Search | Rows |
|---|---|
| `Reed` (control) | 3 — `Português (Brasil)` → `Eloquence` → **Reed** |
| `Capture` | **0** |

So the capture voice was **absent from VoiceOver's own list**, at the same
moment that `AVSpeechSynthesisVoice.speechVoices()` reported 191 voices with
ours among them, the extension was registered, and its process was **alive**
(pid 777). Every system-wide signal said the voice was fine.

**A reader restart did not repair it.** VoiceOver had been restarted five times
that afternoon before this was noticed. What repaired it was **re-registration**:

```sh
pluginkit -r <old>.appex
lsregister -f <app>          # first, and not sufficient alone (spec 0041, C1)
pluginkit -a <new>.appex
# then restart VoiceOver
```

after which the same search returned three rows —
`Português (Brasil)` → **`screen-readers-mcp`** → **`Capture Spike`**. The
manufacturer string the audio unit declares becomes a **group** in the picker,
which is worth knowing for anyone looking for the voice by eye.

**This corrects spec 0041's C2.** That finding says the voice disappears from
VoiceOver's list after the provider dies and that *"only restarting VoiceOver
restores it"*. The first half is confirmed and the second half is **too weak**:
a restart is necessary and **not sufficient**, and the provider had not died.
The honest statement is that VoiceOver's binding to a provider voice can be lost
for reasons not yet understood, that nothing observable from outside VoiceOver
reveals it, and that re-registration plus a restart is the repair.

**And it explains finding 2 without needing any of its three hypotheses.**
Writing a voice identifier into the preferences did nothing because **VoiceOver
did not have that voice in its catalogue at the time**. The write may well be
sound. Question 1 is therefore not merely open, it is **untested** — the
experiment must be repeated now that the voice is back in the list.

**It is the fourth named condition this lane owes**, and the worst-shaped one:
`ProviderState` (entry 13.6) currently distinguishes `notRegistered` →
`registered` → `published` → `selected` → `capturing`, and this is a state
between `published` and `selected` in which every check the bridge can make from
outside says *published* while VoiceOver disagrees. Detecting it needs the
reader's own list, which AppleScript does not expose — so the honest reporting is
"published system-wide; whether VoiceOver offers it cannot be read", and the
recovery instruction is re-register and restart.

## Finding 7 — press a key, read the phrase back: the bridge's own design, proven

With `perform command` dead (finding 4), VoiceOver was driven **entirely by
synthesized keystrokes with the capture channel as feedback** — which is exactly
what the bridge is designed to do, arrived at because the alternative was broken.

Every one of these works through `System Events`, needing Accessibility:

| Keys | Effect |
|---|---|
| VO-F8 (`key code 100` + control, option) | opens VoiceOver Utility |
| VO-Left / VO-Right (`123`/`124` + control, option) | walk the elements |
| VO-Space (`49` + control, option) | activate |
| VO-Shift-Down / Up | interact with / stop interacting |
| plain typing | goes to the focused field |

and `tell application "VoiceOver" to return content of last phrase` reports what
VoiceOver said about it, every time. That loop navigated a category table, found
the Voz pane, reached the voice button and opened the picker.

**Two things it taught that no document states.** Tab does *not* enter the
settings pane — it cycles toolbar → category table → Help — so a bridge cannot
rely on Tab to reach a control; VoiceOver's own VO-Left/VO-Right is the route.
And **`content of last phrase` is only meaningful when it CHANGES**: five
consecutive VO-Rights that returned the same phrase meant the cursor had not
moved, not that five elements shared a name. A bridge reading this channel needs
that rule, because the failure is silent and looks like data.

## Finding 8 — the accessibility API drives the reader's own settings, with two traps

Where the keyboard loop was slow, `AXUIElement` was deterministic: enumerate
VoiceOver Utility's tree, find the voice button by title, `AXPress` it, read the
picker's rows. This is a working prototype of entry 13.9's `AXAccessibilityTree`
adapter, and it confirms that route on a real window.

**Both traps fail silently, which is why they are recorded:**

- **Setting a search field's `AXValue` does not fire the search.** The field
  showed the new value and the results list did not change, so the list read as
  empty when it was merely stale. Typing works; assignment does not.
- **Setting a row's `AXSelected` does not commit the choice.** The row is marked
  and the dialog's OK button then confirms *nothing*: the voice button still read
  `Reed` afterwards. Selecting and choosing are different operations.

Both were briefly mistaken for real answers about the reader, which is the same
failure this document already records twice.

## Finding 9 — the decomposed extension is loaded by VoiceOver's own path

After re-registering the build from
[PR #82](https://github.com/marlon-sousa/screen-readers-mcp/pull/82) and
restarting the reader, the container file the **new** code writes —
`voiceover-capture.jsonl`, a different name from the spike's — appeared, with:

```
15:55:22  audio-unit-created   cleared_darwin_bg = true   silent = false
15:55:22  speech-voices-read
```

So the system instantiated the decomposed audio unit inside the reader's own
world, the `PRIO_DARWIN_BG` escape still works after the refactor, and the two
sinks still emit. **No `synthesize` events**, because the voice was deliberately
left unselected: whether the refactor still *sounds* right is a judgement only
the maintainer can make by ear, which is the whole reason spec 0041's six fixes
exist.

## Finding 10 — setting the voice by hand writes nothing we can find

**This is the observation the maintainer asked for**, and it is a strong
negative that settles finding 2 completely.

The voice was set to `Capture Spike` through VoiceOver Utility, with the
preferences snapshotted before and after by
`scripts/voiceover_settings.sh`. What changed:

| File | Change |
|---|---|
| `default.plist` | **nothing** — last written 14:48, an hour and a half before the selection |
| `journal.plist` | only timestamps refreshed, on every restart, for settings unrelated to speech |
| `com.apple.VoiceOver4.local.plist` | `AllowAirPlay`, `FKNHotKeySettings`, `PlannedShutdownSuccessful` — all unrelated |
| cfprefsd domain view | unchanged |

Then VoiceOver was **quit** — in case it persists on exit — and snapshotted
again. Still nothing. Then the identifier and the display name were searched for
across `~/Library/Preferences`, `~/Library/Application Support` and
`~/Library/Group Containers`: **no file contains either.** And yet the selection
**survived a full VoiceOver restart**.

So the reader persists its chosen voice somewhere none of this reaches.

**The search was then made exhaustive**, because "I did not find it" is not
"it is not there", and the maintainer said so: *"it has to be somewhere,
otherwise how would it know?"* — which is correct, and the right correction to a
negative result. What was done:

- The voice was changed **twice** through the UI (`Capture Spike` → `Reed` →
  back), with whole-file diffs of `default.plist`, `journal.plist` and
  `local.plist` either side. The only differences in the entire run are
  `SCRSpeechAttributeRotorLastRotor` (this session's own rotor test),
  `AllowAirPlay`, and shutdown bookkeeping. **No voice, under any key name** —
  so this is not a case of having guessed the key wrong.
- VoiceOver was **quit** and the files re-diffed, testing the maintainer's
  hypothesis that a reader flushes settings on shutdown: `default.plist` and
  `journal.plist` show **zero** changes on a clean quit.
- A **filesystem sweep** was taken around a voice change: every file written
  under `~/Library` in that window. `journal.plist` moves; the voice is not in
  it.
- Finally, `grep -r` for **both** the published identifier and the display name
  `Capture Spike` across the **whole of `~/Library`**, plus `/Library/Preferences`
  and `/private/var/db`. **No file contains either string.** VoiceOver Utility
  has no sandbox container of its own.

**So the value is stored in a form that is not the string** — an index, a hash,
or an encoded record — and the plausible home is the CloudKit-backed accessibility
store its own preferences advertise
(`AXCloudKitZoneCreated-com.accessibility.voiceover.*`).

**The consequence is a design one, and it settles a proposal.** The maintainer's
preferred mechanism — *"patch whatever it uses before starting it"* — would be
the safest of all if the store were a readable file: no UI, no timing, nothing to
race. It is not available. Implementing it would mean reverse-engineering an
encoded store and writing into it, which is both more fragile and more invasive
than the AX route that already works. The route stays as finding 13 describes.

**Three consequences.**

1. **The preference-write route is dead**, and with it all three hypotheses under
   finding 2. It is not that we wrote to the wrong door — there is no door of
   that kind. That also means open question 0 does not need running.
2. **Finding 2's failure is fully explained twice over**: VoiceOver did not have
   the voice in its catalogue (finding 6), *and* the key it was written to is not
   where the reader keeps the answer.
3. **`getState`-style reads of the voice are impossible from the filesystem.**
   Anything wanting to know which voice VoiceOver is using must ask the reader's
   own UI, which is finding 11.

## Finding 11 — the accessibility framework can do it, and here is the recipe

The bridge will have to set its own voice, so this is the load-bearing result.
Driving VoiceOver Utility through `AXUIElement` works, end to end, with no
`perform command` and no reliance on the broken command channel:

1. **Open the utility** — VO-F8, `key code 100` with control and option. A fresh
   launch resets to the `Geral` category.
2. **Select the `Voz` category** — set `AXSelected` on its row in the
   `Categorias de Utilitários` table. This *does* work: an `AXTable` row's
   selection is writable.
3. **Press the voice button** (`AXPress` on `AXButton "<voice>, <language>"`).
   That opens the voice **settings** sheet — rate, pitch, volume — which is not
   the picker.
4. **Press the inner button** `AXButton "Voz, <voice>"` inside that sheet. *This*
   opens the picker. Matching on the voice name alone finds the outer button
   first, which is a trap worth naming.
5. **Focus the picker's search field** by setting `AXFocused`, then **type** the
   voice name with synthesized keystrokes.
6. **Click the row** at the centre of its `AXPosition`/`AXSize` frame, with a
   `CGEvent` left click.
7. **Press `OK`** on the settings sheet.

**Three ways it does not work, each failing silently**, and each of which was
briefly mistaken for a fact about the reader:

- **Setting the search field's `AXValue` does not fire the search.** The field
  displays the new text and the list does not re-filter, so it reads as empty
  when it is stale. Only typing works.
- **Setting a row's `AXSelected` in the voice list does nothing.** The write
  returns success and the outline then reports **zero** selected rows. Writing
  `AXSelectedRows` on the outline fails the same way. The voice list is not an
  `AXTable` like the category list; it behaves like a SwiftUI list whose
  selection is not writable through AX.
- **The voice rows expose no `AXPress`.** Their only actions are
  `AXShowDefaultUI` and `AXShowAlternateUI`, so there is nothing to perform.
  Arrow keys do not move into the list either.

**What works is a real mouse click at the element's real frame** — the one
approach that goes through the same path a person does. AX supplies the
coordinates; the click supplies the commit.

## Finding 12 — the decomposed extension, verified live

With the voice selected, VoiceOver spoke through the build from PR #82 and the
feed proves every part of the refactor:

```
synthesize  seq=15  silent=false
   text                  "Você está em um item do tipo tabela, dentro de..."
   utterance_language    <unknown>
   passthrough_language  pt-BR
   passthrough_voice     com.apple.voice.compact.pt-BR.Luciana
cancel  prebuffer_ms=153 cb_count=52 cb_frames=13056 drained_frames=13056
        underruns=0 contention_drops=1 overflow_drops=0
```

33 utterances in one session. Every decomposition claim holds against a live
reader: the `SsmlDocument` plain-text extraction populates `text`; the missing
`xml:lang` is reported as `<unknown>` rather than guessed; `VoiceChoice` falls
back to the **system** language and picks a voice that is **not ours**, which is
the Arabic-reading-Portuguese fix working in production; the `PRIO_DARWIN_BG`
escape reports cleared; and frames produced equal frames drained with no
overflow. The prosody spec 0041 A2 measured is still there —
`<prosody rate="160.00002%">` and `<break time="250ms"/>` — captured intact.

## Finding 13 — the direct accessibility message exists: press the button inside the cell

**This section replaces a wrong conclusion.** An earlier draft of this document
said there was no AX message that could commit the choice, and that a synthesized
click at the element's frame was the only route. That was wrong, and the
maintainer refused it on the right grounds — *"you are saying the Apple
accessibility framework has a bug; it is very hard to believe. If it had such a
flaw, everything depending on it would fail."* It does not have a bug. The probe
was too shallow.

**What is true**, and was measured:

| Element | Reported settable | Actions |
|---|---|---|
| `AXOutline "Lista de Vozes"` | `AXFocused`, `AXSelectedRows` | *(none)* |
| `AXRow` | `AXSelected` | `AXShowDefaultUI`, `AXShowAlternateUI` |
| `AXCell` | `AXScrollToVisible` | *(none)* |
| **`AXButton` inside the cell** | — | **`AXPress`** |

Setting `AXSelected` on a row, or `AXSelectedRows` on the outline, does return
`.success` and then silently does nothing — the row still reads `AXSelected = 0`.
That part of the earlier finding stands, and it is a real trap. But it is not the
only door, and stopping there was the error: **the row's cell contains two
buttons — the voice and its `Falar Amostra` sample — and both expose `AXPress`.**
Pressing the voice button selects the voice, closes the picker, and updates the
parent button's title. No coordinates, no synthesized click.

**Verified as a round trip**, in both directions, with nothing but AX messages:
`Capture Spike` → `Reed` → `Capture Spike`, each confirmed by reading the parent
button's title back.

**The complete mechanism**, which is what entry 13.13 implements:

1. Open VoiceOver Utility — VO-F8, or `open -a`. A fresh launch resets to
   `Geral`.
2. `AXSelected = true` on the `Voz` row of the `Categorias de Utilitários`
   table. This one *does* take: it is a real `AXTable`.
3. `AXPress` the main voice button — that opens the voice **settings** sheet
   (rate, pitch, volume), not the picker.
4. `AXPress` the inner `Voz, <voice>` button in that sheet — *this* opens the
   picker. Matching on the voice name alone finds the outer button first.
5. `AXFocused = true` on the picker's search field, then type the voice name.
   **This step is not optional**: the list is virtualized, so a row that is not
   visible does not exist in the AX tree at all — which is why the target row was
   "not found" among 34 rows until it was filtered to 3.
6. `AXPress` the button **inside the target row's cell** whose label is the voice
   name.
7. `AXPress` `OK` on the settings sheet.

Only step 5 needs a keystroke, and it types into a field that was focused by
message rather than by hoping focus was already there. **Every element in that
list is addressed by filter and unique-match assertion, not by index and not by
its localized name** — see finding 15.

**The lesson worth keeping is about the probe, not the framework.** Two of this
document's earlier wrong turns and this one share a shape: an element was asked
what it could do, the answer was "nothing", and the conclusion drawn was about
*the application* rather than about *how far down the tree the question had been
asked*.

## Finding 14 — the rotor is window-independent, and still not a setter

VoiceOver's speech-attribute guide is the one route that needs **no window at
all**, which is the right property. Its bindings, read from the default
configuration rather than guessed:

| Command | Selector | Keystroke |
|---|---|---|
| open next speech attribute guide | `Global.interactRightCommandShift` | VO-Command-Shift-Right |
| open previous speech attribute guide | `Global.interactLeftCommandShift` | VO-Command-Shift-Left |
| select next option down in guide | `Global.interactDownCommandShift` | VO-Command-Shift-Down |
| select next option up in guide | `Global.interactUpCommandShift` | VO-Command-Shift-Up |

(control + option + command + shift, with the arrow characters `\uf700`–`\uf703`.)

**Measured, and it does not advance.** The first press opened the guide on
`Velocidade 60%`; a later one reached `Tom 40%`; and every press after that
produced exactly `Fechando Menu Tom` → `Tom 40%` → the previous context. It
closes and reopens the guide on the **same** attribute. Eight presses at 0.7 s
and four presses as fast as `osascript` allows behaved identically. The guide is
a **transient, timed** overlay, so driving it means racing a timeout — and the
mechanism is **relative** (cycle) rather than absolute (set to X) in any case.

**A better readback channel, found here and worth keeping.** `content of last
phrase` raced badly during this — it returned a stale context line more often
than the guide's announcement. The **capture feed** did not: every utterance,
in order, with a sequence number, which is how the transcript above was
recovered. The bridge already has the better channel; `last phrase` is the
degraded one.

## Finding 15 — filter and assert; never index, never a localized name

The recipe in finding 13 is correct and, as first written, was still unsafe in
two ways the maintainer named: *"if you can avoid depending on element order, it
will be safer"* and — implicitly, because this machine speaks Portuguese —
depending on `"Voz"` would break on every other locale.

**There is no stable identifier to fall back on, and that was measured rather
than assumed.** `AXIdentifier` on these elements is `_NS:32`, AppKit's
auto-generated view numbering — an index wearing a name, not a developer-set
handle, and not stable across OS versions. `AXPath` is a **bezier drawing path**,
not a locator. So identifier-based addressing is not available here at all.

**What is available is filtering with an asserted unique match**, and it is
enough. Measured across all eleven categories:

| Category | comma-titled buttons | outlines |
|---|---|---|
| Geral, Verbosidade, Navegação, Web, Som, Visuais, Comandos, Atividades, Reconhecimento | 0 | 0 |
| Braille | 0 | 1 |
| **Voz** | **1** | **1** |

So *"the category whose pane contains exactly one comma-titled button and at
least one outline"* selects the speech pane **uniquely, without its name**.
Braille is the near miss the conjunction exists to exclude, and it is why the
predicate is two clauses rather than one. The voice button is then *"the unique
button whose title contains a comma"*, and inside the picker the target is *"the
unique button whose title is the voice's own name"* — a name we choose, so it is
locale-independent by construction.

**The rule this yields, and it is the transferable part:**

1. **Filter over a subtree by role and predicate; never take the *n*th child.**
   Positional paths — `group 2 of scroll area 1 of group 1` — encode a layout
   that Apple may change in any release, and System Events' index-by-class makes
   them read more stable than they are.
2. **Assert exactly one match. Zero or many is an error, never a coin flip.**
   This document's own `axpress` helper took `.first` of its matches, and with
   the settings sheet open *"Reed"* matched both the outer and the inner button
   — it picked one silently. That is the ordering bug the rule exists to prevent,
   and it was in this session's own tooling.
3. **Prefer structure over words.** Roles, counts and containment survive
   translation; `"Voz"`, `"Speech"` and `"Voix"` do not.
4. **Confirm by meaning, not by title.** `AXSheet` exposes `AXDefaultButton` —
   though it is *unpopulated* here, so the honest fallback for the final confirm
   is a Return keystroke, which says "confirm this sheet" without matching the
   word `OK`.

## The conclusion: the bridge can set the voice, by message

Four routes were tried. One works, and it is the one that sends messages rather
than depending on where a window happens to be:

| Route | Verdict |
|---|---|
| Write a preference | **Dead** — the reader keeps the voice in no file (finding 10) |
| Set `AXSelected` on the row | **Dead** — accepted and silently discarded (finding 13) |
| Drive the speech rotor | **Not a setter** — transient, timed, relative (finding 14) |
| **`AXPress` the button inside the row's cell** | **Works**, both directions, no coordinates (finding 13) |

So the bridge does **not** have to fall back to reporting an unfixable
precondition, and it does not have to click at screen positions — the objection
that killed that idea was correct and it no longer applies. `ProviderState`
(13.6) still owes its *detection*, because a voice can be lost from the reader's
picker without anything outside the reader noticing (finding 6), and the
repair — re-register, then restart — is still the instruction. What changes is
that selecting the voice afterwards is something the bridge can do itself.

**It still depends on VoiceOver Utility being drivable**, which is a real
dependency and should be stated rather than hidden: the app must launch, and the
window's category list and sheets must be present. But those are *messages to
named elements*, which fail loudly with a missing element rather than quietly
clicking whatever is at a coordinate — and that is the difference the maintainer
was asking for.

## What this changes

| Claim | Before | After |
|---|---|---|
| Updating the provider needs a reader restart | a manual cost | **true, but scriptable** |
| The user must select the capture voice in VoiceOver Utility | assumed permanent | **unresolved; three untried routes** |
| Activities could carry the voice | unknown | **true, and they inherit** |
| An activity can be selected without a human | assumed possible | **no documented route; blocked by finding 4** |
| `perform command` is the gesture mechanism | assumed sound | **a measured risk** |
| The voice is published, so VoiceOver offers it | assumed equivalent | **false — they can disagree, invisibly** |
| A reader restart restores a lost voice | spec 0041, C2 | **necessary, not sufficient; re-registration is the repair** |
| The preference write does not work | finding 2 | **dead — the reader keeps the voice nowhere we can write** |
| The voice can be set without a human | open | **yes — through the accessibility framework, finding 11** |
| The decomposed extension works live | untested | **verified: 33 utterances, 0 underruns** |
| The bridge can set the voice itself | hoped | **yes — `AXPress` the button inside the row's cell** |
| The rotor position is unsaved like the voice | assumed | **false — `SCRSpeechAttributeRotorLastRotor` IS written; the voice is deliberately elsewhere** |

## What is deliberately not built

- **Guidepup's portable-preferences mechanism**, still refused, but now for a
  precise reason: wrong granularity, not an unsupported mechanism.
- **A keystroke-driven restart.** Finding 1 gives a route needing a narrower
  permission; synthesizing Command-F5 would widen the grant for nothing.
- **Writing an activity into the preferences blind.** The storage shape is user
  data and cannot be read from the system, and inventing it would be exactly the
  guess this document exists to avoid.

## Open questions

0. ~~Repeat finding 2's write experiment.~~ **Answered by finding 10: there is
   nothing to repeat.** The reader does not keep its voice in any file we can
   find, so no write to one can select it. Questions 1 and 2 below fall with it
   and are struck for the same reason.
1. ~~Does the CFPreferences *domain* write work?~~ Moot.
2. ~~Does a key need a `journal.plist` entry?~~ Moot.
2a. **WHERE does VoiceOver keep the selected voice?** It survives a restart and
   is in no file under `~/Library`. Worth knowing only if something ever needs
   to *read* it; the bridge does not, because it sets it.
3. **What killed `perform command`, and is it recoverable at all?** Until this is
   answered, 13.7's mechanism is unproven on this host.
4. **What does an activity look like in storage?** Answerable the moment one
   exists.
5. **Is an app-bound activity the right shape for the add-on-testing use case?**

## Board amendments this spec makes

- **13.13** is new: the follow-up work, carrying questions 1 through 4.
- **13.7** gains the `perform command` risk, since it is the entry that depends
  on it.
- **13.11** keeps both costs in its documentation, but the restart is now
  described as scripted rather than manual.
