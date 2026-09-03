# Driving VoiceOver on macOS

This is VoiceOver's own account of how to work this reader, and of where the
boundary of the ordinary user's vocabulary falls **on VoiceOver specifically**.
The stance you are holding is normative and lives at `screenreader://guidance`;
this document instantiates it, and cannot redefine it.

Read the next section before anything else. It is the one place where this reader
differs from every other one you may have driven, and getting it wrong produces
failures that look like a broken interface.

## What a VoiceOver user presses — and what you press

A VoiceOver user drives this reader by holding **VO** and pressing a key. VO-M
reaches the menu bar, VO-Right Arrow moves to the next item, VO-Space activates
what the cursor is on. That is the vocabulary this document is written in, and it
is what you should be sending:

    press_gesture { gestures: ["vo+m"] }            # go to the menu bar
    press_gesture { gestures: ["vo+rightArrow"] }   # move to the next item
    press_gesture { gestures: ["vo+space"] }        # activate it
    press_gesture { gestures: ["command+l"] }       # and the ordinary Mac chords

**`vo` is read off this machine, never guessed.** VoiceOver's modifier is
Control-Option, or Caps Lock, or either — the person chooses it in VoiceOver
Utility — and this bridge reads their choice and presses that. What comes back in
`pressed` is the **resolved** spelling (`control+option+m`), so the record of your
run says which keys actually went out, and one press tells you what this machine
is set to.

If the person here has bound it to **Caps Lock alone**, `vo+…` is refused by name
and nothing is pressed. This bridge cannot synthesize that key, and
`control+option+…` is not a substitute: on that machine those two keys are not the
modifier at all, and pressing them would do something else entirely. The refusal
says so and names the route that still works.

**Keys are the only way in, and that is on purpose.** This reader will also
dispatch its own commands by name — `go to menu bar` rather than `vo+m` — and
this bridge used to send them. It does not any more, and the reason is the
reason you are here. A keystroke goes out through the window server, past the
application under test, and reaches VoiceOver's event tap, which is exactly the
journey a person's keypress makes. A command name is dispatched *inside* the
reader and never passes the application at all. **So an application that swallows
or reinterprets VO-M is invisible to the command name**, which reports success
while a real user is stuck — and that is the defect class you are here to find.

**So an id with a space in it is refused**, and the refusal names the key. If you
have driven this bridge before, or read anything written about it, you may reach
for `describe item in voiceover cursor`; send `vo+f3` instead. The tables further
down give the key for every act this document names.

## Reaching an act that has no key

Some acts have no keystroke at all. Measured on macOS 15.0 on 2026-09-02: `find
next button`, `find next text field`, `toggle web navigation dom or group`, `mute
speech toggle` and `pause or resume speaking` ship with **no** factory binding.

**You reach them the way a person does: the Commands menu.** Press `vo+h` twice,
type the act's name, press Enter.

    press_gesture { gestures: ["vo+h", "vo+h"] }
    type_text     { text: "mute speech toggle" }
    press_gesture { gestures: ["kb:enter"] }

Read the speech after each step: the menu announces itself, and it announces what
it has narrowed to as you type, so you can see whether it found the act before you
commit to it.

**One caveat, and it is honest rather than tidy.** The menu is rendered in the
machine's own language, while the names above are English. On a machine whose
system language is not English, typing an English name may match nothing — read
the speech, and if it has found nothing, ask the person at the machine what the
act is called for them (`ask_user`). The rotor (`vo+u`) is the other route a
person uses, and it is worth trying for anything about navigating by element.

**If an act has neither a key nor a menu entry you can reach, say so.** That is a
finding about this reader, not a failure of yours, and it is worth writing down.

## Keystrokes: how to write one, and what it costs

    vo+m       vo+shift+w      vo+command+h      command+l      kb:h
    control+option+space       shift+command+4   kb:leftArrow+rightArrow

**Modifiers first, the keys last, joined by `+`.** The modifiers are `vo`,
`command`, `control`, `option` (`alt` also works), `shift` and `fn`; case does not
matter and neither does the order of the modifiers among themselves. A key is a
single character, or one of these names:

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
- **`insert`** is a key this keyboard does not have. It is NVDA's own modifier,
  and **the counterpart here is `vo`**: write `vo+m` where you would have written
  `insert+m`. Each reader's bridge resolves its own modifier, so the two ids mean
  the same act on two machines whose modifier keys are different.

