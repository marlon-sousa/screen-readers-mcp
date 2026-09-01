# Driving VoiceOver on macOS

This is VoiceOver's own account of how to work this reader, and of where the
boundary of the ordinary user's vocabulary falls **on VoiceOver specifically**.
The stance you are holding is normative and lives at `screenreader://guidance`;
this document instantiates it, and cannot redefine it.

Read the next section before anything else. It is the one place where this reader
differs from every other one you may have driven, and getting it wrong produces
failures that look like a broken interface.

## `press_gesture` takes TWO notations, and the difference matters

On this reader a gesture id is either **one of VoiceOver's own English command
names**, which the reader dispatches itself, or **a keystroke**, which this
bridge posts at the system:

    press_gesture { gestures: ["describe item in voiceover cursor"] }   # the reader
    press_gesture { gestures: ["command+l"] }                           # the system
    press_gesture { gestures: ["kb:h"] }                                # the system

**Two things tell them apart, and you only need the first one.**

- **`kb:` says "this is a key".** Everything after it is a keystroke, whatever it
  looks like. That is what lets you press a single letter — `kb:h`, the key an
  ordinary user presses to move by heading with single-key Quick Nav on. Without
  the prefix, `h` is looked up as one of the reader's command names and refused.
- **Otherwise a `+` says it**, so `command+l` needs no prefix. A command name is
  a phrase and always contains a space; a keystroke never does. So `command key`
  is a command the reader performs and `command+l` is a chord the system
  receives.

The prefix is optional on a chord and required on a lone key. `kb:command+l` and
`command+l` are the same gesture.

**Prefer the command name whenever one exists.** It costs no permission at all,
it works whatever the user has rebound, and the reader diagnoses it for you. The
keystroke route exists for the chords the reader has no command for — which is
most of the ones an ordinary Mac user presses.

Four consequences that save round trips:

- **An unknown command name fails cleanly and changes nothing.** The reader
  answers `Command does not exist (6)`. So guessing a name costs one round trip
  and is safe — which makes trying one a legitimate way to find out whether this
  reader has a facility, and a better one than trusting a list that goes stale
  every macOS release.
- **The vocabulary is large** — 414 commands on macOS 15.0 — and this document
  names only what a session actually needs. The reader is the authority on the
  rest.
- **This document contains no table of key combinations for reader commands**,
  and one would be worse than useless: what a user has bound to a command is
  theirs, it differs between the desktop and the laptop layout and between the
  three commanders, and none of it changes the command's name.
- **VoiceOver's own `VO-D` shorthand is refused**, by this bridge rather than by
  the reader. It is neither a command name the reader will dispatch nor a chord
  this bridge can press: `VO` is whatever the person has bound their VoiceOver
  modifier to — Control-Option, or Caps Lock, or both — so pressing it would mean
  guessing at somebody's own configuration. Send the command name, or write the
  literal keys out as `control+option+d`.

## Keystrokes: how to write one, and what it costs

    command+l          control+option+space          shift+command+4          kb:h

**Modifiers first, the key last, joined by `+`.** The modifiers are `command`,
`control`, `option` (`alt` also works), `shift` and `fn`; case does not matter
and neither does the order of the modifiers among themselves. The key is a single
character, or one of these names:

| Key | Write | Also accepted |
|---|---|---|
| Return | `enter` | `return` |
| The Delete key, which erases backwards | `backspace` | — |
| Forward delete | `forwardDelete` | — |
| The arrows | `leftArrow`, `rightArrow`, `upArrow`, `downArrow` | `left`, `right`, `up`, `down` |
| Paging | `pageUp`, `pageDown`, `home`, `end` | — |
| The rest | `space`, `tab`, `escape` | `esc` |
| Function row | `f1` … `f20` | — |

**These are NVDA's spellings, on purpose.** Every key name this reader accepts
names the same physical key on the other reader in this contract, so a keystroke
that works here works there. Two names are **refused** rather than guessed at,
because they would not:

- **`delete`** means a different key on each platform — this machine's Delete
  erases backwards, Windows' erases forwards. Write `backspace` or
  `forwardDelete`, or send the reader's own `delete key` command.
- **`insert`** is a key this keyboard does not have. Neither is there an `nvda`
  modifier: VoiceOver's is Control-Option unless the person rebound it, so send
  the command name rather than guessing at somebody's configuration.

