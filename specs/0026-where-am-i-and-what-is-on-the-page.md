# 0026 — where am I, and what is on the page

Status: **drafted 2026-08-03; revised and AGREED 2026-08-22**, implemented in
the same PR. Board entry **11.13**. Comes out of the same live run as
[0024](0024-a-session-the-agent-can-hear.md) and
[0025](0025-one-round-trip-per-intention.md) — specifically, out of the step the
run never reached.

**What the 2026-08-22 revision changed**, so a reader of the earlier draft knows
what to re-read:

1. **The whole buffer is the default.** The draft capped every read at 200 lines
   / 20 000 chars. It no longer does: a call with no parameters returns the
   entire document. Bounds survive only as something the *agent* asks for, and
   the risk of asking for less is now written into the contract rather than left
   for the agent to work out.
2. **The say-all alternative is settled, not deferred.** The draft rejected it
   on an untested assumption, which was then tested twice and found wrong (board
   entry 11.13). It is now rejected on the design, with the assumption
   corrected.
3. **The rendering path is named.** The draft said "split into lines with the
   same rendering browse mode uses", which is not something the buffer's text can
   give you. Part 4 names the NVDA function, and the side effect it has unless
   you stop it.
4. **`capturedAt` exists** and the snapshot says out loud that it is one instant.
5. **The name is `getDocumentSnapshot`**, not `getPageSnapshot`.
6. **`truncatedBy` has no null**, on 0015's doctrine.

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
written down. The maintainer restated it on 2026-08-22 in exactly those terms —
*"the where am I is solved"* — so it is settled twice over.

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
object model they never see. A document snapshot has neither property. Its
content is what the user reads; only the *delivery* differs.

That is the same test [0024](0024-a-session-the-agent-can-hear.md) draws for
config: **information may change channel; it may not change substance.** A
snapshot moves N keystrokes' worth of already-user-visible text into one
response. It adds nothing the user could not have read.

**This is why the snapshot is not stance-gated.** `get_focus_info` and
`get_state` are qualified per persona in the guidance, because they read a model
the person does not have. This reads what the person reads, so `user`,
`validator` and `expert` may all call it and the guidance says so without a
caveat. What changes by stance is only *when it is the right move* — Part 6.

### The rejected alternative: capture a say-all

The maximally faithful design is to press `NVDA+downArrow` — a real user gesture
— and return everything it speaks. The 2026-08-03 draft deferred it on the
grounds that its behaviour under a silent session was unknown. **That question
has since been answered, twice, and the draft's supporting claim was wrong**
(board entry 11.13):

- The 2026-08-18 run said say-all stops after two chunks under suppression. The
  *observation* was real; the cause named for it was ours, not NVDA's. Silent
  mode returned an empty sequence from `filter_speechSequence`, which deleted
  the `CallbackCommand` NVDA inserts at position 0 of every say-all chunk to
  clock the next one.
- PR #64 fixed it by running the non-audible callbacks ourselves. The re-run the
  same day read a heading, thirty paragraphs and a closing line **complete, in
  328 ms**, carrying the caret with it.

So say-all works, and the honest form of this section is that it is rejected on
the design rather than on a defect:

- **It moves the caret.** Say-all carries the review position through the
  document and leaves it at the end. An agent that reads the page has then also
  navigated it, and the next gesture starts somewhere it did not choose. A
  snapshot moves nothing.
- **It produces utterances, not lines.** What comes back is chunks the way the
  speech pipeline emitted them, with no line coordinate to hang on them — so
  "the third result is at line 14" is not expressible, and that coordinate is
  most of what makes the answer actionable.
- **It costs reader time proportional to the document**, inside the call, and it
  occupies the reader while it runs. The snapshot costs one render.
- **It is already available.** An agent can press `NVDA+downArrow` today and read
  the speech, because 11.21 taught `waitForSpeechToFinish` to see a continuous
  read. Nothing here removes that, and for "what does this page sound like" it
  remains the more faithful instrument.

It also remains the best **verification** of the snapshot: two independent
renderings of the same document, one through the speech pipeline and one through
`getTextInfoSpeech`, should say very nearly the same words. That comparison is on
the live checklist rather than in CI, because only a live NVDA has a document to
compare.

