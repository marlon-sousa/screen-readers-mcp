# Spec 0049 — a key that is not a command

**Status:** **Decided and implemented** — board entry 13.19, 2026-08-31. §2.1's
choice between `key:` and `kb:` was Marlon's, in conversation, along with the
instruction that shaped §2.3; the amendments made while implementing are recorded
in §7 with their reasons, as the workflow requires.

**Board entry:** [13.19](../ROADMAP.md), lane 3. **A v1 blocker for the `user`
persona**, for the same reason [spec 0048](0048-pressing-a-chord.md) was: it is
something an ordinary VoiceOver user does constantly and this bridge cannot
express.

**Found by:** Marlon, 2026-08-31, driving 13.17's own build:

> with single-key Quick Nav on, an ordinary VoiceOver user presses `h` to move by
> heading, and this bridge cannot express it.

**And the instruction that shaped the answer**, given in the same conversation
once the notation question was on the table:

> let's standardize the maximum we can with what nvda already does.

Which is why this spec is longer than the one-line fix it started as. The
notation question turned out to have a right answer already written down, in
`../nvda/source/vkCodes.py`, and once that is the rule it settles half a dozen
smaller questions this bridge had answered differently by accident.

## 1. The gap, exactly

13.17 made the `+` the whole discriminator between `pressGesture`'s two
notations, so an id with no `+` is one of VoiceOver's own English command names.
That is right for `return key` and `tab key` — commands the reader dispatches
itself for free — and it means a bare `h` is looked up as a command and refused:

    press_gesture { gestures: ["h"] }
    -> 'h' is not a gesture id on this reader: this reader has no command called 'h'

There is no way to ask for the letter key. Spec 0048 §8 amendment 5 said so in as
many words — *"a key with no modifier stays a COMMAND NAME"* — and gave a good
reason for it (the grant, §2.5 below). What it did not notice is that the rule
leaves a hole where the platform's own single-key navigation lives.

### 1.1 The capability exists and is reachable through the wrong tool

Measured in the same live run: `type_text "h"` **does** drive Quick Nav — it
moved to *"nível de título 1"* — because the Unicode-payload event reaches the
same place. So an agent can do it today by typing, which is precisely the
confusion the two notations were separated to prevent, and which the guidance
document currently contradicts in a sentence of its own: *"A key with NO modifier
is a command name, not a keystroke."*

That is the same shape as 0048 §1.1, one entry later: a true statement about one
route generalised into a claim about the bridge, with a working route sitting
next to it under a name that means something else.

## 2. Decisions

### 2.1 The prefix is `kb:`, and it is NVDA's rather than a new one

    press_gesture { gestures: ["kb:h"] }

A `key:` prefix was proposed by the board entry and considered here. It is
declined in favour of `kb:` because the contract already has a source-prefix
namespace and this is exactly the case it was reserved for.
[Spec 0018](0018-input-vocabulary.md) §"Compatibility and the reserved prefix"
says a source prefix is **reserved, not forbidden**, and that absent a prefix
means *keyboard* on NVDA. This reader is the first one where absent a prefix does
**not** mean keyboard — its unprefixed vocabulary is the reader's own commander —
so the prefix stops being redundant and starts doing work.

**What this costs, and it is the honest objection.** `protocol.md` §5 today calls
`kb:` a *legacy* prefix that an NVDA bridge merely tolerates, and says the
documented form is prefixless. Promoting it here means the shared contract
document has to stop saying that in the flat way it says it now. The amended
wording is in §3.4: the prefix names the **source** of an id, it is redundant on
a reader whose gesture notation is keystrokes and nothing else, and it is
load-bearing on a reader with two vocabularies. Both halves of that are true of
the two bridges we have, and neither is a schema change — gesture ids pass
through opaquely and `schema.json` is untouched.

**A new wire command was not considered**, for the reason 0048 §2.1 already
settled: this is the same command, and which route a bridge takes is the bridge's
business.

### 2.2 What the prefix does, precisely

`CommandVocabulary.classify` gains one step, ahead of everything it already does:

