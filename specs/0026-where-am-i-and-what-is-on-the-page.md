# 0026 — where am I, and what is on the page

Status: **drafted 2026-08-03, not agreed.** Board entry **11.13**. Comes out of
the same live run as [0024](0024-a-session-the-agent-can-hear.md) and
[0025](0025-one-round-trip-per-intention.md) — specifically, out of the step the
run never reached.

---

## Part 1 — two questions of very different size

An agent driving a reader asks two questions constantly, and the repo has been
treating them as one:

1. **"Where am I?"** — one line. Cheap, frequent, needed after almost every
   action.
2. **"What is on this page?"** — the whole document. Expensive, occasional, and
   currently **impossible at any reasonable cost.**

The first is already solved and this spec adds nothing to it. The second is the
worst round-trip ratio in the system.

### Question 1 is already a gesture, and that is the right answer

[0023](0023-drive-it-like-a-user.md) settled this in its Part 2, in the
maintainer's own description of how he works:

> Press `NVDA+Tab` — report the focused object — because the goal is to type, so
> the question is whether an edit has focus. This is *screen-reader operating
> knowledge*, the kind any competent user has.

"Where am I" is **a command you send the reader**, and its answer arrives on the
same channel as everything else. `NVDA+Tab` reports the focus; `NVDA+T` reports
the window title. Both are speech. With [0025](0025-one-round-trip-per-intention.md)'s
grace window they cost **one round trip**, answer included.

So: **nothing is built for question 1.** Not a `whereAmI` tool, not a focus
field on a result — 0023 rejected the latter by construction and 0025 declined
to overturn it. The primitive exists, it is a keystroke, and a user already
knows it. This section exists to say so explicitly, because "add a where-am-I
tool" is the obvious thing to propose and it is wrong for reasons already
written down.

### Question 2 has no answer at all

On 2026-08-03 the agent reached a search-results page and needed the titles of
the first three results. There was no way to get them:

- Quick-nav by heading (`h`) found nothing — the results were not headings, and
  in the event the keystrokes were not even reaching browse mode
  ([0024](0024-a-session-the-agent-can-hear.md) Part 1).
- Arrowing line by line costs **one round trip per line**. At the 5–12 s
  observed that afternoon, reading twenty lines is two to four minutes.
- `get_focus_info` reports one object, and is the wrong job entirely
  ([0023](0023-drive-it-like-a-user.md) Part 3).

The run ended without the three titles. Not because anything failed, but because
the cheapest available path was too expensive to walk.

**This is the one place where 0025's collapse does not help.** 0025 makes a step
cost one trip instead of three; it does not reduce the *number of steps*, and
reading a document is N steps by construction.

---

## Part 2 — the tension, and why it resolves differently than it looks

A bulk text dump is not what a user gets. [0023](0023-drive-it-like-a-user.md)'s
stance is that an agent orienting through the platform's model is testing the
platform, not the reader — and a document dump smells like exactly that.

But the smell is misleading, and the distinction is worth being precise about,
because it decides the design.

**Browse mode is already a flat text rendering.** NVDA's own translator comment
says so:

```python
# Translators: The mode that presents text in a flat representation
# that can be navigated with the cursor keys like in a text document
ui.message(_("Browse mode"))
```

The virtual buffer *is* the document as the user reads it: headings carry their
level, links carry `link`, form fields carry their role and state. Reading it is
not consulting the accessibility tree — it is reading **the same flat text the
user arrows through**, all at once instead of one line per keystroke.

Compare the thing 0023 actually forbade: `waitForFocus { role: "EDITABLETEXT",
appModule: "nvda" }` — vocabulary a blind user does not have, describing an
object model they never see. A page snapshot has neither property. Its content
is what the user reads; only the *delivery* differs.

That is the same test [0024](0024-a-session-the-agent-can-hear.md) draws for
config: **information may change channel; it may not change substance.** A
snapshot moves N keystrokes' worth of already-user-visible text into one
response. It adds nothing the user could not have read.

### The rejected alternative: capture a say-all

The maximally faithful design is to press `NVDA+downArrow` — a real user
gesture — and return everything it speaks. It was considered and is **not**
proposed, for two reasons:

- **Its behaviour under suppression is unknown.** Say-all is driven by the
  speech manager's callbacks as each utterance completes. A silent session
  suppresses at the `speak()` filter ([0008](0008-transparent-silent-capture.md))
  so no synth ever runs, and whether say-all advances at all — let alone at what
  rate — has never been tested. Designing on it would be guessing, and this repo
  spent 2026-08-03 learning what that costs.