**And one key has no shared spelling at all:** NVDA calls forward delete
`delete`, which is exactly the name refused here. A script that runs on both
readers has to spell that one key differently.

- **A key with NO modifier needs the `kb:` prefix** — `kb:h`, `kb:enter`. Without
  it the id is refused, and the refusal names the prefixed spelling. It is the
  same spelling this bridge writes back to you in `pressed` and in the run's
  record, and the same one the other reader in this contract uses, so one notation
  means one thing everywhere.
- **Two ordinary keys may be held together** — `kb:leftArrow+rightArrow`, which
  is arrow-key Quick Nav. Every part after the modifiers is a key, so there is no
  second separator to learn and `command+leftArrow+rightArrow` says what it looks
  like. The keys go down in the order you wrote them and come up in reverse, so
  they really are held at the same moment — which is what the reader detects;
  sending the two arrows as two gestures moves nothing. There is no limit of two.
- **A keystroke costs the Accessibility grant**, exactly as `type_text` does, and
  the request is raised on the first one of a session. **Every session that drives
  this reader will be asked for it**, once, and that is the price of pressing what
  a person presses. A session that only reads speech is never asked for anything,
  and neither is connecting: this bridge reads permissions at the handshake and
  requests none, so nothing pops a dialog at a machine nobody is watching.
- **The keyboard layout is the machine's, not yours.** Which physical key produces
  `l` depends on the layout the person is typing on, and this bridge asks the live
  layout rather than assuming an American keyboard. If the active layout has no key
  for a character, the press **fails by name and sends nothing** — it never presses
  a different key instead. That failure is a real answer: try another chord, or ask
  the person at the machine.
- **A shifted chord carries its shifted character**, and this is stated because it
  was measured rather than assumed (2026-09-02): this reader matches its bindings
  on the **character** an event carries, not on the key and the modifier flags. So
  `vo+shift+q` reaches VO-Shift-Q and not VO-Q — which it did, silently, before
  that was found. If you ever meet a shifted chord that lands on its unshifted
  binding, that is the shape to suspect.
- **What arrives is still not what was sent.** The application may swallow or
  reinterpret a chord, and nothing here can see that. A check that needs to know
  what happened asks the application or the reader afterwards.

Re-runnable as `bash scripts/voiceover_chords.sh` and
`bash scripts/voiceover_vo_modifier.sh` in this repository.

## SOME KEYS ARE A RING, and the second press is a different command

This one will produce a result you did not ask for and give you no sign that it
did, so read it before you press a key twice.

VoiceOver binds **several commands to one key** and tells them apart by how many
times it has been pressed. `vo+f7` is the time and date; pressed again it is the
battery status; again and it is the wifi status. Thirty of this reader's factory
bindings are like that — `vo+w` spells the word alphabetically on the second
press and phonetically on the third, `vo+m` twice goes to the status menus rather
than the menu bar.

**Apple's documentation writes it as "press twice", which reads as "twice in
quick succession". That is not what the machine does.** Measured on macOS 15.0,
2026-09-02, through this bridge's own key presser:

| what was sent | what the reader said |
|---|---|
| `vo+f7` | the wifi status |
| `vo+f7` again, two seconds later | the time and date |
| `vo+f7` again | the battery status |
| `vo+f7` again | the wifi status |
| `vo+f2`, then `vo+f7` | **the time and date** — back to the first |
| `vo+f7` ten seconds later | the battery status — waiting changed nothing |

So it is a **ring**: each press advances to the next command bound to that key,
and **the ring is reset by pressing a DIFFERENT command, not by waiting.** Where
you land depends on what the person at this machine, or your own last call, did
before you.

Three consequences, and the third is the useful one:

- **A key is not a promise about which command runs.** `press_gesture` reports
  what it PRESSED; the reader decides what that meant, and nothing in the result
  says which of the bound commands answered. What came back in `speech` is your
  only evidence, and on this reader it is a good one — the three answers above
  cannot be mistaken for each other.
- **Do not press a key twice to hear something again.** That is a different
  command. Use `vo+z` (`repeat last phrase`), or read the speech you already have
  by index.
- **To get the FIRST meaning of such a key, press a different command first** —
  any one, including a harmless one like `vo+f2`. That is what a person does, and
  it is the only route: the reader's own command names select exactly one command
  and have no ring, but this bridge does not send them (see the top of this
  document). If a check depends on WHICH of the bound commands ran, reset the ring
  first and read the speech to confirm where you landed.