1. Trim. An empty id is refused as it is today.
2. **If the text before the first `:` has no space**, everything up to and
   including that colon is a **source prefix** — which is `bare_key_name`'s rule
   in lane 1, quoted rather than reinvented. (*As proposed this said "if the id
   has no spaces", which contradicts the paragraph below it — see §7.1.*)
   - `kb:` — the rest is a **keystroke**, whatever it looks like. No `+` is
     required, which is the whole point of the entry.
   - `kb(...):` — refused **by name**: this bridge has no keyboard layouts in
     NVDA's sense. The machine's own layout is read live at press time
     (0048 §2.4), so there is nothing for a qualifier to select.
   - anything else — refused **by name**, saying `kb` is the only source it
     knows.
3. Otherwise the rules are exactly today's: `VO-D` refused by name, a `+` with no
   space is a keystroke, everything else is a reader command name.

The space rule survives untouched and now guards the colon as well as the `+` and
the hyphen: a phrase is a command name whatever punctuation it contains.

**An explicit prefix outranks the shape of what follows it.** `kb:go to desktop`
is a malformed keystroke, not a command name — because the agent said which
vocabulary it meant and the answer to a mistake is to name it, not to guess past
it.

### 2.3 The standardization rule: a token this bridge accepts means the same key on NVDA

This is the load-bearing decision, and it is Marlon's instruction turned into
something checkable:

> **Every token this bridge accepts in a keystroke names, on NVDA, the same
> physical key it names here. Where NVDA's token names a DIFFERENT key, this
> bridge refuses it by name rather than pressing something.**

Read out of `../nvda/source/vkCodes.py` at `release-2026.1` on 2026-08-31 —
`byCode`, the map NVDA's own gesture names come from, lower-cased into `byName`
for lookup — rather than recalled. Today's table was written from macOS's key
labels and diverges from it in four places, **three of which fail on NVDA and one
of which silently presses the wrong key**:

| Today | On NVDA | Consequence |
|---|---|---|
| `return` | not a name at all (`enter` is) | `command+return` **fails** on lane 1 |
| `left`, `right`, `up`, `down` | `leftArrow`, … | `kb:down` **fails** on lane 1 |
| `pageup`, `pagedown` | `pageUp`, `pageDown` | parses either way — casing only |
| `delete` = the Mac's Delete, which erases **backwards** | `delete` = **forward** delete (0x2E); backwards is `backspace` (0x08) | the same id **presses a different key** on each reader, with nothing to see |

So the accepted vocabulary becomes NVDA's, with the Mac's own spellings kept as
synonyms wherever they are unambiguous:

| Key | Canonical (NVDA's name) | Also accepted |
|---|---|---|
| Return | `enter` | `return` |
| The Mac's Delete (erases backwards) | `backspace` | — |
| Forward delete | `forwardDelete` | — |
| Arrows | `leftArrow`, `rightArrow`, `upArrow`, `downArrow` | `left`, `right`, `up`, `down` |
| Paging | `pageUp`, `pageDown`, `home`, `end` | — |
| The rest | `space`, `tab`, `escape` | `esc` |
| Function row | `f1` … `f20` | — |

Parsing stays case-insensitive, so `downarrow` and `downArrow` are the same id;
the casing above is what `described` **emits**, which is what a transcript shows.

**Refused by name, each with the alternative it should have been:**

- **`delete`** — *"`delete` names a different key on each platform: this machine's
  Delete erases backwards (`backspace` here) and NVDA's Delete erases forwards
  (`forwardDelete`). Say which you meant — or send the reader's own `delete key`
  command, which erases backwards and costs no permission."* This is the one
  refusal that prevents a wrong key rather than a failed lookup, and it is the
  reason the whole rule is worth having.
- **`insert`** — a key this keyboard does not have. NVDA's users press it all day;
  there is nothing here to press.
- **`nvda`** as a modifier — *"there is no NVDA key on this machine. VoiceOver's
  modifier is Control-Option unless the person rebound it, and this bridge will
  not guess — send the reader's command name."* Which is the `VO-D` refusal's
  argument arriving through a different door.
- **`windows`** as a modifier — *"on this machine that key is `command`."*

`alt` is accepted as a synonym for `option` and is **not** refused, because it is
the same physical key under two labels — Apple prints both — so nothing can go
wrong with it. That is the line the rule draws: **a name that differs with no
hazard is tolerated; a name that differs with a hazard is refused.**

**The modifier ORDER needed no standardizing, and that is worth recording.**
NVDA's `press_order` writes `nvda, control, alt, shift, windows`; ours writes
`fn, control, option, shift, command`. Position for position they are the same
sequence with the platform's substitutions, arrived at independently. Nothing
changes here.

### 2.4 The canonical spelling carries the prefix exactly when dropping it would lie

`Gesture.described` is what the transcript line and the `pressed` entry report —
what the bridge **understood**, never an echo of what the agent typed (0048
§7.1). A keystroke with modifiers keeps today's prefixless spelling, which is
lane 1's documented form:

    "Command+L"      -> command+l
    "kb:command+l"   -> command+l
    "KB:H"           -> kb:h
    "kb:Down"        -> kb:downArrow

A modifier-free keystroke keeps the prefix, because **without it the line no
longer means what it did**: `h` fed back in is a command name, and a transcript
whose lines cannot be replayed is not doing its job. So the rule is *the prefix
appears exactly where it is load-bearing*, which is also the answer that keeps
the spelling identical to NVDA's everywhere it can be.

`Keystroke.described` stays the pure keystroke spelling and keeps its documented
round-trip through `Keystroke.parse`; the **gesture id** spelling is
`Gesture.described`'s, which is the type that knows about notation. Both doc
comments say so, because the split is exactly the kind of thing a later reader
would collapse.

### 2.5 The lazy-grant lever is untouched, and this time there is no sweep

13.8's claim, as 13.17 narrowed it:

> a session that presses only the reader's command names and reads speech never
> triggers an Accessibility request

`kb:h` is a keystroke, so it costs the grant exactly as `command+l` does, and
`return key` still costs nothing. The sentence stays true **word for word**, so
none of the forty places 0048 §8.6 had to rewrite are touched again. That is not
luck: it is what choosing a notation that lands inside the existing
classification buys, and it is the reason `kb:h` is better than making a lone
token mean a keystroke.

The guidance keeps saying it plainly: **prefer the command name when one exists**.
`kb:enter` and `return key` press the same key, and only one of them raises a
consent dialog on somebody's machine.

### 2.6 `type_text`'s remit is not widened — considered and declined

The alternative the board entry named. It is declined:

- `type_text` means *insert this literal text at whatever holds focus*
  (`protocol.md` §5). Quick Nav responding to it is a property of what happens to
  have focus, so **the same call is navigation in web content and a typed letter
  in a text field** — a difference the agent cannot see and did not ask for.
- It saves nothing. Both routes post system events and both cost the
  Accessibility grant.
- The transcript would record navigation as typing, and a run reconstructed from
  it would read as though the agent had typed `h` into a page.

What the guidance gains instead is one sentence saying that `type_text "h"` does
move Quick Nav, that this is not what it is for, and which call to use.

### 2.7 What is deliberately NOT standardized

- **Lane 1's modifier hoisting.** `press_order` exists to undo NVDA's own
  normalizer, which sorts a stored gesture's parts alphabetically — it is a
  workaround for an internal, not a leniency offered to agents. There is no such
  normalizer here, so `l+command` stays a **named failure** (0048 §7.3) rather
  than being silently reordered into `command+l`. A lenient parse would hide a
  typo in the one place a typo presses a key.
- **`alt` and `windows` as the canonical modifier names.** `option` and `command`
  are what this platform's keyboards, documentation and reader all say. §2.3's
  rule is about which **key** a token names, not about preferring Windows
  vocabulary on a Mac.
- **The numpad.** NVDA names twenty-odd numpad keys and binds most of its own
  commands to them; VoiceOver binds nothing there and nobody has asked. Adding
  them is a table and a day, whenever a measurement wants one.

## 3. Class/file layout

The review gate. Every file the implementing PR changes, with its role and its
collaborators. **No new files, and no adapter decisions change** — which is the
shape a notation entry should have.

### 3.1 Domain — `Sources/VoiceOverBridgeDomain/`

| File | Role | Change |
|---|---|---|
| `Entities/Keystroke.swift` | entity — **amended** | Parses a **single-token** keystroke (the `tokens.count >= 2` guard goes; the caller has already decided this is keystroke notation). Named-key vocabulary restated on NVDA's names per §2.3, with the Mac spellings as synonyms. `NamedKey` cases `.return` → `.enter` and `.delete` → `.backspace`, so the case name and the wire spelling stop disagreeing. `delete`, `insert`, `nvda` and `windows` each refused **by name** with their alternative. |
| `Entities/CommandVocabulary.swift` | entity — **amended** | The source-prefix step of §2.2, ahead of the existing rules. `Gesture.described` gains the load-bearing-prefix rule of §2.4. Both are notation decisions and this is the type that owns notation. |
| `Controllers/Commands/PressGesture.swift` | controller — **unchanged** | It routes on the classification and asks for the grant when any gesture `isKeystroke`. A prefixed bare key is a keystroke, so both behaviours are already right. Recorded here because "no change" is the reviewable claim. |

### 3.2 Adapters — `Sources/VoiceOverBridgeAdapters/`

| File | Role | Change |
|---|---|---|
| `CGKeystrokePresser.swift` | adapter — **rename only** | `namedKeyCodes` follows the two renamed `NamedKey` cases; the keycodes are the same three constants (`0x24`, `0x33`, `0x75`). It already handles an empty modifier set — `hold` and `release` iterate nothing and the `defer` is a no-op — so an unmodified press needs **no** new decision anywhere on this edge. |

### 3.3 Tests

| File | Tier | Asserts |
|---|---|---|
| `Tests/VoiceOverBridgeDomainTests/Entities/KeystrokeTests.swift` | unit — amended | a modifier-free keystroke parses; each NVDA name and each Mac synonym; the canonical casing `described` emits; `delete`, `insert`, `nvda`, `windows` each fail **by name** and the message names the alternative; `l+command` still fails |
| `Tests/VoiceOverBridgeDomainTests/Entities/CommandVocabularyTests.swift` | unit — amended | `kb:h` is a keystroke and `h` is still a command name; `kb:command+l` and `command+l` classify the same; `kb(laptop):h` and `xyz:h` refused by name; `kb:go to desktop` is a malformed keystroke rather than a command; the prefix appears in `described` only without modifiers |
| `Tests/Integration/SessionRoundTripTests.swift` | integration — amended | `kb:h` off a real wire reaches the **key presser** and not the AppleScript runner; the counting-broker scenario keeps its claim — a session of command names and speech reads is asked for nothing |

### 3.4 Documents

| File | Change |
|---|---|
| `Entities/Documents/common.md` | The false bullet (*"A key with NO modifier is a command name"*) rewritten; `kb:` and what it is for; the named-key table of §2.3 with both refusals; single-key Quick Nav named as the thing this is for; one sentence on `type_text "h"` (§2.6); the cross-reader note that `forwardDelete` is the one key with no shared spelling |
| `bridges/voiceover/AGENTS.md` | The discriminator paragraphs (the `+` is no longer the whole rule) and the standardization rule of §2.3, which is the part a future entry must not undo by accident |
| `specs/wire/v1/protocol.md` §5 | `kb:` restated as the contract's **source prefix**: redundant on a reader whose notation is keystrokes only, load-bearing on a reader with two vocabularies. Prose only — `schema.json` is untouched and `poe gates` is unaffected |
| `specs/0018-input-vocabulary.md` | One line in the reserved-prefix section pointing here: the reservation has been spent, and by which entry (invariant 6 — a Decided item is amended in the open) |
| `server/.../tools/press_gesture.go`, `run_sequence.go` | *"modifier+key as that reader's own guidance spells it"* is now false for two of this reader's three id shapes. Reworded to say the notation is the reader's and to read it from `screenreader://reader-guidance`. **Descriptions only — no parameter or result changes**, so no reconnect is required for correctness; a reconnect only refreshes the wording |
| `scripts/live_pages/README.md` | `snapshot-test.html` gains a row: it serves this entry's Quick Nav item, because it already carries heading levels |
| `ROADMAP.md` | 13.19 → **Done**, and the next-free-number line |

### 3.5 Instrument

| File | Change |
|---|---|
| `scripts/voiceover_chords.sh`, `scripts/voiceover_chord_press.swift` | A `key` mode: press an **unmodified** letter into the scratch document and assert exactly one character arrived, then assert the keyboard is clean — the same shape the chord probe already uses, and the 2026-08-29 rule that a probe provoking a hazard must assert the hazard is gone. It proves the mechanical half (a no-modifier keycode press arrives, and holds nothing down); the Quick Nav half is a live checklist item, because it needs the reader, Safari and a page |

## 4. The live checklist this earns

Driven through the MCP tools against a real VoiceOver, `silent` session unless
stated:

1. **The entry's whole point.** Safari on `scripts/live_pages/snapshot-test.html`,
   single-key Quick Nav on: `press_gesture ["kb:h"]` moves by heading and the
   speech says so. This is the one check that can still fail on a fact nobody has
   measured — Quick Nav has been seen to answer a Unicode-payload event, and a
   keycode event is what a real key produces, so it should answer at least as
   well. If it does not, that is a finding and a new board entry, not a patch.
2. `press_gesture ["h"]` is still refused as a command name, and the message
   names `kb:h`.
3. `press_gesture ["kb:downArrow"]` and `["kb:down"]` both move, and `pressed`
   reports `kb:downArrow` for each.
4. `press_gesture ["kb:delete"]` is refused by name, and the message names
   `backspace`, `forwardDelete` and `delete key`.
5. `press_gesture ["return key"]` still works and a session that pressed only
   command names raised **no** Accessibility dialog.
6. A chord still works: `command+l` in Safari opens the location bar.
7. `bash scripts/voiceover_chords.sh` passes in both modes, and the keyboard is
   clean afterwards.

## 5. Honest limits

- **`forwardDelete` has no shared spelling.** NVDA calls that key `delete`, which
  this bridge refuses; there is no token that means forward-delete on both
  readers. §2.3's rule cannot fix a collision, only refuse to hide one — so a
  cross-reader script diverges on exactly this key, and the guidance says so.
- **The standardization is one-directional.** Every token accepted here means the
  same key on NVDA; the reverse is not true and is not attempted — NVDA accepts
  `insert`, the numpad and twenty-four function keys, none of which exist here.
- **A prefixed id is still opaque to the server.** Nothing above the bridge knows
  what `kb:` means, which is the contract working as designed and also why an
  agent that has not read this reader's guidance will not discover the notation on
  its own. That is what `screenreader://reader-guidance` is for, and
  `connect_reader` returns it in full.
- **What arrives is still not what was sent** (0048 §6). An application may
  swallow or reinterpret the key, and Quick Nav in particular is a mode the
  person can have off.

## 6. Open questions

None blocking. One worth naming: **should `kb:` become the documented form on
lane 1 too?** It is already tolerated there, and a contract whose two bridges
spell the same act identically is worth something. It is not this entry's to
decide — nothing in 13.19 needs it, and changing NVDA's documented form is a
lane-1 entry with its own live checklist.

## 7. Amendments made while implementing (2026-08-31), each with its why

1. **The space rule guards the SOURCE, not the whole id** — §2.2 said a colon
   counts as a prefix "if the id has no spaces", and two paragraphs later said an
   explicit prefix outranks what follows it. Those contradict: under the first,
   `kb:go to desktop` is a command name. The rule as built is that the text
   **before** the colon must have no space, which keeps a phrase a phrase and
   makes the malformed keystroke the malformed keystroke. **Checked on the machine
   rather than assumed**: none of the 415 entries in
   `SCRStringsToCommandsMap.scrconfig` contains a `:` — the same check the `+` had
   before it became a discriminator.
2. **The `NamedKey` enum CASES were renamed too**, not only the spellings they
   emit: `.left` → `.leftArrow`, `.pageUp` was already right, `.return` →
   `.enter`, `.delete` → `.backspace`. §3.1 named only the last two. Leaving the
   arrows as `.left` while `described` said `leftArrow` would have been a second
   spelling of the same key living in the code, which is how a canonical form
   stops being one. `CGKeystrokePresser`'s table follows; the keycodes are
   unchanged.
3. **The instrument needed no new mode.** §3.5 asked for a `key` mode in
   `voiceover_chord_press.swift`; `press` already took zero modifiers — the
   script's own control is `press delete` — so what 13.19 adds is the SHELL half's
   unmodified-letter section, which presses `h` into the scratch document and
   reads back what arrived. The Swift half's named-key table was restandardized
   onto NVDA's names in the same commit, because its header claims to carry the
   same table `CGKeystrokePresser` does and that claim has to stay true; the
   script's own `press delete` became `press backspace`.
4. **`h` was added to the fake layout** (`FakeKeyboardLayout.inventedLayout`,
   keycode 205), so the integration test presses the entry's own letter rather
   than a stand-in.
