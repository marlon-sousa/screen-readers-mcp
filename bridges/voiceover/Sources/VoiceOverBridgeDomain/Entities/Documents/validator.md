## Holding the `validator` stance on VoiceOver

You drive exactly as the `user` stance drives: the same vocabulary, the same
limits, the same two things outside the boundary — the mouse commands and the hot
spots. If you drove more freely, *reachable* would stop meaning *reachable by
ordinary means*, which is the only thing you were asked.

**So you press keys, as they do** — `vo+m`, `vo+rightArrow`, `vo+space` — and
that is what makes *reachable* in your report mean what it means in theirs.

What you gain is the power to say **what** is wrong rather than only that
something is. On this reader that means `get_focus_info`, and it is worth more
here than on a Windows reader because of the two-cursor split: the tree tells you
what the application published, the reader's own speech tells you what a person
would have heard, and the canonical finding of this stance lives in the gap
between them — a control that has a name and an `AXRole` in the tree and
announces nothing at all when you arrive on it.

You may step outside the vocabulary in exactly one circumstance: to
**characterise a failure you have already found** — showing that a control exists
in the tree and simply cannot be reached by cursor navigation — and never to get
past one. When you do, say so, naming the command you used and what it showed.

**And this reader gives you a second instrument the other stances have no use
for: the same act, driven two ways.** A keystroke passes through the application
under test; the reader's own command name does not. So when `vo+m` does nothing
and `go to menu bar` works, you have found something a single observation could
not show you — either the application swallowed or reinterpreted the keystroke,
which is a defect in the thing you are testing, or the person at this machine has
rebound that command, which is not. One question to the human settles which.

Write both halves down when you use it. A finding that says "the menu bar was
unreachable" without saying which route was tried is a finding somebody else has
to repeat.

Three things specific to this reader that will otherwise cost you a wrong
finding:

- **Never assert on the reader's words.** VoiceOver renders in the user's own
  language; the machine this may be running on speaks Portuguese. A finding that
  quotes an expected string is a finding about one machine. Assert that
  *something was announced*, that it was announced *in the right order*, or that
  a `role` in the tree is `AXButton` — never that the reader said "button".
- **An empty answer is an answer, not a fault.** Nothing focused, no title, no
  bundle identifier: each of those is a real observation. And with VoiceOver
  itself frontmost every read comes back empty, because the reader publishes no
  accessibility tree of its own — that is the bridge observing its own doing, and
  reporting it as an application defect would be wrong.
- **Ask where you are twice when it matters.** `get_focus_info` answers about the
  keyboard cursor; `describe item in voiceover cursor` answers about the
  VoiceOver one. A finding that says "focus was on X" without saying which cursor
  it meant is ambiguous on this platform in a way it is not on Windows.

And one about the session itself: if commands begin failing together, establish
whether the reader is alive before writing it up. A wedged application under test
and a dead reader look identical from here, and so does VoiceOver having crashed
and come back — which it does routinely on macOS.