---

## Part 3 — what ships

### `getDocumentSnapshot` — the browse-mode document, as lines

Gated on a new `document` capability, so a bridge that has no concept of a browse
document simply does not advertise it
([0005](0005-multi-reader-direction.md)). MCP tool name: `get_document_snapshot`.

**The name is not `getPageSnapshot`.** "Page snapshot" is the maintainer's own
phrase and was the draft's name for that reason. It loses to accuracy: the thing
this reads is a virtual buffer, and a PDF in a reader, an email in Outlook, a
help viewer and a Kindle book all have one. "Page" would suggest the tool is for
the web and quietly discourage its use everywhere else it works.

```jsonc
// getDocumentSnapshot { }                                // the whole document
// getDocumentSnapshot { fromLine, maxLines, maxChars }   // opt in to less
{
  "hasDocument": true,
  "capturedAt": "2026-08-22 14:31:07.412",
  "title": "Você pesquisou por nvda - BlindTec",
  "lines": [
    { "line": 0, "text": "mesma página link Skip to content" },
    { "line": 1, "text": "bâner marco título nível 1 mesma página link BlindTec" }
  ],
  "fromLine": 0,
  "toLine": 412,
  "truncatedBy": "none"     // "none" | "maxLines" | "maxChars"
}
```

Six decisions, most of which are this repo repeating itself on purpose.

**The whole document by default.** `maxLines` and `maxChars` default to `0`,
meaning *no bound*, and the ordinary call carries no parameters at all. This
reverses the draft, on the maintainer's instruction of 2026-08-22: *"We need the
whole buffer, with heading, radio button, or all, rendered to the buffer directly
into the response, exactly how it appears on the buffer."* The draft's 200-line
default would have delivered the first 200 lines of the BlindTec results page and
an agent believing it had the page — *bounded by default means incomplete by
default*, which the draft listed as an honest limit and is better treated as a
defect.

**An agent may still ask for less, and is told what that costs.** `fromLine`,
`maxLines` and `maxChars` remain, because a document can be genuinely enormous
and an agent that knows it wants only the top of one should be able to say so.
What is new is that the contract states the hazard rather than leaving it to be
discovered: **two calls are two moments.** A document that changes between them —
an infinite scroll, a live region, a page still loading — yields a stitched read
that never existed as a single state of the page, and nothing in the result can
detect that. The whole-document call is the only one that returns a coherent
picture, so the parameters are for when an agent has decided that coherence is
not what it needs. That sentence is in the tool description, in the wire contract
and in the schema's field descriptions, in those words.

**Lines, not a blob.** [0021](0021-observing-the-log.md) made exactly this change
to `SpeechResult` — *"A **list, not a joined blob**: the blob welded every
utterance into one string, so there was nowhere to hang a per-utterance
`logPosition`"*. Same reasoning: a line needs a coordinate so an agent can say
*the third result is at line 14* and act from there. `line` is the buffer's own
line ordinal, so it survives `fromLine` — line 14 is line 14 whether or not the
read started at 0.

**`truncatedBy` names the cause, and `"none"` is a value rather than a null.** Not
`truncated: true`: 0021's finding was that *aged out* and *capped* are different
bugs, one fixed by asking again and one not. Here there are three situations —
capped by line count, capped by character budget, or the document ended — so
three values. **The draft made the third one `null`, and
[0015](0015-bridge-introspection.md) had already decided that question the other
way** for `browseMode`: when the absence *is* one of the answers it is a member
of the set, not a missing field, because `if not result.truncatedBy` must not be
how an agent asks. A document that ends exactly on a bound reports `"none"` — the
bound did not bite, it merely coincided.

**`hasDocument: false` rather than an empty list.** A focus with no
`treeInterceptor` — a dialog, the desktop, a native app — is not an empty
document. Collapsing those two is the defect this repo has now cured four times
(0020, 0021, 0023, 0024); it is not going to be introduced deliberately in a new
tool. This is also the maintainer's own condition: *"this should be returned only
if a virtual buffer exists."* When it is `false`, `lines` is empty, `title` is
`""`, `fromLine`/`toLine` are `0` and `truncatedBy` is `"none"` — and
`capturedAt` is still stamped, because the bridge did look, at a time, and found
nothing.

