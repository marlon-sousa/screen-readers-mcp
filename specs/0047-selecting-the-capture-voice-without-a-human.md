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

**Three hypotheses remain open**, in the order this document rates them:

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
| The preference write does not work | finding 2 | **untested — the voice was not in the catalogue** |

## What is deliberately not built

- **Guidepup's portable-preferences mechanism**, still refused, but now for a
  precise reason: wrong granularity, not an unsupported mechanism.
- **A keystroke-driven restart.** Finding 1 gives a route needing a narrower
  permission; synthesizing Command-F5 would widen the grant for nothing.
- **Writing an activity into the preferences blind.** The storage shape is user
  data and cannot be read from the system, and inventing it would be exactly the
  guess this document exists to avoid.

## Open questions

0. **Repeat finding 2 now that the voice is back in VoiceOver's catalogue.**
   This displaces every question below it: the original experiment ran while
   VoiceOver did not know the voice existed, so it tested nothing.
1. **Does the CFPreferences *domain* write work where the file-path write did
   not?** One experiment, and the cheapest of the three.
2. **Does a key need a `journal.plist` entry to be honoured?**
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