**And one key has no shared spelling at all:** NVDA calls forward delete
`delete`, which is exactly the name refused here. A script that runs on both
readers has to spell that one key differently.

- **A key with NO modifier needs the `kb:` prefix** — `kb:h`, `kb:enter`. Without
  it the id is a command name. That is not pedantry: the reader has commands for
  most single keys (`return key`, `tab key`, `left arrow key`, `f8 key`), it
  performs them itself, and **they cost no permission at all**. Prefer them.
  `kb:` is for the keys the reader has no command for — which is every letter,
  and letters are what single-key Quick Nav is made of.
- **A keystroke costs the Accessibility grant**, exactly as `type_text` does, and
  the request is raised on the first one of a session. A session that presses only
  command names and reads speech is never asked for anything — so if you do not
  need a key, do not send one.
- **The keyboard layout is the machine's, not yours.** Which physical key
  produces `l` depends on the layout the person is typing on, and this bridge asks
  the live layout rather than assuming an American keyboard. If the active layout
  has no key for a character, the press **fails by name and sends nothing** — it
  never presses a different key instead. That failure is a real answer: try
  another chord, or ask the person at the machine.
- **What arrives is still not what was sent.** The application may swallow or
  reinterpret a chord, and nothing here can see that. A check that needs to know
  what happened asks the application or the reader afterwards.

Re-runnable as `bash scripts/voiceover_chords.sh` in this repository.

## Do NOT build a chord out of the reader's modifier commands

This is a measured limit, and it is the one that will bite you if you go looking
for a cheaper route than the one above.

The vocabulary contains 30 commands whose name ends in `key`, and they work:
`tab key`, `return key`, `delete key`, `forward delete key`, the four arrows
(`up arrow key`, `down arrow key`, `left arrow key`, `right arrow key`), `f1 key`
through `f12 key`, and the modifiers in two flavours — momentary (`command key`,
`option key`, `shift key`, `control key`, `fn key`) and sticky (`toggle command
key`, `toggle option key`, …).

**The modifiers do not compose.** Measured on macOS 15.0, 2026-08-30, four runs —
sticky and momentary, Option and Command — each followed by `delete key` into a
scratch document. Every one removed exactly one character, the same as the
no-modifier control, where Option-Delete would have taken a word and
Command-Delete the line. The modifier command **succeeds** and changes nothing
about the key that follows it, which is the worst shape a negative can have: no
error tells you it did not work.

So:

- **Never send `command key` followed by a letter and expect a chord.** It will
  report success twice and do the wrong thing. Send `command+l`, which is one
  call and really is a chord.
- **`type_text` cannot press one either.** It carries a Unicode *payload*, which
  is how literal text arrives; it does not hold a modifier down. Typing and
  chording are two different acts and this reader has a route for each.
- **`type_text "h"` does move single-key Quick Nav, and it is still the wrong
  call.** A letter reaching the focused page is a letter either way, so it works
  by coincidence — and the same call types an `h` into a text field, which is a
  difference you cannot see before you make it. `press_gesture ["kb:h"]` says
  which one you meant, and the record of the run says it too.
- The table has **no letter keys at all**, so literal text can never come out of
  it. `type_text` is how text is entered, always.

Re-runnable as `bash scripts/voiceover_modifiers.sh` in this repository.

## AN ANNOUNCEMENT HERE IS TWO UTTERANCES, and that changes how you read

This is the section to read before you write a loop, and it is where an agent
that has driven NVDA will get it wrong without any error to tell it so.

**Landing on an element produces two separate utterances**: its role, then its
text.

```
"nível de título 2  link"                                   <- the role
", COMO ESCREVER CARACTERES ACENTUADOS NO IOS 11.0 …"       <- the text
```

**If you have driven NVDA, this is where your instincts are wrong.** Both readers
wait for the synthesizer before moving on — that part is the same. What differs is
that NVDA's bridge captures speech *before* the reader queues it, so a session
there sees everything the reader decided to say whatever the synthesizer is doing,
and whether or not the speech was later cancelled. **Here the capture point is the
synthesizer itself.** An utterance the reader cancels before speaking it is one
you never see — it is not delayed, it is gone. That is why `silent` and `live`
change what you can read on this reader and change nothing on that one.

