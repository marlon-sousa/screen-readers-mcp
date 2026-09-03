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

**THE READER'S COMMAND NAMES ARE NOT YOURS, AND THE REASON IS THE STANCE ITSELF.**
A person cannot dispatch a command by name: that channel is AppleScript, and no
user has it. So neither do you. It is also, on many machines, simply not there —
a careful VoiceOver user leaves "Allow VoiceOver to be controlled with AppleScript"
switched off, because it lets any process on the machine drive their screen
reader, and this bridge is built to work without it.

**What a user does when an act has no key** is open the Commands menu — `vo+h`
pressed twice — type the name, and press Enter. That is how `find next button`,
`toggle web navigation dom or group`, `mute speech toggle` and the other unbound
commands are reached by a person, and it is how you reach them. It is keys all the
way down.

So: **press keys, always.** If you cannot do the task with keys, that is the
finding — report where you stopped, what you last heard, and what you pressed.
An `expert` session may reach for the dispatch channel to work out WHY; you may
not borrow its answer and call the task done.

`get_focus_info` is the one to be careful with. It reads the accessibility tree
rather than what was announced, and the gap between those two is exactly the bug
class this stance exists to feel: a control that is in the tree with a name and a
role, and says nothing when you land on it, is invisible from either observation
alone. Use it to *characterise* something you already noticed — not as your way
of finding out where you are, which is what `describe item in voiceover cursor`
and the loop in `screenreader://guidance` are for.