**Rendered as browse mode presents it, roles and all.** `link`, `título nível 1`,
`marco`, `botão de opção` stay in the text. Stripping them would produce
something no user hears and would quietly turn the snapshot into a different,
worse thing than the document. It also keeps the snapshot searchable by the same
words that come back from `getSpeech`, which is what makes "find the first three
results" tractable. Part 4 is how.

### `capturedAt` — a snapshot is one instant, and says so

A wall-clock stamp in the format `format_wallclock` already renders for
`emittedAt` and for `getLogPosition`'s `time` ([0028](0028-when-was-that-said.md)),
so it joins to `nvda.log` and to the session transcript by paste.

It is there for one reason: **the result must not read as a description of the
page, because it is a description of the page at 14:31:07.412.** The maintainer
named this directly — *"we must take care with dynamic stuff, and let it clear to
the agent that this is a strict picture of the moment."* Three things carry it,
and none of them is a mechanism:

1. the field, which makes the instant a fact on the result rather than an
   assumption;
2. the tool description, which says the snapshot is a still frame, that a live
   region which updated after the capture is not in it, and that the way to see
   change is to take another snapshot and compare;
3. the wire contract (§5) and the output schema, in the same words.

**What is deliberately not built here:** a change token, a content digest, or a
"the document is still loading" hint. Each was considered on 2026-08-22 and each
is a claim this spec cannot honestly make — a digest is something the agent can
compute from `lines` itself, and a busy hint would have to be right about what
"settled" means for an arbitrary web page. Prose plus a timestamp says exactly
what is true and no more.

### What it does *not* include

No `activate(line)`, no "move the cursor here". Acting on a line is done the way
a user does it — arrow to it, or `control+F`, or quick-nav — and adding a jump
primitive would make the snapshot an alternative navigation model rather than a
way of reading. That is the point at which the 0023 objection *would* start to
bite.

---

## Part 4 — how a line is actually rendered, and the side effect that must not happen

The draft said the adapter would split the document "into lines with the same
rendering browse mode uses". That is not something the buffer's text can give
you, and the difference decides whether the maintainer's requirement is met at
all.

**The buffer's raw text has no roles in it.** `makeTextInfo(POSITION_ALL).text`
returns content — *"Skip to content"*, *"BlindTec"* — with no `link`, no `heading
level 1`, no `radio button`. The roles are not text; they are `ControlField`
commands interleaved with the text, and the words for them are produced by NVDA's
speech layer from the user's own verbosity and document-formatting settings.

**So the snapshot renders through NVDA's own presentation path.**
`speech.speech.getTextInfoSpeech(info, ...)` is a **generator**: it yields the
speech sequences `speakTextInfo` would have spoken, and speaks nothing itself.
Called per line with `unit=textInfos.UNIT_LINE` and `reason=OutputReason.CARET`,
it produces, line by line, precisely the words the user hears when arrowing down
the document — under *their* configuration, which is the only definition of
"exactly how it appears on the buffer" that means anything.

Four properties of that choice, each of which is why it is the right one:

- **No synth runs and no speech is emitted.** `getTextInfoSpeech` does not call
  `speak()`, so nothing reaches `filter_speechSequence` or `pre_speechQueued`.
  The snapshot therefore does **not** appear in `getSpeech`, does not move the
  speech index, and does not disturb a `waitForSpeech` running against something
  else. Reading the document is invisible on the speech channel, which is what
  makes it an observation.
- **The caret does not move.** The adapter walks its own `TextInfo` with
  `move(UNIT_LINE, 1)` and never calls `updateCaret()` or `updateSelection()`.
  Where the user was before the snapshot is where they are after it. This is the
  property say-all cannot offer.
- **The control-field cache is carried across lines, exactly as arrowing does.** A
  single `SpeakTextInfoState` threaded through the whole walk means a list is
  announced *"list with 5 items"* once on entry and not repeated on every line —
  the same economy the user hears. A fresh cache per line would produce a
  technically complete but wildly verbose rendering nobody has ever heard.
