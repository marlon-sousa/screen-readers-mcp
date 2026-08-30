# How we found where VoiceOver keeps its selected voice

A method note, written 2026-08-29 immediately after the fact. The **answer** is
[spec 0047](../specs/0047-selecting-the-capture-voice-without-a-human.md),
findings 16–18. This file is about **how it was measured**, because the technique
transfers to the next closed system and the wrong turns are the instructive part.

## The question

A VoiceOver bridge must point the reader at its own capture voice, and put the
user's voice back afterwards. Doing that by driving the settings UI is fragile.
So: *where does VoiceOver store the selected voice, and can we write it?*

It looked easy. It took an evening, and four instruments failed before one
worked.

## What failed, and why each failure was convincing

**1. Searching the obvious place.** VoiceOver's preferences live in a Group
Container (`group.com.apple.VoiceOver/…/com.apple.VoiceOver4/`). Its
`default.plist` was never written all evening — mtime unchanged through a voice
change, a quit, and a restart. `journal.plist` holds timestamps, `local.plist`
holds runtime state. No voice in any of them.

**2. Searching by string.** `grep -r` for the voice identifier and its display
name across `~/Library`, `/Library/Preferences` and `/private/var/db`. Nothing.
A whole-disk sweep of every file written around a change: 23 files, voice in
none.

> **This one was a tooling artifact, and it is the sharpest lesson here.**
> Measured afterwards, on the file that turned out to be the store:
>
> ```
> grep -l  "<identifier>" com.apple.SpeakSelection.plist   ->  no output, exit 1
> grep -al "<identifier>" com.apple.SpeakSelection.plist   ->  MATCHES
> ```
>
> **BSD `grep` silently skips binary files unless you pass `-a`.** The file is an
> Apple binary property list, the identifier was in it as plain bytes the whole
> time, and every `grep -r` we ran declined to say so — reporting absence rather
> than refusing to look. The store was inside the scope of every sweep, all
> evening. **On macOS, `grep -r` is not a search; `grep -ra` is.**

**3. Watching the writes.** `sudo fs_usage -w -f filesys`, first filtered to
VoiceOver, its Utility and `cfprefsd`, then **unfiltered across every process**.
Result: during a voice change VoiceOver performs **seven writes, all to
`/dev/null`.** `cfprefsd` never wrote `default.plist` once. VoiceOver Utility
opened nothing for writing.

**4. Interrogating the holders.** If nothing is written, something is holding it
in memory. We killed all eight `cfprefsd` instances: **zero files changed** — it
had nothing pending. `lsmp` mapped VoiceOver's 964 Mach ports to find a
persistence daemon: `coreaudiod`, `WindowServer`, `appleeventsd`, our own
extension — and no settings daemon at all.

Each of these produced a *confident negative*, and together they produced a
contradiction: the setting survived a full reboot, so it was on disk, and nothing
we could observe had put it there.

## What worked: compare states, not events

Every failed instrument was **event-based** (watch the write) or
**location-based** (search where we guessed). Both can miss — `fs_usage` is blind
to `mmap`ed writes and to any window you were not recording, and a search only
covers the namespaces you thought of.

The instrument that cannot miss compares **states**:

1. Checksum every plausible file — 35,989 of them — with the voice set to **A**.
2. Change the voice to **B**. Checksum again.
3. Change it **back to A**. Checksum again.
4. **The store is whatever satisfies `A == C ≠ B`.**

Nothing about that depends on when the write happened, which syscall made it,
whether it was memory-mapped, or whether the value is binary, hashed or encoded.
A settings file reverts when the setting reverts; Spotlight, CloudKit and the
prediction engine do not. The revert is the signature, and background churn
cannot fake it.

207 files changed content between the two voice states. Removing known churn left
about twenty, and one was `~/Library/Preferences/com.apple.SpeakSelection.plist`
— the **system speech** domain, one namespace away from everything we had
searched, holding `VoiceOverDefaultVoiceSelections` with the voice in plain
sight.

## The lessons worth keeping

- **A confident negative is not a proof.** Four instruments agreed the write did
  not exist. All four were correct about what they measured and wrong about the
  question.
- **Prefer state comparison to event capture** when you do not control the
  writer. Events need you to be watching the right process at the right moment
  through the right syscall; state only needs the value to differ.
- **Make the differential revert.** A single A→B diff yields a long candidate
  list. A→B→A yields one, because reverting in step with a human's choice is a
  signature nothing else produces.
- **Know what your search tool refuses to read.** This is the one that actually
  cost the evening: `grep -r` without `-a` skips binary files, and on macOS
  preferences are binary plists — so an exhaustive-looking search returned a
  confident, wrong negative. A search that cannot read the format it is searching
  reports absence, not failure.
- **Search the namespace that owns the concept, not the one that owns the
  feature.** The voice belongs to the speech subsystem; VoiceOver only consumes
  it. We searched "VoiceOver" for hours — though note this was a *contributing*
  cause, not the decisive one: the file was in scope regardless.
- **When the write appears to do nothing, check the types.** `defaults write`
  with an old-style plist literal makes every value a *string*; VoiceOver
  silently rejects the malformed record, falls back to a default, **and rewrites
  the key**, erasing the evidence. That produced an earlier wrong conclusion in
  spec 0047 that this session had to overturn.
- **Do not trust your ears as an instrument.** Our pass-through re-synthesizes
  with the same system voice a failed provider falls back to, so success and
  failure sound identical. The capture feed is the signal.

## The instruments, versioned

- `scripts/voiceover_settings.sh` — snapshot and compare VoiceOver's own prefs.
- `scripts/voiceover_voice.py` — read and set the voice, preserving plist types.
- The raw traces and inventories from this session are not committed (17 MB of
  `fs_usage`); the two scripts above reproduce the measurement.