- **Its cost is proportional to the document even when it works.** Reading a long
  page would take real seconds of reader time inside the call, which is the
  problem restated rather than solved.

It stays on the table as a *verification* of the snapshot — if say-all under
suppression turns out to work, comparing the two is a good test that the
snapshot renders what NVDA would actually say. See *Open questions*.

---

## Part 3 — what ships

### `getPageSnapshot` — the browse-mode document, as lines

Gated on a new `document` capability, so a bridge that has no concept of a
browse document simply does not advertise it
([0005](0005-multi-reader-direction.md)).

```jsonc
// getPageSnapshot { fromLine?: 0, maxLines?: 200, maxChars?: 20000 }
{
  "hasDocument": true,
  "title": "Você pesquisou por nvda - BlindTec",
  "lines": [
    { "line": 0, "text": "mesma página link Skip to content" },
    { "line": 1, "text": "bâner marco título nível 1 mesma página link BlindTec" }
  ],
  "fromLine": 0,
  "toLine": 2,
  "truncatedBy": "maxLines"     // "maxLines" | "maxChars" | null
}
```

Four decisions, each of which is this repo repeating itself on purpose:

**Lines, not a blob.** [0021](0021-observing-the-log.md) made exactly this change
to `SpeechResult` — *"A **list, not a joined blob**: the blob welded every
utterance into one string, so there was nowhere to hang a per-utterance
`logPosition`"*. Same reasoning: a line needs a coordinate so an agent can say
*the third result is at line 14* and act from there.

**`truncatedBy` names the cause, and `null` is a real answer.** Not
`truncated: true`. 0021's finding was that *aged out* and *capped* are different
bugs — one is fixed by asking again, one is not. Here: capped by line count,
capped by character budget, or the document simply ended. Three situations, so
three values, so no agent has to guess whether asking again would help. The
maintainer raised the size concern directly — *"The amount of text could be
big"* — and this is the honest form of the answer: bounded by default,
paginated, and explicit about which bound bit.

**`hasDocument: false` rather than an empty list.** A focus with no
`treeInterceptor` — a dialog, the desktop, a native app — is not an empty
document. Collapsing those two is the defect this repo has now cured four times
(0020, 0021, 0023, 0024); it is not going to be introduced deliberately in a new
tool.

**Rendered as browse mode presents it, roles and all.** `link`, `título nível 1`,
`marco` stay in the text. Stripping them would produce something no user hears
and would quietly turn the snapshot into a different, worse thing than the
document. It also keeps the snapshot searchable by the same words that come back
from `getSpeech`, which is what makes "find the first three results" tractable.

### What it does *not* include

No `activate(line)`, no "move the cursor here". Acting on a line is done the way
a user does it — arrow to it, or `control+F`, or quick-nav — and adding a jump
primitive would make the snapshot an alternative navigation model rather than a
way of reading. That is the point at which the 0023 objection *would* start to
bite.

---

## Class/file layout

Per AGENTS.md, "a spec MUST include the class/file layout".

