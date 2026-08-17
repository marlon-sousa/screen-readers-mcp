// screenreader-mcp adapters -- the screenreader://guidance resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. Serves `screenreader://guidance`: what a screen reader is, how
// this MCP is meant to be used, and what the personas are.
// BUILT BY: sdk_server.go's Bind, beside the info and session-record resources.
// DEPENDS ON: entities.AllPersonas, for the profiles. Nothing else -- see below.
//
// Spec 0023, amended by spec 0029, which added the persona profiles and the
// opening section. THE PROFILES ARE COMPOSED FROM THE DOMAIN rather than written
// into the text below: a persona therefore cannot be added without one, and the
// stance an agent is handed at connect_reader cannot drift from the profile it
// read here, because both come from entities.Persona.
//
// 0029 also considered giving each persona its own static resource, and withdrew
// it: a server-owned document holding a persona's VOCABULARY can only be written
// for one platform, and TalkBack has neither the keyboard nor the operating
// system such a document would assume. So this file states the RULE and the
// bridge's own document (board entry 11.20) enumerates the instances -- which is
// why nothing here names a keystroke, and nothing here ever should.
//
// The other two resources describe a session; this one describes a METHOD, so it
// is deliberately different in two ways:
//
//   - STATIC, therefore readable BEFORE connecting -- which is when an agent
//     should read it. A session-shaped guidance document could only be fetched
//     after the moment it was most needed.
//   - READER-AGNOSTIC. It says "your reader's report-focus command", never
//     "NVDA+Tab". Spec 0005 principle 2 forbids this server learning one
//     reader's key map; the agent already knows NVDA's and JAWS's from its
//     training, and screenreader://info tells it which one is connected. This
//     document supplies the method, the agent supplies the vocabulary.
//
// Why it exists at all: `press_gesture` returning ok means the reader ACCEPTED
// the input, not that anything happened -- the reader does the work afterwards
// on its own thread (spec 0021 measured a millisecond). An agent that reads ok
// as "the dialog is open" then types into whatever was already focused, and the
// symptom surfaces later as an unrelated check failing. Three live failures in
// 11.5's run had exactly that shape.
package mcp

import (
	"context"
	"fmt"
	"strings"

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"

	"github.com/marlon-sousa/screen-readers-mcp/server/domain/entities"
)

// GuidanceURI is the resource's address.
const GuidanceURI = "screenreader://guidance"

// addGuidanceResource registers the resource. Always present, and unlike the
// other two it does not even consult a session: there is nothing to be connected
// to in order to learn how to drive.
func (s *Server) addGuidanceResource() {
	s.sdk.AddResource(
		&sdk.Resource{
			URI:      GuidanceURI,
			Name:     "how to drive a screen reader",
			MIMEType: "text/markdown",
			Description: "Read this BEFORE connecting. What a screen reader is; WHO YOU CAN " +
				"CONNECT AS and what each stance means, which you must choose before " +
				"connect_reader and may want to confirm with the human first; how to get " +
				"the application under test in front of you, act, confirm that what you " +
				"intended actually happened, and orient yourself when it did not -- the way " +
				"a screen reader user does, by pressing keys and listening, rather than by " +
				"inspecting internals. Also what a successful press_gesture result does and " +
				"does not mean.",
		},
		func(_ context.Context, _ *sdk.ReadResourceRequest) (*sdk.ReadResourceResult, error) {
			return &sdk.ReadResourceResult{Contents: []*sdk.ResourceContents{{
				URI:      GuidanceURI,
				MIMEType: "text/markdown",
				Text:     guidanceDocument(),
			}}}, nil
		},
	)
}

// guidanceDocument assembles the served text: the static prose with the persona
// profiles composed into it.
//
// Built per read rather than once at init, because it is cheap, and because a
// package-level variable built from another package's function is a start-order
// dependency nobody can see.
func guidanceDocument() string {
	var document strings.Builder
	document.WriteString(guidancePreamble)
	for _, persona := range entities.AllPersonas() {
		fmt.Fprintf(
			&document,
			"\n### `%s` — *%s*\n\n%s\n",
			persona, persona.Question(), persona.Profile(),
		)
	}
	document.WriteString(guidanceMethod)
	return document.String()
}

// guidancePreamble is everything before the persona profiles. Prose, because its
// reader is a model and the thing being conveyed is judgement rather than a
// schema.
const guidancePreamble = `# Driving a screen reader through this server

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

Read ` + "`screenreader://info`" + ` to learn which reader you are driving, then use
that reader's own commands, in the notation its user guide prints. This document
names no keystrokes anywhere, deliberately -- it cannot know whether you are
driving a Windows desktop reader or a touch-screen one, and a key that does not
exist on the reader in front of you is worse than no advice.

## Who you are connecting as

Before you connect you must say **what you are standing in for**, because it
decides what your findings mean. The same observation -- *"I reached that
control"* -- is a pass from one stance and a finding from another, and afterwards
nobody can tell which claim you were making unless you said so first.

Choose with ` + "`connect_reader`" + `'s ` + "`persona`" + ` argument. It is fixed for the whole
session: a stance cannot be applied to a run that already happened.

If a human started you and the choice is not obvious from your task, then
**ask them before you connect**. This is the one decision that cannot be
revisited later, and ` + "`ask_user`" + ` needs a live session -- so by the time you
could ask through this server, the choice has already been made.

One rule spans all three, and it is the one to hold on to:

> **The ordinary user's vocabulary is whatever the platform's own accessibility
> contract assumes of an ordinary user of that platform.** Within it, a command
> that re-reads what is already there is available to everyone; a command that
> *reaches what focus cannot* -- object navigation, a review cursor, a simulated
> click -- is not available to the ` + "`user`" + ` and ` + "`validator`" + ` stances at all.

Which of *your* reader's commands fall on which side of that line is your
reader's own to say, not this document's. Once connected, ask the reader.
`

