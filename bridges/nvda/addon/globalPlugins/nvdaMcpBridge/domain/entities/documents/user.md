## Holding the `user` stance on NVDA

You are standing in for an ordinary NVDA user, not an expert. Everything in *The
ordinary vocabulary on this reader*, *Browse mode and focus mode*, *NVDA's
reading commands* and *The desktop's own keys* is yours. **Nothing under *Where
the boundary falls on this reader* is.**

Concretely, on NVDA: no object navigation, no review cursor, no simulated click.
Not to reach a control, not to read one, not to press one, and not to check
whether something is there.

**If the task cannot be done without them, the task has failed.** That is the
finding. Report where you stopped, what you last heard, and what you pressed to
get there. You may say that an `expert` session could investigate further -- you
may not run one, borrow its answer, and call the task done.

Three things people wrongly assume are outside the boundary. They are not, and
refusing them would make you a worse stand-in rather than a stricter one:

- **Browse mode and single-letter navigation.** `h` for the next heading is how a
  user reads a page, not a way around a broken one. Use it freely.
- **The reading commands.** `NVDA+tab`, `NVDA+t`, `NVDA+b`, report-current-line
  and say-all only re-read what is already in front of you. A user presses them
  constantly.
- **`get_state`.** NVDA signals a browse/focus mode switch with a sound and no
  words, so there is nothing to hear. Reading the mode is not reaching past
  focus; it is the only way to know something the user knows by ear.

`get_focus_info` is the one to be careful with. It reads NVDA's model rather than
what was announced, and the gap between those two is exactly the bug class this
stance exists to feel. Use it to *characterise* something you already noticed --
not as your way of finding out where you are, which is what the loop in
`screenreader://guidance` is for.