**And there is a pipe between the reader and you.** On this platform the reader,
the voice that captures its speech and this bridge are three separate processes,
so an utterance reaches a session over IPC rather than in memory — which is not
true of every reader, and means a wait that is generous elsewhere can be tight
here. Budget for it: when in doubt, give a grace window more room than you think
it needs, and read again from `speech_to` rather than concluding the reader said
nothing.

Measured on macOS 15.0, 2026-08-31, in Safari web content — these are differences
between two emission stamps, so they are the reader's own timing and not the
pipe's:

| Session | Role → text gap |
|---|---|
| `silent` | **50–110 ms** |
| `live` | **~1505 ms** |

**A live session is paced by audio**, because the reader waits for one utterance
to be spoken before it hands over the next. That is not a defect: it is a person
listening. But it means any command you send inside that window **cancels the
text before it is ever spoken**, and it is then gone — not delayed, not
recoverable, never captured.

Three rules follow, and they are the practical content of this section.

- **`grace_ms` returns as soon as the FIRST utterance arrives**, by contract. So
  it hands you the role and the text is still in flight. If you need the text,
  read again from `speech_to`, or press one gesture per call with a generous
  grace — never batch several gestures into one `press_gesture` and expect their
  text.
- **In a live session, SEQUENCE TO ACT, NOT TO READ.** `run_sequence` is excellent
  here for a known plan — open a location bar, type an address, commit it — and
  that works perfectly. But a sequence whose purpose is *reading* captures the
  first utterance of each step and loses the rest. Measured: four moves batched
  in one call returned four utterances and **not one heading title**.
- **Prefer a `silent` session whenever you are reading.** It is already the right
  default; this is the concrete reason. Nothing is spoken aloud, so nothing waits
  for audio, so the queue drains in milliseconds and the text arrives with the
  role. The same nine moves that lost every title in a live batch captured
  **twenty utterances, every title present**, in a silent `run_sequence` with a
  400 ms gap.

**Do not use `wait_for_speech_to_finish` to solve this.** It asks "has speech
stopped?", and silence before speech starts is indistinguishable from silence
after it ends — so it returns immediately in the gap between the role and the
text and tells you nothing. The same is true of a `settle` step inside
`run_sequence`. What works is a fixed gap between steps, or one gesture per call.

**`wait_for_speech` is case-sensitive.** Matching `"Blindtec"` will not find an
utterance reading `https://www.blindtec.com.br/blog/`.

## The ordinary vocabulary on this reader

This is what the macOS accessibility contract assumes of an ordinary VoiceOver
user, and therefore what any interface is entitled to assume you have.

**And it sits somewhere different from where it sits on a Windows reader.** On
NVDA, moving a cursor independently of system focus is an expert's escape hatch.
On VoiceOver it is *how everybody works*: the VoiceOver cursor is the primary
means of navigation for an ordinary user, not a way around a broken interface.
A stance transcribed from a Windows reader would forbid the thing this
platform's own users do all day. That is the single most important reason this
document exists.

**Moving around** — the VoiceOver cursor, which is ordinary here:

- `move right`, `move left`, `move up`, `move down` — through the elements of
  whatever you are in.
- `start interacting with item`, `stop interacting with item` — down into a
  group, table or text area, and back out. This is the structure of macOS
  navigation and there is no substitute for it.
- `go to menu bar`, `go to dock`, `go to desktop`, `go to status menus` — the
  desktop's own places, reached by name.
- `item chooser` — a searchable list of what is in the window.
- `rotor`, `next rotor item`, `previous rotor item`, `move up in rotor`,
  `move down in rotor` — the rotor, which is how a user changes what the arrows
  do.
- `find next heading`, `find next link`, `find next button`, `find next control`,
  `find next text field`, `find next table`, and their `find previous`
  counterparts — web and document navigation by element type. These are this
  platform's single-letter navigation, and like it they are **inside** every
  stance's vocabulary: they are how a user reads a page, not a way around a
  broken one.

**Single-key Quick Nav is the same thing under the person's own fingers**, and
when it is on the letters do it: `kb:h` for the next heading, `kb:l` for a link,
`kb:b` for a button, `kb:1` through `kb:6` for a heading level. An ordinary user
turns it on and navigates a page that way all day, so it is inside every stance's
vocabulary too — press the letters the way a person would.

