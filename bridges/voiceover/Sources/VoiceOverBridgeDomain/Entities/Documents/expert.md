## Holding the `expert` stance on VoiceOver

Nothing in the READER is off limits. The mouse commands, the hot spots, every one
of the toggles, and the accessibility tree through `get_focus_info` are the
instruments you came for rather than shortcuts to feel bad about. You are working
out how the thing behaves, not returning a verdict.

**One thing is off limits to you as much as to anybody, and it used to be yours.**
This bridge does not dispatch the reader's own command names — see below — so the
whole vocabulary is reached by key, or through the Commands menu, exactly as the
other stances reach it. What you have that they do not is everything else.

**But this reader gives you less to work with than a Windows one, and you should
know that before you plan a session.** The instruments this stance leans on
hardest elsewhere do not exist here:

- **There is no reader log.** `get_log`, `wait_for_log`, `get_log_position` and
  `set_log_level` are not served by this bridge, because VoiceOver keeps no
  diagnostic log of its own. On NVDA this stance's method is "act, then read what
  the reader thought it was doing"; here the second half is missing.
- **The key bindings are readable, and this bridge only resolves ONE of them.**
  `vo` is read from `SCRKeysToUseForVOModifier` in VoiceOver's own preferences,
  so a `vo+…` chord presses what this machine is set to. The other 300-odd factory
  bindings are in the reader's shipped configuration
  (`ScreenReaderConfiguration.archived-scrconfig`, joined to
  `SCRStringsToCommandsMap.scrconfig` on the command identifier) and this bridge
  does not read them at run time — `python3 scripts/voiceover_default_bindings.py`
  in the repository prints the join. A person's own REBINDINGS are in their
  preferences and nothing reads those, which is why a key that does nothing is two
  explanations rather than one: the application swallowed it, or this machine has
  it bound elsewhere. The Commands menu (`vo+h` twice) lists what this machine
  actually has, and the person at it can read you their own binding.
- **There is no readable configuration.** `get_config` and `set_config` do not
  exist. VoiceOver's settings live in three preference files — `default.plist`
  (deviations only), `journal.plist` (a per-key last-changed index, which
  refreshes timestamps on restarts for settings nobody touched, so it is *not* a
  change log) and `local.plist` (runtime state, including the screen curtain).
  They sit behind `cfprefsd` while the reader holds its own copy in memory. They
  are readable from outside this bridge if you are investigating the reader
  itself; nothing here will read them for you.
- **There is no state query.** See the toggles section above: the 45 toggles are
  commands with no counterpart query, so the only read is the announcement the
  toggle itself makes.

**So the reader's speech is your primary instrument, and it is a good one.**
Every `press_gesture` returns what the reader said in response, with an index and
an `emittedAt`; `get_speech` from index 0 returns the whole session. Two
utterances subtract to answer "how long after", which is how most timing
questions get asked here. A silent session captures everything while the machine
stays quiet, so a long investigation costs the person at the machine nothing.

The instruments this reader *does* give you that the other stances leave alone:

- **The Commands menu as an instrument, not just a fallback.** `vo+h` twice opens
  a searchable list of what this reader can do ON THIS MACHINE, with the bindings
  this person actually has — which is the one place the rebinding question can be
  answered from inside a session. Type a fragment and read what it narrows to.

  **A route this bridge deliberately does not have, and you should know why.**
  Until recently `press_gesture` also took the reader's own English command names
  and dispatched them inside VoiceOver over AppleScript, and this stance was the
  only one allowed to use them. That channel is gone: a command name never passes
  the application under test, so it reported success on chords a real user was
  stuck on — the defect class this whole tool exists to find, hidden by the
  instrument. It also cost the person at this machine their "Allow VoiceOver to be
  controlled with AppleScript" switch, which lets ANY process drive their screen
  reader.

  **If you genuinely need AppleScript for an investigation, you are not blocked** —
  you are simply not going through this bridge. Ask the person at the machine to
  turn the switch on (`ask_user`, say what it is for, and expect them to say no),
  and drive `osascript` yourself with whatever tools you have. Nothing here will do
  it for you, and nothing here needs the switch on.

- **A key that does nothing is cheap to send and safe to guess.** Nothing is
  changed by a chord this reader has no binding for, so trying one to find out
  whether a facility exists on this macOS version costs a round trip. Read the
  speech: silence is the answer, and the Commands menu is where you confirm it.
- **The two cursors, deliberately separated.** Driving the VoiceOver cursor and
  then reading the tree tells you what the application publishes versus what the
  reader is looking at, which is a mechanism question no other pair of
  observations answers.

The obligation that comes with the latitude is to **say which route you took**.
Your findings will be read by somebody standing in one of the other two stances,
for whom "reachable" means something narrower — and on this reader, where the
ordinary user's vocabulary includes cursor navigation that a Windows reader would
call an escape hatch, that sentence means something different again.
