
## A successful result means delivery, plus whatever arrived in time

`press_gesture` and `type_text` return once the reader has **accepted** the
input and a short grace window has elapsed. Whatever the reader said inside that
window is in your result; whatever it does afterwards, on its own thread, is not.

So the result is evidence of two different strengths, and they are worth keeping
apart:

- **The speech it carries really was said.** That is an observation, and it is
  usually enough — a window that opens announces its title.
- **An empty list is not evidence of anything happening or not happening.** It
  says only that nothing had arrived by that instant.

Two corollaries worth stating:

- `type_text`'s `typed` count is the length of what was **sent** — the reader's
  own count of what it received. It says nothing about what arrived in the
  control, only about what reached the reader.
- Do not re-press a gesture because the result "seemed" not to work. It very
  likely did work, and you are about to do it twice.

## First, get the application in front of you

Everything below assumes the application you are testing is the one receiving
keys. Nothing here puts it there. Focusing an application is the desktop's job,
not the screen reader's, so no reader command will do it for you and this server
publishes no tool for it — which is correct scoping, and also the first thing you
need.

Two things about *this* interface shape how you do it, and they are the parts you
cannot work out from what you already know about the desktop.

**A gesture is a discrete press and release.** `press_gesture` sends each gesture
whole, so no modifier can be held down across several other keys. The ordinary
hold-a-modifier-and-tap-repeatedly way of walking a window switcher is therefore
**not expressible here at all**: every press releases, and a switcher that lives
only as long as its modifier is held starts over each time. The limit is general,
not a window-switching quirk — anything meaning "hold this down while pressing
that several times" is outside what a gesture can say.

**So choose a route made of separate presses.** Either name the application
rather than cycle to it — open the desktop's launcher or search, type the name
with `type_text`, press Enter; three ordinary calls, independent of how many
windows are open, and layout-independent, which makes it the one to prefer — or
use a switcher that *stays up after its keys are released*, which can then be
moved through one gesture at a time and committed with Enter.

Your desktop's keys for either route are yours to supply, exactly as your
reader's are — and for a sharper reason. This document is **static**: it is
readable before you connect, so it cannot know which reader you are driving, and
the reader is what fixes the platform. Read `screenreader://info` to learn which
reader is connected; that tells you the desktop as well.

What a *particular* reader can and cannot do for you here is the reader's own to
say, not this document's — readers differ in what they offer, not merely in which
keys they use for it, so do not assume a facility exists just because another
reader has one. If you cannot establish where you are by the loop below, say so
with `ask_user` rather than guessing at a command that may not exist.

The window title comes back in the same call that pressed the key, exactly as in
the loop below — that is your confirmation that you arrived, and the reader volunteers it without being
asked. **Confirm by listening rather than by counting presses**, and do not
assume how a switcher is ordered. An agent that assumes it is in the right window
types into whatever was already focused, and that surfaces later as an unrelated
failure naming the wrong component — see *Before you type, know where you are*
below.

If the application is not running at all, start it with whatever tooling you have
outside this server. That is setup rather than testing, and it is the one part of
driving a screen reader this server deliberately leaves alone.

## The loop: act and read, orient, escalate

**1. Act, and read what it said — in one call.** `press_gesture` or `type_text`
waits a short grace after each key and returns the speech that arrived, so
acting and listening are the *same* call. Speech is the one thing a reader
produces for everything it does, which is why it is the channel you key on.

A window that opens announces its title -- that is your confirmation that you
are where you meant to be, and the reader volunteers it without being asked. If
you hear the wrong title, you are somewhere else: the gesture may be remapped on
this machine, or the application may have opened something you did not expect.

In a batch, each key reports its own `speechFrom`/`speechTo`, so you can see
*which* key spoke. An empty span for a key is a real answer: that key said
nothing.

**2. If the result was quiet, read again — do not re-press.** An empty `speech`
list means **nothing had arrived by that instant**. It does not mean nothing
happened. Slow effects — a browser window opening, a page loading, a dialog
appearing — take longer than any grace worth paying, and they are exactly the
cases where re-pressing does damage: the key lands twice. Read on from
`speechTo` with `get_speech`, or name what you expect with `wait_for_speech`.

**Never sleep instead.** The distinction is not the waiting, it is what you do
with it: *a blind wait you treat as evidence is forbidden; a bounded wait
followed by an honest observation is the mechanism.* The grace window is the
second kind — it waits, then reports exactly what it saw and claims nothing
beyond it. A sleep followed by an assumption is the first.

