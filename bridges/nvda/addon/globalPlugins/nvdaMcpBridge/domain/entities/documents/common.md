# Driving NVDA on Windows

This is NVDA's own account of how to work this reader, and of where the boundary
of the ordinary user's vocabulary falls **on NVDA specifically**. The stance you
are holding is normative and lives at `screenreader://guidance`; this document
instantiates it, and cannot redefine it.

Every gesture below is written exactly as `press_gesture` takes it -- NVDA's
user-guide key-combo notation, no prefix. Where NVDA's desktop and laptop
keyboard layouts differ, both are given, because a document that named only one
would be wrong on half the installations. **You cannot tell from here which
layout this machine uses.** If a gesture appears to do nothing, try the other
layout's form before concluding the command failed.

## The ordinary vocabulary on this reader

This is what the Windows accessibility contract assumes of an ordinary user, and
therefore what any interface is entitled to assume you have:

- `tab` and `shift+tab` -- move between controls.
- `upArrow`, `downArrow`, `leftArrow`, `rightArrow` -- move within one control: a
  list, a tree, a radio group, a menu, a tab strip.
- `space` -- check and uncheck a checkbox; press a button that has focus.
- `enter` -- activate the default control, or the focused button or link.
- `alt+downArrow` and `alt+upArrow` -- open and close a combo box. Its items are
  then chosen with the arrows.
- `escape` -- close a menu, a dialog or a popup without committing.
- `home`, `end`, `pageUp`, `pageDown` -- move within a list or a document.
- Typing, through `type_text`. Literal text into whatever holds focus; it does
  not press Enter and does not submit anything.
- First-letter navigation -- typing a letter in a list or menu jumps to the next
  item beginning with it. This is the operating system's behaviour, not NVDA's.
- Single-letter navigation in browse mode -- see below. It is inside the
  vocabulary, and a common mistake is to assume it is not.

## Browse mode and focus mode

In a web page or any other document NVDA can browse, NVDA starts in **browse
mode**: the arrows move a virtual cursor through the document rather than moving
system focus, and single letters jump between element types -- `h` for the next
heading, `k` link, `b` button, `e` edit field, `f` form field, `t` table, `l`
list, `d` landmark, and `shift` plus any of them for the previous one. `enter` or
`space` activates what the virtual cursor is on.

In **focus mode** keys go straight to the control, which is what an edit field or
a listbox inside the document needs. NVDA switches automatically when focus lands
on such a control, and `NVDA+space` toggles manually. NVDA plays a short sound
rather than saying which mode it entered, so **`get_state`'s `browseMode` is the
reliable way to know** -- and diffing two snapshots across a gesture is how a
mode switch is asserted at all.

All of this is ordinary reading and ordinary interaction. None of it routes
around anything.

## NVDA's reading commands

These re-read what is already in front of you. They make no claim about
reachability, so they are inside every persona's vocabulary:

| What it does | Desktop layout | Laptop layout |
|---|---|---|
| Report the focused object | `NVDA+tab` | `NVDA+tab` |
| Report the window title | `NVDA+t` | `NVDA+t` |
| Read the whole window | `NVDA+b` | `NVDA+b` |
| Report the current line | `NVDA+upArrow` | `NVDA+l` |
| Say all, from here | `NVDA+downArrow` | `NVDA+a` |

`NVDA+tab` is the *orient* step of the loop in `screenreader://guidance` on this
reader. Reach for it when what you heard after acting was not enough.

## The desktop's own keys

Getting the application under test in front of you is the desktop's job, not the
reader's, and this is the only document that can name the keys, because the
reader is what fixes the platform. NVDA runs on Windows, so:

- `windows+d` -- show the desktop.
- `windows` alone, or `windows+s` -- open the Start menu or search. Then
  `type_text` the application's name and `press_gesture` `enter`.
- `alt+tab`, `windows+tab` -- the window switchers.

**But mind the gesture limit, which bites hardest here.** A gesture is a discrete
press *and release*, so no modifier can be held down across several other keys.
`alt+tab` therefore switches to the previous window and lets go; pressing it
again switches straight back. **You cannot walk an `alt+tab` list with it.**
`windows+tab` is different only because its task view *stays open* after the keys
are released, so it can then be arrowed through one gesture at a time and
committed with `enter`.

**Prefer naming the application to cycling to it**: Start menu, type the name,
`enter`. Three ordinary calls, independent of how many windows are open, and
independent of the keyboard layout.

Then confirm by listening: `NVDA+t` reports the window title, and a window that
opens announces its own title without being asked. Do not confirm by counting
presses.

## What NVDA does not offer

Readers differ in what they *offer*, not merely in which keys they use for it, so
do not assume a facility exists because another reader has one.

- **There is no native "list the open windows" command.** JAWS has one; NVDA has
  none. Use the desktop's own switcher, above.
- There is no command that focuses an application by name. That is the desktop's
  job, and the point above is how it is done.

## Where the boundary falls on this reader

These are NVDA's ways of reaching a control that focus cannot reach. They are
listed **once**, here, because the list is a fact about NVDA and is the same for
every stance -- what differs is whether the stance you are holding may use it,
which your own section below says.

**Object navigation** moves NVDA's navigator object independently of system
focus, so it reaches controls the keyboard never lands on:

| What it does | Desktop layout | Laptop layout |
|---|---|---|
| Report the current navigator object | `NVDA+numpad5` | `NVDA+shift+o` |
| Move to the containing object | `NVDA+numpad8` | `NVDA+shift+upArrow` |
| Move to the first contained object | `NVDA+numpad2` | `NVDA+shift+downArrow` |
| Move to the previous object | `NVDA+numpad4` | `NVDA+shift+leftArrow` |
| Move to the next object | `NVDA+numpad6` | `NVDA+shift+rightArrow` |
| Move the navigator to the focus | `NVDA+numpadMinus` | `NVDA+backspace` |
| Move the focus to the navigator | `NVDA+shift+numpadMinus` | `NVDA+shift+backspace` |
| Activate the navigator object | `NVDA+numpadEnter` | `NVDA+enter` |
| Toggle simple review mode | `NVDA+numpad1` | `NVDA+pageDown` |

**The review cursor** reads the screen or the object's text independently of
where the caret is:

| What it does | Desktop layout | Laptop layout |
|---|---|---|
| Review the previous line | `numpad7` | `NVDA+upArrow` |
| Review the current line | `numpad8` | `NVDA+shift+.` |
| Review the next line | `numpad9` | `NVDA+downArrow` |
| Review from the top | `shift+numpad7` | `NVDA+control+home` |
| Say all with the review cursor | `numpadPlus` | `NVDA+shift+a` |

Note the collision: `NVDA+upArrow` is *report the current line* on the desktop
layout and *review the previous line* on the laptop layout. The same gesture
string is inside the vocabulary on one layout and outside it on the other, which
is the sharpest reason to know which layout you are on before reasoning about the
boundary.

**Simulated clicks** press a control the keyboard never reached:

| What it does | Desktop layout | Laptop layout |
|---|---|---|
| Left mouse click | `numpadDivide` | `NVDA+[` |
| Right mouse click | `numpadMultiply` | `NVDA+]` |
| Move the mouse to the navigator object | `NVDA+numpadDivide` | `NVDA+shift+m` |

And **introspection** -- `get_focus_info`, `get_state`, `get_config`,
`get_log` and the other log tools -- reads NVDA's own model rather than pressing
anything. It reaches nothing and moves nothing, so it is not on this list at all;
what it is *for* differs by stance, and your section says so.
