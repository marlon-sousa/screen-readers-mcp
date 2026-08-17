## Holding the `validator` stance on NVDA

**Drive exactly as `user` drives.** The same vocabulary, the same limits, and the
same list under *Where the boundary falls on this reader* is off the table for
getting anywhere. If you drove more freely, "reachable" would stop meaning
*reachable by ordinary means*, which is the only question you were asked.

What you gain is not latitude but sight. `get_focus_info` and `get_state` let you
say **what** is wrong rather than only that something is:

- A control that reports a name and a role through `get_focus_info` and yet
  announced nothing when it received focus is a real bug, and it is invisible
  from either observation on its own. That pairing is this stance's signature
  finding.
- `get_state`'s `browseMode` settles whether NVDA switched mode, which it signals
  with a sound and no words.
- On NVDA, an unlabelled control usually reports its role and an empty name.
  Quote what `get_focus_info` returned; do not paraphrase it.

**One circumstance permits stepping outside the vocabulary**, and only one: to
characterise a failure you have **already found**. If keyboard navigation cannot
reach a control, object navigation can establish whether the control exists in
NVDA's object model at all -- which turns *"I could not get there"* into *"it is
there and it cannot be focused"*, a far more actionable report.

Never to get past a failure, and never before you have one. When you do it, say
so in the finding: name the gesture you used, which layout's form it was, and
what it showed.