`wait_for_speech_to_finish` is **not** the step after every action. It asks "has
speech *stopped*?", which cannot be answered at the moment it is asked: silence
before speech starts and silence after it ends are the same observable. Keep it
for a long deliberate announcement or a say-all, where "is it still going?" is
genuinely the question.

**3. Orient**, if what you heard was not enough. Press the reader's own
"report the focused object" command and listen to the answer. Its report-title
and read-whole-window commands are there for the same reason. This is ordinary
screen reader operating knowledge -- asking the reader where you are is a
*command you send*, and its answer comes back in that same call, like any other
key's.

**4. Escalate.** Try what a user would try next -- Tab, Escape -- and notice
when it produces nothing, which is itself information. If you still cannot tell
where you are, call `ask_user` and ask the human at the machine. Do not guess,
and do not proceed with an action whose target you are unsure of.

## When you already know the next few steps, send them together

The loop above is one intention at a time, and that is right whenever what you
do next depends on what you just heard. Often it does not: typing a value and
submitting it, opening something and reading where you landed, starting
something and interrupting it while it is still running. Those are steps you
knew before you sent the first one, and `run_sequence` carries them in a single
call.

**What that buys is not speed, it is reach.** Between two of your calls, seconds
pass — that is your own turn time, not the reader's, and nothing here can shorten
it. Between two steps of a plan, a fraction of a millisecond passes. So a plan
can do something you simply cannot do across separate calls: act on a moment
that has already gone by the time you could have taken another turn. Interrupting
a command that finishes in a second and a half is the standing example.

Three things to hold on to:

- **A plan is a bet placed before the first keystroke.** Its steps cannot react
  to what the reader says, except by stopping. If the second thing you do depends
  on what you heard from the first, that is two calls and should be.
- **It comes back as one window with a bookmark per step**, so you can still see
  which step spoke and which was silent — batching does not cost you the
  observation, which is the whole reason it is worth doing.
- **`outcome` has three values, and the middle one is not a failure.** A
  `wait_for_speech` step whose text never arrived answers `trigger_not_found`:
  the plan stopped, nothing broke, and your next move is different from the one a
  real failure calls for.

The same rules apply inside a plan as outside it. `delay` is the application's
known timing and `settle` is the reader's unknown latency; neither is evidence of
anything on its own, and a plan that only sleeps is the failure this document
opened by warning about, produced faster.

**A plan that interrupts must size its wait to the capture mode.** This is the
one place the mode you chose changes what a plan does rather than what the human
hears. The point of interrupting is to act while the reader is still going, so
the wait before the interrupting step has to be shorter than the thing you are
interrupting — and in a silent session there is no audio pacing that thing, so it
can be over in a fraction of the time the same reading takes aloud. A wait that
lands mid-sentence in one mode can land after the end in the other, and when it
does **nothing fails**: the plan reports `completed`, the interrupting step
returns normally, and you are looking at a result that proves nothing. If a plan
of yours depends on interrupting, read the merged window and check the
interruption actually cut something short, rather than trusting that the plan ran.

## Say something to the human, or the room stays silent

In a **silent** session the person at the reader hears nothing at all except what
you deliberately say to them with `announce`. Not the words the reader would have
spoken, not the window that just opened, not the key you pressed — nothing. From
their chair, a stretch of you working is indistinguishable from their computer
having died, and if they are blind they cannot look at the screen to check.

So `connect_reader` tells you whether a human is expected at that machine, in its
`silenceCap` field. **Read it, and act on it:**

- **Silent, and a human is expected.** This is where `announce` earns its keep and
  where it is close to an obligation. Say something before any stretch of work
  that does not drive the reader — before a long analysis, before you go away to
  think, before anything that will take more than a few seconds without a
  keypress. One short sentence is enough. It costs almost nothing, and it is the
  only thing standing between that person and sitting in silence wondering.
- **Unattended, in either mode.** Do not narrate to an empty room. Every
  announcement is a round trip spent telling nobody anything, and an unattended
  machine that you are talking to should also make you ask why you are not in
  `silent`.
- **The reader did not say.** `silenceCap` has a third answer, given by a reader
  that cannot declare whether anyone is there. **Treat it as attended and
  narrate.** The two mistakes are not the same size: narrating to an empty room
  wastes a round trip, and staying quiet at an occupied one leaves somebody
  unable to tell whether their computer is still alive.

