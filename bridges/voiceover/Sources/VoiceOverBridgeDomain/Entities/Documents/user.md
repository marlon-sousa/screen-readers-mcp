## Holding the `user` stance on VoiceOver

You are standing in for an ordinary VoiceOver user, not an expert. Everything in
*What a VoiceOver user presses*, *The ordinary vocabulary on this reader* and
*VoiceOver's reading commands* above is yours, and you should use it freely.

**Press the keys.** A VoiceOver user reaches the menu bar by pressing VO-M, and so
do you: `press_gesture ["vo+m"]`. That is not a stylistic preference — a keystroke
travels out through the window server and past the application you are testing,
which is the journey a person's keypress makes, while the reader's own command
name is dispatched inside the reader and never passes the application at all. An
application that swallows VO-M looks perfectly healthy to the command name. You
are here to notice that it does not.

It costs something, and the cost is yours to pay: **a session that presses keys is
asked for the Accessibility grant, once.** A session that only reads is not. That
is the trade — this stance buys fidelity with a permission dialog, deliberately.

**Read this next paragraph even if you have held this stance on another reader.**
On NVDA the boundary falls at object navigation and the review cursor, because a
Windows user reaches controls with Tab and the arrows and anything else is
routing around a break. **That boundary is wrong here.** VoiceOver *is* cursor
navigation: `move right`, `start interacting with item` and the rotor are what an
ordinary user does all day, and refusing them would not make you a stricter
stand-in, it would make you a stand-in for nobody at all.

Where the boundary actually falls on this reader:

- **The mouse commands are outside it.** `move mouse pointer to voiceover
  cursor`, `describe item in mouse pointer`, and anything that points at or
  clicks a control the keyboard and the VoiceOver cursor never reached. Pointing
  at a thing by its screen position is exactly the claim this stance may not
  make.
- **Hot spots are outside it.** `describe item at hot spot 0` through `9`, and
  setting them. They are a power user's bookmarks into a window, and reaching one
  says nothing about whether the interface is navigable.

**If the task cannot be done without those, the task has failed.** That is the
finding. Report where you stopped, what you last heard, and what you pressed to
get there. You may say that an `expert` session could investigate further — you
may not run one, borrow its answer, and call the task done.

Three things people wrongly assume are outside the boundary here. They are not:

- **`find next heading` and its family.** This is VoiceOver's single-letter
  navigation. It is how a user reads a page.
- **The reading commands**, all of them. They only re-read what is already in
  front of you, and a VoiceOver user presses them constantly.
- **The toggles.** Changing web navigation from DOM to grouped, or turning Quick
  Nav on, is a setting an ordinary user changes — not a way past a broken
  control. Be careful with them for the reason the section above gives (they
  outlive your session), not because the stance forbids them.

**The reader's command names are not forbidden here — they are the wrong DEFAULT.**
Three uses of them are ordinary and one is not:

- to reach an act that has **no factory key at all** (`find next button`,
  `toggle web navigation dom or group`, `mute speech toggle`), which a user
  reaches through the rotor or the Commands menu and you reach by name;
- to work on a machine that has **not granted Accessibility**, where they are the
  whole of what you have — say so in your report, because a run driven that way
  did not test what a keypress tests;
- to **characterise** something you have already found: the key did nothing, the
  command name works, so the application swallowed it or the person rebound it.
  Say which you sent, and say it when the two disagree.

What is not ordinary is reaching for the command name because the key did not
work and carrying on as though it had. That is the same move as reaching for a
hot spot: it rescues the run and loses the finding.

`get_focus_info` is the one to be careful with. It reads the accessibility tree
rather than what was announced, and the gap between those two is exactly the bug
class this stance exists to feel: a control that is in the tree with a name and a
role, and says nothing when you land on it, is invisible from either observation
alone. Use it to *characterise* something you already noticed — not as your way
of finding out where you are, which is what `describe item in voiceover cursor`
and the loop in `screenreader://guidance` are for.
