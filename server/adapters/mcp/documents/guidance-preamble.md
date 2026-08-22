# Driving a screen reader through this server

## What a screen reader is

A screen reader is the program a blind person operates their computer with. It
watches what has focus and speaks it, and it turns the keyboard (or, on a touch
device, gestures) into the whole of the user interface: there is no pointer, and
nothing is reached by looking at it. Everything is reached by moving focus and
listening to what comes back.

That has one consequence worth stating before anything else. **A control that
exists, and is correctly exposed to the platform's accessibility API, and is
announced as nothing at all, is invisible to the person at the machine.** It
passes every check made by reading the accessibility tree, and it fails the only
check that matters. This is why you drive by pressing keys and listening rather
than by inspecting internals: the two disagree in exactly the cases you are here
to find.

## How this server is meant to be used

You send input to the reader and read back what it said. You do not inspect the
application, and this server has no view of it: everything you learn, you learn
the way the user learns it.

`screenreader://tools` is the complete list of what you can call: every tool,
the capability that gates it, its parameters and the shape of what it returns.
Read it rather than guessing, or waiting to find out which tools your client
shows you -- it is readable now, before you connect, and it never changes.

Read `screenreader://info` to learn which reader you are driving, then use
that reader's own commands, in the notation its user guide prints. This document
names no keystrokes anywhere, deliberately -- it cannot know whether you are
driving a Windows desktop reader or a touch-screen one, and a key that does not
exist on the reader in front of you is worse than no advice.

## How you are capturing: choose silent unless you can say why not

`connect_reader` takes a `mode`, and like the stance it is fixed for the whole
session. **Prefer `silent`. Treat `live` as the exception, and one you can name a
reason for.**

In `silent` the reader's speech is captured for you and the person at the machine
hears none of it. In `live` the reader speaks normally and you observe what it was
asked to say. **Capture is complete either way** -- neither mode gives you more of
what was said, and an interrupted announcement is captured whole in both, because
capture happens when the reader decides to speak rather than when the sound
finishes. So the choice is not about how much you learn. It is about two other
things.

**What the human is subjected to.** A live run means everything you do is spoken
aloud at somebody's machine, at talking speed, for as long as you work. That is
their computer, and you are occupying it.

**How fast the reader can answer you.** In a live session speech is paced by
audio: an announcement, or a command that reads a document aloud, takes as long to
produce as it takes to say. A silent session has no sound to wait for, so the same
reading can arrive far faster -- fast enough that a wait which was comfortable in
one mode is much too long in the other. **Never carry a delay you tuned in one
mode into the other without checking it.** How much faster is the reader's own
business; `screenreader://reader-guidance` is where that reader says what silent
costs and gains there.

So `live` is for one situation: **a human needs to hear this run as it happens** --
they are following along, or how something *sounds* is itself what you are
testing. Everything else is `silent`.

Two consequences worth carrying with you.

**The text you match on can differ between the modes.** One mode may hand you the
words as the reader assembled them and the other as it will pronounce them, with
punctuation and symbols expanded into words. So **match on words, not on
punctuation**, and do not assume a trigger string tuned in one mode fires in the
other.

**Silent puts an obligation on you, and it is not optional.** The person at the
machine is now hearing nothing at all -- not the reader, not the keys you send,
nothing -- and if they are blind they cannot glance at the screen to check whether
anything is happening. Whether you owe them narration depends on whether anyone is
there at all, and `connect_reader` answers that in its `silenceCap` field. It is a
sentence rather than a flag, and it gives **three** answers, not two: that a human
is expected at this machine, that the machine is unattended, or that the reader did
not say. **The third is not a licence to guess** -- it means you are talking to a
reader that cannot declare it, and the sentence itself tells you what to do, which
is to narrate anyway. Silence costs a present human a great deal and costs an empty
room a round trip, so the uncertain case resolves towards speaking.

**Read it, and act on it** -- *Say something to the human* below is that rule in
full, and it is the price of the mode you should almost always be choosing.

## Who you are connecting as

Before you connect you must say **what you are standing in for**, because it
decides what your findings mean. The same observation -- *"I reached that
control"* -- is a pass from one stance and a finding from another, and afterwards
nobody can tell which claim you were making unless you said so first.

Choose with `connect_reader`'s `persona` argument. It is fixed for the whole
session: a stance cannot be applied to a run that already happened.

If a human started you and the choice is not obvious from your task, then
**ask them before you connect**. This is the one decision that cannot be
revisited later, and `ask_user` needs a live session -- so by the time you
could ask through this server, the choice has already been made.

One rule spans all three, and it is the one to hold on to:

> **The ordinary user's vocabulary is whatever the platform's own accessibility
> contract assumes of an ordinary user of that platform.** Within it, a command
> that re-reads what is already there is available to everyone; a command that
> *reaches what focus cannot* -- object navigation, a review cursor, a simulated
> click -- is not available to the `user` and `validator` stances at all.

Which of *your* reader's commands fall on which side of that line is your
reader's own to say, not this document's. Once connected, read
`screenreader://reader-guidance`: that is the connected reader's own account of
your stance, and the only place the actual commands are named. If the reader
publishes none, that resource says so and this rule still stands.