**And the case that is easiest to get wrong, because the reflex points the wrong
way: a LIVE session with a human at the machine.** They can already hear
everything — every window title, every keystroke's answer, the reader's own
account of what you just did. Narrating that back to them tells them nothing they
did not just hear, and it does not merely waste a round trip: an announcement
speaks, so it **competes with the speech they were listening to**. Announcing each
step of a live run is talking over the very thing they are trying to follow.

So in a live session, announce only what **the reader itself will not tell them**:

- that you are about to go quiet — a stretch with no keystrokes is silence in
  live mode too, and silence is what worries somebody;
- that you are about to do something disruptive, or something they might want to
  stop before it happens;
- that you have finished, or hit something you cannot get past.

If they asked to follow along, or how something *sounds* is what you are testing,
say so at the start and then let the reader do the talking.

**Narration rides along, so when it is warranted it is nearly free.**
`press_gesture`, `type_text` and `run_sequence` all take an `announce` string,
spoken to the human before they act; you do not need a separate `announce` call to
say what you are about to do. Each hands it back as `announced`, which is your
confirmation the announcement was **made**. It is never a confirmation that it was
**heard**: the reader emits speech around five seconds ahead of the audio the
person is listening to, so if you narrate and act in the same breath you are
acting ahead of your own narration, and their objection — when it comes — is a
reaction to something already several seconds old.

A reader may enforce this rather than trusting you to remember: `silenceCap` says
whether it does, and after how long. If you meet it, the reader warns its human and
then restores their speech — you lose nothing, because your capture is unaffected
and `get_speech` still returns everything, but you have stopped being the only
thing they can hear. An agent that narrates never meets it at all.

`status` reports `suppressing`, which is whether the reader is withholding speech
right now, if you want to know where you stand.

## Not every action moves focus

Most reader commands do not: report title, read the current line, read the whole
window, say-all, toggle a setting. The absence of a focus change is not evidence
that nothing happened, and its presence is not the signal to key your waiting
on. Key your waiting on speech.

## Before you type, know where you are

Text goes to whatever currently holds focus. If the window you believe is open
is not, your text lands in a document, a search field, or a chat you did not
mean to touch.

And a field that is open is not necessarily empty. Some windows keep their
contents between openings, so what you type is appended to what was already
there -- which can turn valid input into nonsense without any error you can see.
Read back what the reader says about the line before committing to it.

## When the reader says nothing

Some actions are silent, and some answer with a sound rather than words -- a
mode toggle may signal with an earcon that no speech assertion will ever match.
Then your window closes on silence, and you cannot separate "nothing happened"
from "something happened quietly" -- which is exactly why `state` rides on the
result: a browse/focus toggle shows up there even when nothing was said.

That is the moment to introspect: `get_state` answers questions about modes
that are signalled by sound, and `get_focus_info` answers when the ear has
nothing to work with. Reach for them here, not as your default way of finding
out where you are.

## To arrive at a mode, say where you want to be

A mode key is usually a **toggle**, and a toggle is a coin flip whenever
something else might have moved the mode first -- a page that finished loading
can put you in browse mode before your keystroke arrives, and then your
keystroke takes you out of it. The re-check that catches this catches it one
call too late, after the keys that followed have already gone somewhere else.

So: **to arrive at a mode, use `set_state`; to test the toggle itself, press the
gesture.** `set_state` compares inside the reader, so there is no window between
reading and pressing. Asking for the mode you are already in does nothing at all
-- no sound, no announcement -- which means you can state a precondition on every
step without making the human at the reader listen to a tone each time. The
result tells you the state afterwards and whether this call moved anything, so
you never need to look again.

If the focus is not a browsable document, `set_state` says exactly that. That is
about the reader, not about the application you are testing.

## Introspection is for a different job — and this part depends on your stance

`get_focus_info`, `get_state` and `get_config` read the reader's own model
directly. They are good for two things:

- **asserting** in a test what a control reports about itself -- for instance
  that a control claims a name and a role *and* that the reader announced
  nothing when it received focus, which is a bug you cannot see from either
  observation alone;
- **surveying** an application you are about to build for.

For `user` and `validator` they are **not** how you find out where you are: use
the loop above for that, because the loop is what the person you are standing in
for actually has. For `validator` the first bullet is the whole point -- stating
precisely what is wrong is what that stance owes.

For `expert` this section does not apply. The reader is part of what you are
examining rather than the instrument you examine through, so its model, its
configuration and its log are legitimate first resorts.

## In short

Act and read what was said, in one call. If that does not tell you
where you are, ask the reader with its own command and listen again. If that
still does not, ask the human. Introspect on purpose, not by reflex, and never
sleep.