- **And that cache must be OURS, and must start EMPTY.** Two requirements, and
  the constructor gives neither by itself. The second was **found by the live
  run on 2026-08-22** and is the reason this bullet has two halves:
  `SpeakTextInfoState(obj)` *seeds itself* from `obj._speakTextInfoState`, the
  user's live reading position. With the caret inside a list, a snapshot taken
  from the top rendered line 0 as *"fora de lista título nível 1 …"* — the
  exit-of-list transition from where the **user** was, welded onto the
  document's first line. The same unchanged page, snapshotted from two caret
  positions, returned two different texts, which directly contradicts what the
  result claims to be: a snapshot is the document at an instant, and must not
  also depend on where the person at the keyboard is standing. The adapter
  therefore clears the three caches after constructing the state, rendering the
  document **as it reads entered from the top** — which is what "the whole
  document" means, and what NVDA itself produces when a page loads and it reads
  the document out.

  The first half is the trap that belongs in the spec because it is invisible in
  review: `getTextInfoSpeech` calls
  `speakTextInfoState.updateObj()` — writing its cache back onto the document
  object as `_speakTextInfoState` — **unless `useCache` is an explicit
  `SpeakTextInfoState` instance** (`speech/speech.py`,
  `_getTextInfoSpeech_updateCache`). With the default `useCache=True` a snapshot
  would leave the user's real browse-mode context pointing at the end of the
  document, and their next arrow press would announce field boundaries that are
  not there. **The adapter constructs its own `SpeakTextInfoState(ti)` and passes
  it**, which is the difference between reading the document and altering the
  reader.

**A speech sequence is flattened by the rule the bridge already has.**
`_join_speech` in `speech_buffer.py` keeps the `str` parts and joins them with a
space, for a reason recorded there (`"Move" + "indisponível" + "m"` must not come
out as `Moveindisponivelm`). The snapshot needs the identical rule — a snapshot
line and a captured utterance must be comparable word for word, which is what
makes the say-all cross-check in Part 2 possible at all — so the function is
**extracted to its own module and shared**, on the precedent of 0028 extracting
`format_wallclock` for exactly this reason: two renderings of the same thing in
two files is a drift waiting to happen.

**One atomic pass on NVDA's main thread.** All NVDA reads are marshalled through
`run_on_main(block=True)` as every other adapter here does, and the *entire* walk
happens inside one such call. Not per line: a per-line hop would let the document
change under the read, and a snapshot stitched from many instants is the very
thing `capturedAt` promises it is not. The cost is that NVDA's main thread is
occupied for the duration of the render, which for a large document is the one
real price of "the whole buffer by default" — see *Honest limits*, and the live
checklist item that measures it.

---

## Class/file layout

Per AGENTS.md, "a spec MUST include the class/file layout".

### Shared wire

| File | Role | Collaborators |
|---|---|---|
| `shared/screenreader_wire/protocol.py` | wire (existing) | Adds `Command.GET_DOCUMENT_SNAPSHOT`, `Capability.DOCUMENT`, `TruncatedBy(StrEnum)` (`NONE`/`MAX_LINES`/`MAX_CHARS`), `SnapshotLine`, `DocumentSnapshotParams`, `DocumentSnapshotResult`, and the `COMMAND_SHAPES` entry its coverage test requires. |
| `shared/tests/unit/test_protocol.py` | unit (existing) | The new shapes round-trip; `COMMAND_SHAPES` still covers every `Command`. |
| `specs/wire/v1/protocol.md` | contract (existing) | §4's capability table gains `document`; §5 documents the command, including the two-calls-are-two-moments rule. |
| `specs/wire/v1/schema.json` | generated (existing) | Regenerated by `schema.py`; `poe gates` is what proves it was. |

### Bridge (lane 1)