Re-runnable as `bash scripts/voiceover_press_count.sh` in this repository.

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

- **This is history rather than advice now**, because this bridge no longer sends
  the reader's command names at all — `command key` is not an id you can send. It
  is kept because it explains why `press_gesture` takes a chord as ONE id: the
  route that looked like it would compose one does not.
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

**Every keystroke in the tables below was read out of this reader's own factory
configuration**, on macOS 15.0, on 2026-09-02 — not remembered from Apple's
documentation. Re-runnable as `python3 scripts/voiceover_default_bindings.py`,
which presses nothing and needs no permission.

**The second column is the act's NAME, not an id you can send.** It is what the
act is called in VoiceOver Utility and in the Commands menu, so it is what you
type into that menu to reach an act with no key — and it is the word to use when
you tell a human what you did.

**One honest limit on the whole table.** These are the FACTORY bindings. A person
who has rebound a command in VoiceOver Utility gets their own key, which this
bridge does not read. So a key that does nothing here may mean the person rebound
it rather than that the application swallowed it, and the way to tell is to ask
them (`ask_user`) or to look in the Commands menu, which lists what this machine
actually has.

**And this vocabulary sits somewhere different from where it sits on a Windows
reader.** On NVDA, moving a cursor independently of system focus is an expert's
escape hatch. On VoiceOver it is *how everybody works*: the VoiceOver cursor is
the primary means of navigation for an ordinary user, not a way around a broken
interface. A stance transcribed from a Windows reader would forbid the thing this
platform's own users do all day. That is the single most important reason this
document exists.

**Moving around** — the VoiceOver cursor, which is ordinary here:

| What a user presses | What the act is called |
|---|---|
| `vo+rightArrow`, `vo+leftArrow`, `vo+upArrow`, `vo+downArrow` | `move right`, `move left`, `move up`, `move down` |
| `vo+shift+downArrow` | `start interacting with item` |
| `vo+shift+upArrow` | `stop interacting with item` |
| `vo+m` | `go to menu bar` |
| `vo+m` twice | `go to status menus` |
| `vo+d` | `go to dock` |
| `vo+shift+d` | `go to desktop` |
| `vo+i` | `item chooser` — a searchable list of what is in the window |
| `vo+u` | `rotor` |
| `vo+command+upArrow`, `vo+command+downArrow` | `move up in rotor`, `move down in rotor` |
| `vo+shift+escape` | `jump to top level` |

`start interacting with item` and `stop interacting with item` are the structure
of macOS navigation — down into a group, table or text area, and back out — and
there is no substitute for them.

**Finding things in a page or a document** — this platform's single-letter
navigation, and like it these are **inside** every stance's vocabulary: they are
how a user reads a page, not a way around a broken one.

| What a user presses | What the act is called |
|---|---|
| `vo+command+h` / `vo+command+shift+h` | `find next heading` / `find previous heading` |
| `vo+command+l` / `vo+command+shift+l` | `find next link` / `find previous link` |
| `vo+command+j` | `find next control` |
| `vo+command+t` | `find next table` |
| `vo+command+x` | `find next list` |
| `vo+command+g` | `find next image` |
| `vo+command+n` | `find next landmark` |
| — no factory key — | `find next button`, `find next text field` |

`vo+f` is `find`, and `vo+g` finds the next match of what you searched for.

**Single-key Quick Nav is the same thing under the person's own fingers**, and
when it is on the letters do it: `kb:h` for the next heading, `kb:l` for a link,
`kb:b` for a button, `kb:1` through `kb:6` for a heading level. An ordinary user
turns it on and navigates a page that way all day, so it is inside every stance's
vocabulary too — press the letters the way a person would.

