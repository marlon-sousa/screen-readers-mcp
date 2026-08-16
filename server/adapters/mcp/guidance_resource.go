// screenreader-mcp adapters -- the screenreader://guidance resource.
// Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
//
// ROLE: adapter. Serves `screenreader://guidance`, a static document telling an
// agent HOW to drive a screen reader.
// BUILT BY: sdk_server.go's Bind, beside the info and session-record resources.
// DEPENDS ON: nothing. It has no source, which is the point -- see below.
//
// Spec 0023. The other two resources describe a session; this one describes a
// METHOD, so it is deliberately different in two ways:
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

	sdk "github.com/modelcontextprotocol/go-sdk/mcp"
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
			Description: "Read this BEFORE driving a reader. How to get the application " +
				"under test in front of you, act, confirm that what you intended actually " +
				"happened, and orient yourself when it did not -- the way a screen reader " +
				"user does, by pressing keys and listening, rather than by inspecting " +
				"internals. Also what a successful press_gesture result does and does " +
				"not mean.",
		},
		func(_ context.Context, _ *sdk.ReadResourceRequest) (*sdk.ReadResourceResult, error) {
			return &sdk.ReadResourceResult{Contents: []*sdk.ResourceContents{{
				URI:      GuidanceURI,
				MIMEType: "text/markdown",
				Text:     guidance,
			}}}, nil
		},
	)
}

// guidance is the document. Prose, because its reader is a model and the thing
// being conveyed is judgement rather than a schema.
const guidance = `# How to drive a screen reader

## The stance: you are standing in for a user

A screen reader user does not know window classes, control ids, or the
accessibility tree. They press keys and they listen. Drive the same way by
default.

This is not a style preference. If you orient yourself by reading the reader's
object model, you are testing the platform's accessibility API. If you orient
yourself by pressing a gesture and hearing the answer, you are testing the
screen reader and the application together -- which is what a user experiences,
and what you are here to check. The two disagree in exactly the cases that
matter: a control that is correctly exposed to the platform API and announced as
nothing at all passes the first check and fails the second.

Read ` + "`screenreader://info`" + ` to learn which reader you are driving, then use that
reader's own commands, in the notation its user guide prints.

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

Do it the way a user does: switch windows from the keyboard with ` + "`press_gesture`" + ` —
the desktop's own switcher, alt+tab on Windows, or its application launcher —
then settle and listen for the window title, exactly as in the loop below. That
keeps the switch inside what you are testing and gives you the same confirmation
a user gets.

If the application is not running at all, or the desktop will not surface it from
the keyboard, start or raise it with whatever tooling you have outside this
server. That is setup rather than testing, and it is the one part of driving a
screen reader this server deliberately leaves alone.

Either way, confirm you arrived before you act. An agent that assumes it is in
the right window types into whatever was already focused, and that surfaces later
as an unrelated failure naming the wrong component — see *Before you type, know
where you are* below.

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

## Introspection is for a different job

` + "`get_focus_info`" + `, ` + "`get_state`" + ` and ` + "`get_config`" + ` read the reader's own model
directly. They are good for two things:

- **asserting** in a test what a control reports about itself -- for instance
  that a control claims a name and a role *and* that the reader announced
  nothing when it received focus, which is a bug you cannot see from either
  observation alone;
- **surveying** an application you are about to build for.

They are not how you find out where you are. Use the loop above for that.

## In short

Act, wait for speech to settle, read what was said. If that does not tell you
where you are, ask the reader with its own command and listen again. If that
still does not, ask the human. Introspect on purpose, not by reflex, and never
sleep.
`
