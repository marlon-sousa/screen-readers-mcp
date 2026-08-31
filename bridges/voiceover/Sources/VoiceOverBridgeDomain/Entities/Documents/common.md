# Driving VoiceOver on macOS

This is VoiceOver's own account of how to work this reader, and of where the
boundary of the ordinary user's vocabulary falls **on VoiceOver specifically**.
The stance you are holding is normative and lives at `screenreader://guidance`;
this document instantiates it, and cannot redefine it.

Read the next section before anything else. It is the one place where this reader
differs from every other one you may have driven, and getting it wrong produces
failures that look like a broken interface.

## A gesture here is a COMMAND NAME, not a keystroke

On this reader `press_gesture` does not take `control+option+rightArrow`. It takes
VoiceOver's own English command name:

    press_gesture { gestures: ["describe item in voiceover cursor"] }

The reader does its own dispatch. That is why this document does not contain a
table of key combinations, and why one would be worse than useless: what a user
has bound to a command is theirs, it differs between the desktop and the laptop
layout and between the three commanders, and none of it changes the command's
name.

Three consequences that save round trips:

- **An unknown name fails cleanly and changes nothing.** The reader answers
  `Command does not exist (6)`. So guessing a name costs one round trip and is
  safe — which makes trying one a legitimate way to find out whether this reader
  has a facility, and a better one than trusting a list that goes stale every
  macOS release.
- **A keystroke sent as a gesture is refused before it is sent**, by this bridge
  rather than by the reader — `control+l`, and VoiceOver's own `VO-D` notation.
  That is the one mistake the reader cannot diagnose usefully, so it is caught
  here.
- **The vocabulary is large** — 414 commands on macOS 15.0 — and this document
  names only what a session actually needs. The reader is the authority on the
  rest.

## `press_gesture` reaches commands and single KEYS, and NOT chords

This is a measured limit, not a caution, and it is the one that will bite you.

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

- **A chord is not expressible through `press_gesture` on this reader.** Do not
  build one out of two calls; it will report success and do the wrong thing.
- **A chord needs `type_text`'s route**, which synthesizes real system events and
  costs the Accessibility grant.
- The table has **no letter keys at all**, so literal text can never come out of
  it. `type_text` is how text is entered, always.

Re-runnable as `bash scripts/voiceover_modifiers.sh` in this repository.

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

**Acting on things**, through the key commands above: `return key` to activate,
`space` — which is not in the vocabulary, so use `return key` or the item's own
command — `tab key` and `shift`+`tab` are **not** expressible as a chord, so use
`tab key` alone and reach backwards with `move left` instead.

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
