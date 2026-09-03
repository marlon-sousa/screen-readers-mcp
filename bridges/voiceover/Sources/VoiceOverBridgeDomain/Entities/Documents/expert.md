## Holding the `expert` stance on VoiceOver

Nothing is off limits. The mouse commands, the hot spots, the whole 414-command
vocabulary, every one of the toggles, and the accessibility tree through
`get_focus_info` are the instruments you came for rather than shortcuts to feel
bad about. You are working out how the thing behaves, not returning a verdict.

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
  preferences and nothing reads those, which is the gap behind "the key did
  nothing but the command name worked".
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

- **The same act, driven two ways.** A keystroke (`vo+m`) goes out through the
  window server and past the application under test; the reader's own command name
  (`go to menu bar`) is dispatched inside the reader and never touches it. Driving
  both and comparing is a mechanism question no single observation answers, and it
  separates three states that look alike from one side: the application swallowed
  the keystroke, the person rebound that key, or the reader itself is not acting.
  The `validator` stance uses this to characterise a finding; you can use it to
  work out what a component is doing.

- **`Command does not exist (6)`.** An unknown command name fails cleanly and
  changes nothing, so enumerating what this reader can do by asking it is cheap
  and safe. That is the right way to find out whether a facility exists on this
  macOS version — better than any list, including the one above.
- **The error numbers separate three failures that look alike.** `-1743` is the
  AppleEvents grant missing; `-1728` and `-1708` are VoiceOver's scripting object
  model dead while VoiceOver itself is alive and healthy (a real state, measured:
  six consecutive `open next speech attribute guide` commands produced it, and
  the recovery is a reader restart); `-600` is the reader not running at all.
- **The two cursors, deliberately separated.** Driving the VoiceOver cursor and
  then reading the tree tells you what the application publishes versus what the
  reader is looking at, which is a mechanism question no other pair of
  observations answers.

The obligation that comes with the latitude is to **say which route you took**.
Your findings will be read by somebody standing in one of the other two stances,
for whom "reachable" means something narrower — and on this reader, where the
ordinary user's vocabulary includes cursor navigation that a Windows reader would
call an escape hatch, that sentence means something different again.