| File | Role | Collaborators |
|---|---|---|
| `domain/entities/speech_text.py` (new) | **supporting pure function**, not a class — `join_speech(sequence)`, moved out of `speech_buffer.py`'s private `_join_speech`. | Used by `SpeechBuffer` and by `NvdaDocumentReader`. Precedent: `wallclock.format_wallclock` (0028). |
| `domain/entities/speech_buffer.py` | entity (existing) | Loses its private copy of the join; imports the shared one. No behaviour change. |
| `domain/entities/document_snapshot.py` (new) | **entity** — the accumulating snapshot. `offer(text) -> bool` (False = full, stop asking), owning `from_line`, `max_lines`, `max_chars`, the collected lines, `to_line` and `truncated_by`. Pure, no ports. **All budget arithmetic lives here**, so "which bound bit, and did a document that ended exactly on a bound get called truncated" is decided in one testable place rather than inside an NVDA adapter. | Constructed by the handler from the request params; filled by the adapter. |
| `domain/ports/document_reader.py` (new) | **port** — `read(snapshot: DocumentSnapshot) -> DocumentRead \| None`; `None` means "no browse document here". Its DTO `DocumentRead` (just `title`) lives in the same file, per the one-port-per-file rule. Speaks the entity and strings, never NVDA types. | Implemented by the NVDA adapter and by the fake; called by the handler. |
| `adapters/nvda_document_reader.py` (new) | **adapter** — implements `DocumentReader`. The only file that knows what a virtual buffer is: `api.getFocusObject().treeInterceptor`, the `DocumentTreeInterceptor` + `isReady` check, `makeTextInfo(POSITION_FIRST)`, per-line `expand(UNIT_LINE)` → `getTextInfoSpeech(..., useCache=<own SpeakTextInfoState>, unit=UNIT_LINE, reason=CARET)` → `join_speech` → `snapshot.offer(...)` → `move(UNIT_LINE, 1)`. One `run_on_main(block=True)` around the whole walk. Never speaks, never moves the caret, never lets `updateObj` fire. On pyright's ignore list, like every NVDA-importing adapter. | Built by `NvdaAdapterFactory`; sits beside `nvda_state_inspector.py`, which already reads `treeInterceptor.passThrough`. |
| `domain/controllers/commands/get_document_snapshot.py` (new) | **command handler** for `getDocumentSnapshot`. `mutates_reader = False`, so an observe-only session ([0017](0017-observe-only-control.md)) may call it. Builds the `DocumentSnapshot` from params, hands it to the port, stamps `capturedAt` from the `Clock`, maps to the wire result. | `ctx.adapter_set.document_reader`, the `Clock`, `wallclock.format_wallclock`. |
| `domain/controllers/commands/registry.py` | controller (existing) | One entry. Its enumeration test is what makes a forgotten registration visible. |
| `domain/ports/adapter_factory.py` | port (existing) | `AdapterSet` gains `document_reader`. |
| `adapters/nvda_adapter_factory.py` | adapter (existing) | Builds `NvdaDocumentReader` in **both** capture modes — the read involves no speech, so live and silent are identical here. |
| `tests/fakes/document_reader.py` (new) | fake | Subclasses the ABC; scripted documents (empty, one line, long, none at all) for the handler tests. |
| `tests/unit/domain/entities/test_document_snapshot.py` (new) | unit | Unbounded by default takes everything; `maxLines` bites; `maxChars` bites; `fromLine` skips and `line` ordinals stay absolute; a document ending exactly on a bound reports `"none"`; a `maxChars` smaller than the first line still returns that line rather than nothing. |
| `tests/unit/domain/entities/test_speech_text.py` (new) | unit | The join rule, moved with the function. |
| `tests/unit/domain/controllers/commands/test_get_document_snapshot.py` (new) | unit | `hasDocument: false` when the port returns `None`, with the empty-but-stamped shape; `capturedAt` comes from the injected clock; params reach the entity. |

### Server (lane 2)