Two things to know before you rely on it. It is a **mode**, and it is off unless
somebody turned it on; `toggle single-key quick nav on or off` flips it and says
which way it went, which is how you find out (see "How you read state" below).
And while it is on, those letters no longer reach the page as text — which is
what makes it worth turning off again before you type into a field.

**Acting on things**, through the key commands above: `return key` to activate,
`space` — which is not in the vocabulary, so use `return key` or the item's own
command — and `tab key` to move forward. Backwards is `shift+tab`, which is a
keystroke and costs the Accessibility grant, so `move left` is the cheaper way
when the VoiceOver cursor will do.

**The chords an ordinary Mac user presses in the first minute**, all of which are
keystrokes rather than command names: `command+l` (the location bar),
`command+f` (find), `command+t` (a new tab), `command+n`, `command+s`,
`command+a`, `command+z`, `command+shift+tab`. Use them the way a person would.

**Typing** is `type_text`, into whatever holds keyboard focus. It presses no
Enter and submits nothing.

## VoiceOver's reading commands, as this reader names them

These re-read what is already in front of you. They make no claim about
reachability, so they are inside **every** persona's vocabulary:

| What it does | Command |
|---|---|
| Describe what the VoiceOver cursor is on | `describe item in voiceover cursor` |
| Describe what has keyboard focus | `describe item with keyboard focus` |
| Read everything under the cursor | `read contents of voiceover cursor` |
| Read the whole window | `read contents of window` |
| Describe the window itself | `describe window` |
| Read the current line, paragraph, character | `read current line`, `read current paragraph`, `read current character` |
| Where the cursor is, and how big | `describe position of item in voiceover cursor`, `describe size of item in voiceover cursor` |
| What applications are open | `describe open applications` |
| Stop or resume speaking | `pause or resume speaking` |

`describe item in voiceover cursor` is the *orient* step of the loop in
`screenreader://guidance` on this reader. It describes what the cursor is already
on and **moves nothing**, which makes it the safe probe: reach for it whenever
what you heard after acting was not enough.

## How you read state on a reader that cannot be asked

**There is no `get_state` and no `set_state` here, and that is a property of the
reader rather than a gap in this bridge.** VoiceOver's scripting dictionary
reports four properties in total and none of them is a mode. Its 45 toggleable
settings are *commands* — every one of them — and not one has a query. So there
is nothing to read before a write, which is exactly what `set_state`'s contract
requires.

**What replaces it: toggle, and listen to what the reader says.** Every one of
these announces its own resulting state out loud, and `press_gesture` returns
that announcement in the same call:

    press_gesture { gestures: ["toggle web navigation dom or group"] }
    -> speech: [ "<the mode it has just arrived in>" ]

So you read the state by causing it to be spoken. If it is not the one you
wanted, press the same command again. That is full authority over all of them.

**The toggles worth knowing**, out of the 45 — these are the ones that change how
an interface behaves under you, so they are the ones a session needs to be able
to name:

| What it changes | Command |
|---|---|
| DOM order versus grouped web navigation | `toggle web navigation dom or group` |
| Single-key Quick Nav (letters jump by element) | `toggle single-key quick nav on or off` |
| Arrow-key Quick Nav | `toggle arrow-key quick nav on or off` |
| Both together | `toggle arrow-key and single-key quick nav on or off` |
| Whether the caret and the VoiceOver cursor move together | `toggle insertion point navigation` |
| Whether the cursor follows keyboard focus | `toggle cursor tracking on or off` |
| Elements the reader is hiding | `toggle hiding ignored elements` |
| Whether a table can be interacted with | `toggle table interactability` |
| Row and column indices in table announcements | `toggle table row and column indices` |
| The screen curtain | `toggle screen curtain on or off` |
| Speech, sound, or the reader itself | `mute speech toggle`, `mute sound toggle`, `mute voiceover toggle` |
| The VoiceOver-modifier lock | `toggle the vo modifier lock on or off` |

**Two warnings, and the second one is about somebody's machine.** These are
toggles: they do not arrive at a state, they flip one, so pressing one twice
returns the machine to where it was and pressing one once leaves it changed for
whoever uses this computer next. And `mute voiceover toggle` and `toggle screen
curtain on or off` change what a *person* can perceive — never press either
without a reason you could defend to the person sitting there.

## Where you are: two cursors, and they separate

