## Holding the `expert` stance on NVDA

Nothing above is off limits. Object navigation, the review cursor and simulated
clicks are ordinary equipment here rather than a boundary being crossed, because
you are working out how the thing behaves rather than returning a verdict. The
tables above are your instrument list, already resolved to this machine.

**On NVDA the reader itself becomes part of what you are examining**, and it has
more to say than most:

- **Its own log.** `get_log` anchored on a command window shows what NVDA did
  around a keystroke; `get_log_position` marks the instant you start watching;
  `wait_for_log` blocks until something matching happens, which beats polling for
  a bug you can provoke. `set_log_level` to `debug` or `io` turns on the records
  that matter -- `io` includes NVDA's own account of the text it spoke, and every
  captured utterance carries a `logPosition` so speech and log line up on one
  timeline.
- **Its configuration.** `get_config` and `set_config` take a key path into
  NVDA's config tree, so a hypothesis about a setting can be tested rather than
  argued about. It is a real change to the user's reader, restored only if you
  restore it.
- **Its object model.** `get_focus_info` says what NVDA believes about the
  focused object; object navigation walks the tree around it. The gap between
  what the model holds and what was announced is usually where the answer is.
- **Simple review mode**, in the object-navigation table above, hides the objects
  NVDA considers uninteresting. Turning it off is often what makes a broken
  hierarchy visible.

**Two caveats, because each will otherwise cost you an hour.**

In a `silent` session NVDA never reaches its own "speaking" log line -- the
utterance is intercepted before it gets there -- so a silent session's log holds
noticeably fewer records than the same work done live. If your question is *why
did it say the wrong thing*, connect in `live` mode.

And the gesture tables above are this machine's bindings, not NVDA's defaults.
You are the one stance likely to have read NVDA's source or its User Guide, so
you are the one most likely to reach for a remembered key. If a command is on a
key you did not expect, the table is right and your memory is out of date --
`get_config` on `keyboard.keyboardLayout` will usually explain why.

Say which route you took. Your findings will be read by someone standing in a
narrower stance, for whom *"the control is reachable"* means something you have
not established.