| File | Role | Collaborators |
|---|---|---|
| `server/domain/entities/capability.go` | entity (existing) | `CapabilityDocument`, in `All()`, and a `Meaning()` case — the gloss `screenreader://info` reports verbatim. |
| `server/domain/ports/document_reader.go` (new) | **port** — `DocumentSnapshot` struct + `DocumentReader` interface. The `document` capability group. | Implemented by `adapters/bridge/json_lines_client.go`. |
| `server/adapters/bridge/json_lines_client.go` | adapter (existing) | One more command call; handed out by the handshake when the reader announced `document`. |
| `server/adapters/wire/wire.gen.go` | generated (existing) | Regenerated from `schema.json`; `poe gates` proves it. |
| `server/domain/controllers/tools/tool_context.go` | controller (existing) | A `Document()` accessor, structured `CapabilityError` when absent. |
| `server/domain/controllers/tools/get_document_snapshot.go` (new) | **controller**, one per tool. Capability-gated on `document`. Its `Description()` and `OutputSchema()` carry the three things Part 3 requires an agent to be told: this is the flat text a user arrows through and not a structural read; it is one instant; and asking for a slice means two calls are two moments. | `registry.go`, `tool_context.go`. |
| `server/domain/controllers/tools/registry.go` | controller (existing) | One entry. |
| `server/adapters/mcp/documents/guidance-method.md` | document (existing) | A short section — Part 6. Remember `//go:embed` copies at compile time; `scripts/doctor.py` already counts these among the server's build inputs. |
| `server/tests/integration/mcp_document_snapshot_test.go` (new) | integration | Tool absent without the `document` capability, present with it; the result shape reaches the agent; `hasDocument: false` survives the round trip as a false rather than as an error. |
| `server/tests/conformance/...` | conformance (existing) | The real Go binary against the real Python bridge, per `poe conformance`. |

---

## Part 5 — what the live checklist must establish

**Run on 2026-08-22 against NVDA 2026.1.1, ibmeci, pt_BR. All ten items pass**,
and the run found one defect, fixed in the same PR: the caret-dependent
rendering in Part 4's fourth bullet. The results are recorded on the PR's
checkboxes; the two worth carrying here are that **the snapshot's words are
identical to what arrowing produces** (ten lines, compared one by one) and that
**item 9 answered in favour of the unbounded default** — a 1103-line document
rendered in no more time than a one-line one, within a two-second measurement
noise, with the reader responsive throughout.

Item 9 also produced the one change to the shipped surface the run argued for:
**the render is cheap, and the ANSWER is not.** 1103 lines is 60 KB of JSON,
which overflowed the calling agent's context budget and had to be spilled to a
file. That is not an argument for a default cap — the whole point of the
reversal is that a silent cap makes an agent believe a partial page is the page
— but it is a fact an agent should be told, so the tool description now names
`maxLines` as the remedy for a document already known to be huge.


**The pages are in [`scripts/live_pages/`](../scripts/live_pages/)**, versioned
with the checklist that needs them, so every item below can be re-run rather
than merely read. Their README says which page serves which item — and why they
are fixtures rather than golden files, since the rendering is the tester's own
locale and verbosity.

Everything above except the NVDA edge is unit-testable, and the edge is exactly
where this can be wrong. The implementing PR's body carries these as checkboxes,
per AGENTS.md:

1. **A web page renders with its roles.** Headings carry their level, links say
   `link`, and a **radio button says it is one, with its state** — the
   maintainer's own example, so the checklist uses a form page that has one.
2. **The rendering matches what the user hears.** Arrow down five lines with
   speech captured, and compare those five utterances to lines *n*..*n+4* of a
   snapshot. They should agree word for word; where they do not, the difference
   is recorded on the unchecked item and this spec is amended.
3. **The say-all cross-check.** `NVDA+downArrow` on the same document, captured
   per 11.21, against the snapshot. Part 2's second rendering.
4. **The caret did not move.** Note the review position, snapshot, press
   `downArrow`, and confirm it reads the line it would have read anyway.
5. **The user's browse-mode context is intact, and the snapshot does not depend
   on it.** The `updateObj` trap of Part 4: arrow through a list, snapshot, arrow
   again, and confirm the announcements are what they were — not a repeated or a
   swallowed field boundary. And the converse, which is what the 2026-08-22 run
   actually caught: snapshot the same unchanged page from two different caret
   positions and confirm the text is **identical**. It was not, the first time.
6. **Nothing appears on the speech channel.** `getNextSpeechIndex` before and
   after a snapshot returns the same index.
7. **Not a document, and it says so.** With focus on the Windows desktop and on
   an NVDA dialog: `hasDocument: false`, no error, `capturedAt` present.
8. **In focus mode too.** Inside a form field with `passThrough` on the buffer
   still exists, so `hasDocument` is `true` — this is not gated on the
   browse/focus tri-state.