`get_focus_info` on this reader answers about the **keyboard** cursor, from the
frontmost application's accessibility tree — and the VoiceOver cursor is a
different thing that can be somewhere else.

Measured on macOS 15.0, 2026-08-30: with a text document focused, one press of
`stop interacting with item` moved the VoiceOver cursor to the enclosing scroll
area while the keyboard cursor and the accessibility tree both stayed on the
text. Re-runnable as `bash scripts/voiceover_cursors.sh`.

So, concretely:

- **If you navigated with `press_gesture` and then asked where you are, you got
  the element you left**, not the one you are on. To ask about the VoiceOver
  cursor, press `describe item in voiceover cursor` and read the speech.
- **`role` and `appModule` are stable across machines**; `role` is the raw
  `AXRole` (`AXTextArea`, `AXButton`) and `appModule` is a bundle identifier
  (`com.apple.TextEdit`).
- **The VoiceOver cursor's own answer is LOCALIZED, and is not comparable across
  machines.** The same run that measured the split got `área de rolagem` from the
  reader where the tree said `AXTextArea`, because that machine is Portuguese.
  Use it to understand what you are looking at; **never assert on it**, and never
  compare it with a string from another machine or another run.

That last point generalises, and it is the rule this whole lane works under: this
reader renders in the user's own language everywhere. Compare **structure** —
roles, counts, order, whether something was announced at all — and never text.

## What this reader does not offer

Readers differ in what they *offer*, not merely in which keys they use for it, so
do not assume a facility exists because another reader has one.

- **No braille content.** VoiceOver exposes no readable braille buffer, so
  `get_braille` does not exist here. A braille display attached to this machine
  is showing something; this bridge cannot tell you what.
- **No reader log.** There is no VoiceOver equivalent of NVDA's log, so `get_log`
  and its family do not exist. The system's unified log is not a substitute: it
  is not the reader's account of what it did.
- **No settable state**, for the reason given above.
- **No document snapshot.** There is no way to ask this reader for a whole
  document as flat lines; read it with the reading commands, or navigate it with
  `find next …`.
- **No "list open windows" that this bridge can drive**, but `describe open
  applications` and `item chooser` between them cover most of what you would want
  it for.

## Your session was SET UP before you were handed it

`connect_reader` does not merely open a channel here. Before it answers it reads
the two permissions this bridge needs, starts VoiceOver if it is not running,
registers the capture voice's extension with the system if the system has
forgotten it, points the reader at that voice, and then makes the reader speak
and requires the words to arrive. If any of that could not be done, **you get a
named failure instead of a session** — which step, what was wrong, and what you
must do, usually "tell the person at this machine to do X, then connect again".

Two consequences worth holding on to:

- **An empty `get_speech` now means the reader said nothing.** It used to be able
  to mean "this machine cannot capture at all", and the two were
  indistinguishable. They are not any more: a session that exists is a session
  whose capture was proved a moment ago. So an empty read is a fact about the
  interface you are testing, not a fault to go hunting for.
- **The first utterance of every session is not yours.** Index 1 holds what the
  reader said when the setup asked it to describe what its cursor is on — real
  speech, recorded like any other, and incidentally a useful statement of where
  you are starting from. Your own first utterance is index 2. Take a bookmark
  with `get_next_speech_index` before you act, as you would anyway, and none of
  this matters.

One thing the bridge will **not** do for you: restart the reader. macOS only
publishes a newly registered voice after VoiceOver restarts, so if the setup had
to register the extension, the connect fails and tells you to ask the person at
the machine to run `killall VoiceOver && open -a VoiceOver` and connect again.
That is not the bridge being timid — restarting somebody's screen reader without
asking is taking their computer away mid-sentence.

## Two things about the machine you are driving

- **Speech is captured through a voice this bridge installs.** In a `silent`
  session the person at the machine hears nothing and you read everything; in a
  `live` session they hear their reader normally and you read the same words.
  Either way, `get_speech` returns what was *spoken*, which on this reader is the
  only account of what happened that exists.
- **The reader crashes.** VoiceOver restarting underneath a session is normal
  weather on macOS rather than an edge case. If commands start failing together,
  or reads go quiet, that is a real possibility — but check what is in *front* of
  you first: a wedged application under test looks exactly like a dead reader,
  and on the maintainer's machine it once was Finder, with VoiceOver entirely
  healthy and saying so out loud.