| File | Role | Collaborators |
|---|---|---|
| `bridges/.../domain/ports/document_reader.py` (new) | **port** — `snapshot(from_line, max_lines, max_chars) -> DocumentSnapshot \| None`; `None` means "no browse document here". Speaks lines and ints, never NVDA types. | Implemented by the NVDA adapter; called by the handler. |
| `bridges/.../adapters/nvda_document_reader.py` (new) | **adapter** — `api.getFocusObject().treeInterceptor`, `makeTextInfo(textInfos.POSITION_ALL)`, split into lines with the same rendering browse mode uses. The only file that knows what a virtual buffer is. | Built by `AdapterFactory`; sits beside `nvda_state_inspector.py`, which already reads `treeInterceptor.passThrough`. |
| `bridges/.../domain/entities/document_snapshot.py` (new) | **entity** — the line list plus the truncation reason; owns the budgeting, so "which bound bit" is decided in one testable place rather than in the adapter. | Pure; no ports. |
| `bridges/.../domain/controllers/commands/get_page_snapshot.py` (new) | **command handler** — `mutates_reader = False`, so an observe-only session ([0017](0017-observe-only-control.md)) may call it. | `ctx.adapter_set.document_reader`. |
| `bridges/.../domain/controllers/commands/registry.py` | controller (existing) | Registers the handler. |
| `bridges/.../domain/ports/adapter_factory.py` + `adapters/nvda_adapter_factory.py` | port/adapter (existing) | `AdapterSet` gains `document_reader`. |
| `bridges/.../protocol.py` | wire (existing) | `PageSnapshotParams`, `PageSnapshotResult`, `SnapshotLine`, `TruncatedBy` enum; `document` added to `Capability`. |
| `server/domain/controllers/tools/get_page_snapshot.go` (new) | **controller** — capability-gated on `document`. Description states that this is the flat text a user arrows through, not a structural read, and that it is bounded. | `registry.go`, `tool_context.go`. |
| `server/domain/controllers/tools/registry.go` | controller (existing) | One entry. |
| `specs/wire/v1/protocol.md` | contract (existing) | New command documented; `PROTOCOL_VERSION` 1 is pre-release, so this is additive and costs a rebuild (AGENTS.md). |
| `bridges/nvda/tests/unit/domain/entities/test_document_snapshot.py` (new) | unit | Budgeting: capped by lines, capped by chars, ended naturally — and that a document ending exactly on a bound reports `null`, not a cap. |
| `bridges/nvda/tests/unit/.../test_get_page_snapshot.py` (new) | unit | `hasDocument: false` when the port returns `None`; pagination round-trips. |
| `bridges/nvda/tests/fakes/document_reader.py` (new) | fake | Deterministic pages for the handler tests. |
| `server/tests/integration/mcp_page_snapshot_test.go` (new) | integration | Tool absent without the `document` capability, present with it; shape reaches the agent. |

---

## What is deliberately not built

**A `whereAmI` tool.** Part 1. It is `NVDA+Tab`, and with 0025 that is one round
trip.

**Jumping to a line.** Part 3. It would make the snapshot a navigation model.

**Say-all capture.** Part 2 — deferred on unknown behaviour under suppression,
not on principle.

**A structural tree dump.** 0023's *Future direction* already claims this
territory for surveying an inaccessible application, and is explicit that it is a
*survey* tool rather than an orientation one. A flat browse-mode read and an
object tree are different products for different customers; merging them would
undo the distinction 0023 went to some length to draw.

**Braille snapshot.** The braille line is the observable for a deafblind user and
deserves the same treatment. Out of scope here for the same reason 0023 gave:
stated as a limit rather than guessed at.

## Honest limits

- **Only browse-mode documents.** Native applications, dialogs, the desktop, the
  Windows system menu — all `hasDocument: false`. Much of what an agent drives is
  not a web page, and for those the answer remains N keystrokes. This spec fixes
  the worst case, not the general one.
- **A snapshot is a moment.** Dynamic pages change under it; a live region that
  updates after the read is not in it, and nothing about the shape hints at that.
- **The rendering may not equal what say-all would speak.** The virtual buffer's
  text and NVDA's spoken presentation are produced by related but not identical
  paths. The snapshot is *close* to what the user hears, and calling it identical
  would be a claim this spec has not earned.
- **Bounded by default means incomplete by default.** An agent that ignores
  `truncatedBy` will silently read the first 200 lines of a long page and believe
  it has the page. The field is the mitigation; it is not a guarantee.

## Open questions

- **Does say-all advance under a silent session?** Directly testable on the
  current build, cheap, and it decides whether the say-all comparison test in
  Part 2 is available at all. Worth doing *before* this is agreed, since a
  working say-all would also be a second implementation to check the snapshot
  against.
- **Are the defaults right?** 200 lines / 20 000 chars are guesses. The
  BlindTec results page is the obvious calibration sample.
- **Should `title` be there?** It duplicates what `NVDA+T` reports, which under
  0025 is one round trip anyway. Cheap, and it saves the trip on the one call
  where the agent is already asking about this document.
- **Is `getPageSnapshot` the right name?** It is the maintainer's word
  ("page snapshot"), which is a good reason. Against: it works on any browse-mode
  document, and "page" implies the web.
- **Does this deserve `sinceLine` semantics like the log's `sincePosition`?** For
  a page that grows — an infinite scroll, a chat log — reading only what is new
  is the same problem 0021 solved for the journal. Probably a later entry, but
  the shape should not foreclose it.

## Not in scope

Making capture complete ([0024](0024-a-session-the-agent-can-hear.md)) and the
cost of a single step ([0025](0025-one-round-trip-per-intention.md)). This spec
is about the number of steps needed to read something, which neither of those
touches.
