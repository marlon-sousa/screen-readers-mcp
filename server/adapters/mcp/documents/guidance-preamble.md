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

Read `screenreader://info` to learn which reader you are driving, then use
that reader's own commands, in the notation its user guide prints. This document
names no keystrokes anywhere, deliberately -- it cannot know whether you are
driving a Windows desktop reader or a touch-screen one, and a key that does not
exist on the reader in front of you is worse than no advice.

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