// guidanceMethod is everything after the profiles: the method, which does not
// vary by persona and is spec 0023's original document nearly unchanged.
const guidanceMethod = `
## A successful result means delivery, not consequence

` + "`press_gesture`" + ` and ` + "`type_text`" + ` return once the reader has **accepted** the
input. The reader then does the work afterwards, on its own thread. At the
instant your result is written, the dialog has not opened, focus has not moved,
and nothing has been spoken.

So a successful result never tells you that the thing you wanted happened. It
tells you the keystroke arrived. Confirm the rest.

Two corollaries worth stating:

- ` + "`type_text`" + `'s ` + "`typed`" + ` count is the length of what was **sent**, counted on
  this side. It says nothing about what arrived anywhere.
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

**A gesture is a discrete press and release.** ` + "`press_gesture`" + ` sends each gesture
whole, so no modifier can be held down across several other keys. The ordinary
hold-a-modifier-and-tap-repeatedly way of walking a window switcher is therefore
**not expressible here at all**: every press releases, and a switcher that lives
only as long as its modifier is held starts over each time. The limit is general,
not a window-switching quirk — anything meaning "hold this down while pressing
that several times" is outside what a gesture can say.

**So choose a route made of separate presses.** Either name the application
rather than cycle to it — open the desktop's launcher or search, type the name
with ` + "`type_text`" + `, press Enter; three ordinary calls, independent of how many
windows are open, and layout-independent, which makes it the one to prefer — or
use a switcher that *stays up after its keys are released*, which can then be
moved through one gesture at a time and committed with Enter.

Your desktop's keys for either route are yours to supply, exactly as your
reader's are — and for a sharper reason. This document is **static**: it is
readable before you connect, so it cannot know which reader you are driving, and
the reader is what fixes the platform. Read ` + "`screenreader://info`" + ` to learn which
reader is connected; that tells you the desktop as well.

What a *particular* reader can and cannot do for you here is the reader's own to
say, not this document's — readers differ in what they offer, not merely in which
keys they use for it, so do not assume a facility exists just because another
reader has one. If you cannot establish where you are by the loop below, say so
with ` + "`ask_user`" + ` rather than guessing at a command that may not exist.

Then settle and listen for the window title, exactly as in the loop below — that
is your confirmation that you arrived, and the reader volunteers it without being
asked. **Confirm by listening rather than by counting presses**, and do not
assume how a switcher is ordered. An agent that assumes it is in the right window
types into whatever was already focused, and that surfaces later as an unrelated
failure naming the wrong component — see *Before you type, know where you are*
below.

If the application is not running at all, start it with whatever tooling you have
outside this server. That is setup rather than testing, and it is the one part of
driving a screen reader this server deliberately leaves alone.

## The loop: act, settle, listen, orient, escalate

**1. Act.** ` + "`press_gesture`" + ` or ` + "`type_text`" + `.

**2. Settle.** ` + "`wait_for_speech_to_finish`" + `. This is the one wait that applies
after **any** action, because speech is the one thing a reader produces for
everything it does. Never sleep instead: a sleep is either too short and flaky
or too long and slow, and it is never evidence.

**3. Listen.** ` + "`get_speech`" + ` (or ` + "`get_last_speech`" + `). A window that opens
announces its title -- that is your confirmation that you are where you meant to
be, and the reader volunteers it without being asked. If you hear the wrong
title, you are somewhere else: the gesture may be remapped on this machine, or
the application may have opened something you did not expect.

**4. Orient**, if what you heard was not enough. Press the reader's own
"report the focused object" command and listen to the answer. Its report-title
and read-whole-window commands are there for the same reason. This is ordinary
screen reader operating knowledge -- asking the reader where you are is a
*command you send*, and its answer arrives on the same channel as everything
else. Then settle and listen again.

**5. Escalate.** Try what a user would try next -- Tab, Escape -- and notice
when it produces nothing, which is itself information. If you still cannot tell
where you are, call ` + "`ask_user`" + ` and ask the human at the machine. Do not guess,
and do not proceed with an action whose target you are unsure of.

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
Then settling finishes on silence, and you cannot separate "nothing happened"
from "something happened quietly".

That is the moment to introspect: ` + "`get_state`" + ` answers questions about modes
that are signalled by sound, and ` + "`get_focus_info`" + ` answers when the ear has
nothing to work with. Reach for them here, not as your default way of finding
out where you are.

## Introspection is for a different job — and this part depends on your stance

` + "`get_focus_info`" + `, ` + "`get_state`" + ` and ` + "`get_config`" + ` read the reader's own model
directly. They are good for two things:

- **asserting** in a test what a control reports about itself -- for instance
  that a control claims a name and a role *and* that the reader announced
  nothing when it received focus, which is a bug you cannot see from either
  observation alone;
- **surveying** an application you are about to build for.

For ` + "`user`" + ` and ` + "`validator`" + ` they are **not** how you find out where you are: use
the loop above for that, because the loop is what the person you are standing in
for actually has. For ` + "`validator`" + ` the first bullet is the whole point -- stating
precisely what is wrong is what that stance owes.

For ` + "`expert`" + ` this section does not apply. The reader is part of what you are
examining rather than the instrument you examine through, so its model, its
configuration and its log are legitimate first resorts.

## In short

Act, wait for speech to settle, read what was said. If that does not tell you
where you are, ask the reader with its own command and listen again. If that
still does not, ask the human. Introspect on purpose, not by reflex, and never
sleep.
`
