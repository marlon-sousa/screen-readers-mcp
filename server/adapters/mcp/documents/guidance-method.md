
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

## Say something to the human, or the room stays silent

In a **silent** session the person at the reader hears nothing at all except what
you deliberately say to them with `announce`. Not the words the reader would have
spoken, not the window that just opened, not the key you pressed — nothing. From
their chair, a stretch of you working is indistinguishable from their computer
having died, and if they are blind they cannot look at the screen to check.

So `connect_reader` tells you whether a human is expected at that machine, in its
`silenceCap` field. **Read it, and act on it:**

- **Where a human is expected**, `announce` before any stretch of work that does
  not drive the reader — before a long analysis, before you go away to think,
  before anything that will take more than a few seconds without a keypress. One
  short sentence saying what you are doing is enough. It costs almost nothing, and
  it is the only thing standing between that person and sitting in silence
  wondering.
- **Where the machine is unattended**, do not spend round trips narrating to an
  empty room.
- **Narration rides along, so it is nearly free.** `press_gesture` and `type_text`
  both take an `announce` string, spoken to the human before they act; you do not
  need a separate `announce` call to say what you are about to do. Each hands it
  back as `announced`, which is your confirmation the announcement was **made**.
  It is never a confirmation that it was **heard**: the reader emits speech
  around five seconds ahead of the audio the person is listening to, so if you
  narrate and act in the same breath you are acting ahead of your own narration,
  and their objection — when it comes — is a reaction to something already
  several seconds old.

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
