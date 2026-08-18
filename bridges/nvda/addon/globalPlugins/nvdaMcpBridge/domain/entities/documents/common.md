# Driving NVDA on Windows

This is NVDA's own account of how to work this reader, and of where the boundary
of the ordinary user's vocabulary falls **on NVDA specifically**. The stance you
are holding is normative and lives at `screenreader://guidance`; this document
instantiates it, and cannot redefine it.

**Every gesture table below was read out of NVDA itself, on this machine, at the
moment you asked for this document.** They are not NVDA's published defaults and
they are not copied from the User Guide: they are what is bound here and now,
including anything the person at this machine has remapped, and already narrowed
to the keyboard layout in use. Use them, not what you remember about NVDA.

Each gesture is written exactly as `press_gesture` takes it. They are lower-cased
and their parts are sorted, because that is the literal form NVDA has bound;
`press_gesture` accepts them verbatim, so a cell of a table can be pasted
straight into a call.

Two honest limits. The tables are a **snapshot**: NVDA can rebind per
configuration profile, and profiles can switch when focus moves to another
application, so a long session can outlive its own document — read it again if
you have reason to think the machine changed under you. And they cover **keyboard
gestures only**: a command bound to touch or to a braille display is not shown,
because `press_gesture` sends keystrokes and listing one would be telling you
about something you cannot do.

For anything beyond the boundary this document draws, the
[NVDA User Guide](https://www.nvaccess.org/files/nvda/documentation/userGuide.html)
is the reference. This document does not restate it, and deliberately: it says
what a stance may and may not do, and which of *this machine's* commands those
are.

## The ordinary vocabulary on this reader

This is what the Windows accessibility contract assumes of an ordinary user, and
therefore what any interface is entitled to assume you have. **None of it is
NVDA's to rebind** — these are the operating system's and the toolkit's, which is
why they are stated here rather than resolved:

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

## Browse mode and focus mode

In a web page or any other document NVDA can browse, NVDA starts in **browse
mode**: the arrows move a virtual cursor through the document rather than moving
system focus, and single letters jump between element types -- `h` for the next
heading, `k` link, `b` button, `e` edit field, `f` form field, `t` table, `l`
list, `d` landmark, and `shift` plus any of them for the previous one. `enter` or
`space` activates what the virtual cursor is on.

**Single-letter navigation is inside the vocabulary**, and assuming otherwise is
a common mistake: it is how a user reads a document, not a way around a broken
one. Those letters are NVDA's own and can in principle be remapped, and unlike
the tables below they are not resolved here — they belong to the browse-mode
document rather than to NVDA globally, so they exist only while you are in one.
If a quick-navigation key does nothing, check with `get_state` that you are in
browse mode at all before concluding it was remapped, and consult the User Guide.

In **focus mode** keys go straight to the control, which is what an edit field or
a listbox inside the document needs. NVDA switches automatically when focus lands
on such a control, and it plays a short sound rather than saying which mode it
entered — so **`get_state`'s `browseMode` is the reliable way to know**, and
diffing two snapshots across a gesture is how a mode switch is asserted at all.

## NVDA's reading commands, as bound here

These re-read what is already in front of you. They make no claim about
reachability, so they are inside **every** persona's vocabulary:

{{gestures:reading}}

The first of them is the *orient* step of the loop in `screenreader://guidance`
on this reader. Reach for it when what you heard after acting was not enough.

## The desktop's own keys

Getting the application under test in front of you is the desktop's job, not the
reader's, and this is the only document that can name the keys, because the
reader is what fixes the platform. NVDA runs on Windows, so:

- `windows+d` -- show the desktop.
- `windows` alone, or `windows+s` -- open the Start menu or search. Then
  `type_text` the application's name and `press_gesture` `enter`.
- `alt+tab`, `windows+tab` -- the window switchers.

These are Windows' own and NVDA does not bind them, which is why they are stated
rather than resolved.

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

Then confirm by listening: the report-title command above, and a window that
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
listed **once**, here, because the list is a fact about this machine and is the
same for every stance -- what differs is whether the stance you are holding may
use them, which your own section below says.

Each table is **everything NVDA itself classifies** under that heading, so a
command NVDA gained since this document was written appears here anyway. If a row
says nothing is bound, that command genuinely cannot be reached on this machine.

**Object navigation** moves NVDA's navigator object independently of system
focus, so it reaches controls the keyboard never lands on:

{{gestures:object-navigation}}

**The review cursor** reads the screen, or an object's text, independently of
where the caret is:

{{gestures:text-review}}

**Simulated clicks and mouse movement** press or point at a control the keyboard
never reached:

{{gestures:mouse}}

A gesture can appear in more than one of these tables, or in a reading table and
a boundary table at once, if this machine binds it twice. Where that happens the
*command* is what decides which side of the boundary you are on, not the key --
so read the row, not just the keystroke.

And **introspection** -- `get_focus_info`, `get_state`, `get_config`, `get_log`
and the other log tools -- reads NVDA's own model rather than pressing anything.
It reaches nothing and moves nothing, so it is not on these lists at all; what it
is *for* differs by stance, and your section says so.