9. **A long document, timed.** Something with hundreds of lines. Record the
   wall-clock cost of the whole-document call and whether NVDA felt frozen while
   it ran. **This is the number that decides whether an unbounded default is
   defensible**; if it is bad, the answer is a documented recommendation to the
   agent, not a silent cap that recreates the defect Part 3 removed.
10. **A dynamic page.** Two snapshots either side of a live region updating, so
    the `capturedAt` difference is a real observation rather than a decoration.

---

## Part 6 — what the guidance tells the agent

`screenreader://guidance`'s method document gains a short section, placed after
step 4 of *The loop* and before *When you already know the next few steps*,
saying roughly this:

- **Reading a document is not orienting.** The loop's step 3 answers "where am I"
  with the reader's own command. This answers "what is here", which is a
  different question and has never had a cheap answer.
- **It is one call for the whole document.** Not a page at a time, and not a
  keystroke per line.
- **It is a still frame.** Take another one to see change; do not assume the
  first is still true.
- **If you ask for a slice, you are asking for two moments.** Say plainly that a
  document which changes between calls yields a read that never existed.
- **Every stance may use it** — unlike the introspection tools, whose section
  qualifies them per persona (Part 2 says why).

It also fixes a smaller thing while the file is open: *Orient* mentions
"read-whole-window commands" as a way to hear a lot at once, and an agent reading
that today has no idea a document snapshot exists.

---

## What is deliberately not built

**A `whereAmI` tool.** Part 1. It is `NVDA+Tab`, and with 0025 that is one round
trip. Confirmed again by the maintainer on 2026-08-22.

**Jumping to a line.** Part 3. It would make the snapshot a navigation model.

**Say-all capture as a tool.** Part 2 — and note this is now a *design*
rejection, with the draft's factual premise corrected. Say-all remains available
as a gesture and remains the cross-check.

**A change token, digest or busy hint.** Part 3. `capturedAt` plus prose says
what is true; the rest would be claims we cannot keep.

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
  not a document, and for those the answer remains N keystrokes. This spec fixes
  the worst case, not the general one.
- **A snapshot is a moment.** Dynamic pages change under it; a live region that
  updates after the read is not in it. `capturedAt` and the prose are the
  mitigation, and they are a mitigation, not a guarantee.
- **A sliced read is several moments.** The parameters exist and the contract
  warns about them; an agent that paginates a changing document gets a stitched
  picture and nothing in the result can tell it so.
- **The whole document occupies NVDA's main thread while it renders.** One atomic
  pass is what makes the snapshot coherent, and the price is that the reader is
  busy for its duration. Checklist item 9 is the measurement; until it exists,
  the cost of a very large document is unknown rather than small.
- **The rendering is very close to what say-all would speak, and not provably
  identical.** Both go through NVDA's speech layer, which is why they should
  agree, but the pipelines diverge after that point. Checklist items 2 and 3
  measure the gap rather than assuming it away.
- **It renders under the user's configuration.** That is the point — but it means
  two machines can snapshot the same page and get different words, exactly as two
  users hear different words. An agent comparing snapshots across machines is
  comparing renderings, not documents.

## Settled since the draft

The draft's open questions, and where each landed:

- **Does say-all advance under a silent session?** Yes, since PR #64. Part 2.
- **Are the defaults right?** There are no size defaults any more. Part 3.
- **Should `title` be there?** Yes. It is one field, it costs nothing on a call
  the agent is already making about this document, and it saves the `NVDA+T`
  trip. Best-effort: empty when the document has no name.
- **Is `getPageSnapshot` the right name?** No — `getDocumentSnapshot`. Part 3.
- **Does this deserve `sinceLine` semantics like the log's `sincePosition`?** No,
  and now for a reason rather than as a deferral: the journal grows by append and
  a document does not. Lines are *rewritten* in place, so "everything after line
  40" is not the same claim as "everything after position 40" and would mislead
  precisely on the dynamic pages it would be reached for. The shape does not
  foreclose it; nothing here should be built on the assumption it is coming.

## Not in scope

Making capture complete ([0024](0024-a-session-the-agent-can-hear.md)) and the
cost of a single step ([0025](0025-one-round-trip-per-intention.md)). This spec
is about the number of steps needed to read something, which neither of those
touches.