Two things to know before you rely on it. It is a **mode**, and it is off unless
somebody turned it on; `vo+q` (`toggle single-key quick nav on or off`) flips it
and says which way it went, which is how you find out. Its sibling `vo+shift+q`
is `toggle arrow-key quick nav on or off`. **Prefer either of those to the key
chord you may know from Apple's own documentation** — a person toggles Quick Nav
by pressing Left Arrow and Right Arrow *together*, and this bridge can press that
(`kb:leftArrow+rightArrow`), which does not make it the way to do it: measured
2026-09-01, that chord moves **two** settings rather than one, taking single-key
Quick Nav down with arrow-key Quick Nav, and the announcement it makes ("Quick Nav
on"/"off", measured 2026-09-02) does not say which of them moved. So it tells you
less than it appears to. And while single-key Quick Nav is on, those letters no
longer reach the page as text — which is what makes it worth turning off again
before you type into a field.

**Acting on things**: `vo+space` (`perform action for item`) activates what the
cursor is on; `kb:enter` and `kb:tab` are the ordinary keys, and `shift+tab` goes
backwards. `vo+shift+m` opens the shortcut menu — what a right-click would show.

**The chords an ordinary Mac user presses in the first minute**, all of which are
the system's rather than the reader's: `command+l` (the location bar),
`command+f` (find), `command+t` (a new tab), `command+n`, `command+s`,
`command+a`, `command+z`, `command+shift+tab`. Use them the way a person would.

**Typing** is `type_text`, into whatever holds keyboard focus. It presses no
Enter and submits nothing.

## VoiceOver's reading commands, as a user presses them

These re-read what is already in front of you. They make no claim about
reachability, so they are inside **every** persona's vocabulary:

| What it does | Press | What the act is called |
|---|---|---|
| Describe what the VoiceOver cursor is on | `vo+f3` | `describe item in voiceover cursor` |
| Describe what has keyboard focus | `vo+f4` | `describe item with keyboard focus` |
| Read everything under the cursor | `vo+a` | `read contents of voiceover cursor` |
| Read the whole window | `vo+shift+w` | `read contents of window` |
| Describe the window itself | `vo+f2` | `describe window` |
| Read the current line, word, character | `vo+l`, `vo+w`, `vo+c` | `read current line`, `read current word`, `read current character` |
| Read the current paragraph, sentence | `vo+p`, `vo+s` | `read current paragraph`, `read current sentence` |
| Repeat the last thing said | `vo+z` | `repeat last phrase` |
| What applications are open | `vo+f1` | `describe open applications` |
| Stop or resume speaking | — no factory key — | `pause or resume speaking` |

On a laptop keyboard the function-key rows are also bound as `fn+vo+3`,
`fn+vo+4`, and so on — the same commands, reached the way a person reaches them
when the top row is media keys. This bridge presses `vo+f3` as written; whether
that needs `fn` on the machine in front of you is the machine's own setting, and
one this bridge does not read.

`vo+f3` is the *orient* step of the loop in `screenreader://guidance` on this
reader. It describes what the cursor is already on and **moves nothing**, which
makes it the safe probe: reach for it whenever what you heard after acting was not
enough.

## How you read state on a reader that cannot be asked

**There is no `get_state` and no `set_state` here, and that is a property of the
reader rather than a gap in this bridge.** VoiceOver's scripting dictionary
reports four properties in total and none of them is a mode. Its 45 toggleable
settings are *commands* — every one of them — and not one has a query. So there
is nothing to read before a write, which is exactly what `set_state`'s contract
requires.

**What replaces it: toggle, and listen to what the reader says.** Every one of
these announces its own resulting state out loud, and the speech comes back in
the same call:

    press_gesture { gestures: ["kb:leftArrow+rightArrow"] }   # arrow-key Quick Nav
    -> speech: [ "<the mode it has just arrived in>" ]

So you read the state by causing it to be spoken. If it is not the one you
wanted, do it again. That is full authority over all of them.

**Most of these have no key**, so the route is the Commands menu — `vo+h` twice,
type the name, Enter (see "Reaching an act that has no key" at the top). The
names below are what you type there.

**The toggles worth knowing**, out of the 45 — these are the ones that change how
an interface behaves under you, so they are the ones a session needs to be able
to name:

| What it changes | What the act is called |
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

**Three warnings, and the second one is about somebody's machine.** These are
toggles: they do not arrive at a state, they flip one, so pressing one twice
returns the machine to where it was and pressing one once leaves it changed for
whoever uses this computer next. And `mute voiceover toggle` and `toggle screen
curtain on or off` change what a *person* can perceive — never press either
without a reason you could defend to the person sitting there.

The third is about the last row. **The VoiceOver-modifier lock is invisible from
here.** When it is on the reader behaves as though VO were held down, so ordinary
letters become commands and your `vo+…` chords are not what a person's would be.
Nothing in this bridge can read that state. If ordinary keys start behaving like
reader commands, or your VO chords stop landing where they should, suspect it —
and note that pressing `vo+;` to find out would itself change it.

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
  cursor, press `vo+f3` and read the speech.
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
- **No account of what a chord DID.** `press_gesture` reports what it PRESSED and
  never what the reader made of it, which is the contract's own rule everywhere.
  Where that matters most is a chord that moves more than one thing:
  `kb:leftArrow+rightArrow` moves two Quick Nav settings and names neither, while
  `vo+q` and `vo+shift+q` each move one and say which way it went. If you meet an
  act you can reach neither by key nor through the Commands menu, say so: it is a
  gap worth recording rather than a thing to work around with `type_text`, which
  sends characters and not keys.
- **No reading of the person's own key bindings.** The keys in this document are
  the reader's factory bindings. If somebody has rebound a command in VoiceOver
  Utility this bridge does not know, and the key will simply do nothing. The
  Commands menu lists what this machine actually has, and the person at it can
  tell you.

## Your session was SET UP before you were handed it, and it will be PUT BACK

`connect_reader` does not merely open a channel here. Before it answers it reads
the permission this bridge needs — reads, never asks for; nothing here raises a
consent dialog — starts VoiceOver if it is not running, registers the
capture voice's extension if the system has forgotten it — restarting the reader
when it had to, because macOS publishes a newly registered voice no other way —
points the reader at that voice, and then makes the reader speak and requires the
words to arrive. If
any of that could not be done, **you get a named failure instead of a session** —
which step, what was wrong, and what you must do, usually "tell the person at this
machine to do X, then connect again".

Three consequences worth holding on to:

- **An empty `get_speech` now means the reader said nothing.** It used to be able
  to mean "this machine cannot capture at all", and the two were
  indistinguishable. They are not any more: a session that exists is a session
  whose capture was proved a moment ago. So an empty read is a fact about the
  interface you are testing, not a fault to go hunting for.
- **The first utterance of every session is not yours.** Index 1 holds what the
  reader said when the setup asked it for the time and date — real speech,
  recorded like any other. Your own first utterance is index 2. Take a bookmark
  with `get_next_speech_index` before you act, as you would anyway, and none of
  this matters.
- **The setup probe is `vo+f7`**, the time and date, which always speaks and moves
  nothing. It is pressed like anything else this bridge sends.

### What it changed on this person's machine, and what puts it back

**Exactly one setting: the voice VoiceOver speaks with.** It is on the capture
voice for the duration, and the person's own is restored when your session ends —
however it ends, including a watchdog firing or a failed handshake.

**Nothing else of theirs is touched.** In particular this bridge does **not**
change the VoiceOver modifier. It was going to: on a machine where `vo` is bound
to Caps Lock alone this bridge cannot press it, so the plan was to borrow
Control-Option for the session. VoiceOver turns out to watch that key and put a
modal question on screen when it changes — measured 2026-09-02 — so the borrow was
withdrawn. On such a machine there is **no session at all**, and the connect says
so and names what a person would have to change. It is a real gap and it is known.

**And this bridge asks nothing of VoiceOver's "Allow VoiceOver to be controlled
with AppleScript" switch.** It used to need it, for the command-name route that no
longer exists. If the person at this machine has it off, that costs you nothing;
if they have it on, nothing here uses it, and they can turn it off.

**If a session dies without tearing down**, the voice change is recorded in
`~/Library/Logs/screen-readers-mcp/reader-changes.jsonl` — one line per change,
one per restore. Anything with no matching restore is still changed.
`python3 scripts/voiceover_restore.py` reports what is open and puts back what can
be put back. Say so to the person at the machine if you ever see a connect fail
after the voice step; it is the difference between a five-second fix and an
afternoon.

### The bridge may restart the reader now, for one named reason only

That reason is: the capture voice was registered a moment ago, and macOS publishes
a newly registered voice only after VoiceOver restarts. In practice that happens to
whoever has just rebuilt this bridge, and to nobody else. It never restarts
speculatively, it always announces first through its own synthesizer — which you
can hear even in a silent session — and it quits, waits for the process to be gone,
and *then* starts it.

**That last part matters if you are ever telling a human to do it by hand.**
`killall VoiceOver && open -a VoiceOver` looks right and is not: `killall` returns
when the signal is sent rather than when the process is gone, so `open` can fire
into a reader the system still believes is running and do nothing at all. What a
person actually presses is **Command-F5**, twice.

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
