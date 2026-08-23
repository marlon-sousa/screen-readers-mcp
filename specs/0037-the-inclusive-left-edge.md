# 0037 — the inclusive left edge

Status: **drafted 2026-08-23, awaiting agreement.** Board entry **11.29**, lane 1
(the bridge). Found by 11.16's live checklist on 2026-08-22 against NVDA
2026.1.1, and **not introduced by it**: `run_sequence` only made the boundary
reachable, by having a plan's trigger match from the plan's own start mark.

---

## Part 1 — the evidence

Three calls, one live session, measured on 2026-08-22:

| call | answer |
|---|---|
| `get_speech(since_index=22)` | returns the utterance sitting **at** index 22 |
| `wait_for_speech(after_index=22, "Log")` | `found: false` |
| `wait_for_speech(after_index=21, "Log")` | `found: true`, `index: 22` |

So the wait scans history correctly and exactly one thing is wrong: the left
edge. `wait_for_speech` matches `index > after_index` where `get_speech` matches
`index >= since_index`.

### It bites the taught pattern, and it fails as silence

`get_next_speech_index` is documented as "the index the NEXT captured utterance
will take", and every description teaches the same three steps: bookmark, act,
pass that bookmark as `after_index`. Under an exclusive edge that silently
discards **the first utterance the action caused** — precisely the one being
waited for.

It fails as a **timeout**, not an error. So it reads as "the reader never said
it", and points nowhere near the boundary. An agent debugging it looks at the
gesture, the app, the capture mode, the timeout — everything except the index
arithmetic, which is the one thing that is wrong.

Inside `run_sequence` the same off-by-one costs the amendment its exact case: a
plan whose trigger arrives as the plan's FIRST utterance cannot match, which is
the "arrived a fraction of a millisecond early" case the amendment exists for.
Observed live — a plan pressing the report-title command and then waiting for a
word of that title answered `trigger_not_found`, with the matching utterance
sitting in its own merged window.

### Which side drifted is not in doubt

The defect is one line,
[`speech_buffer.py:114`](../bridges/nvda/addon/globalPlugins/nvdaMcpBridge/domain/entities/speech_buffer.py):

```python
first = 0 if after_index is None else after_index + 1
```

and the method's own docstring contradicts itself across two consecutive
sentences — line 109 says *"First index at/after `after_index`"*, line 111 says
*"`after_index` is exclusive (search starts at `after_index + 1`), matching
NVDASpyLib."*

That second sentence is the origin, and it is worth naming: the exclusive edge
is **not an accident**. It was borrowed deliberately from NVDA's own spy
library, a codebase whose indexing conventions are not ours. It arrived as a
convention, not as a typo, which is why it survived review.

Everything this repo says promises the other edge:

| where | what it promises |
|---|---|
| [`wait_for_speech.go:51`](../server/domain/controllers/tools/wait_for_speech.go) | "Only consider utterances **at or after** this index." |
| [`specs/wire/v1/protocol.md:727`](wire/v1/protocol.md) | "`afterIndex` restricts the match to items **at or** after…" |
| `speech_buffer.py:109` | "First index **at/after** `after_index`." |

So the bridge is the outlier against three statements of intent, one of them its
own.

### Two things found while writing this spec, which change the argument

**The server's own fake already implements the inclusive edge.**
[`server/fakes/speech_reader.go:180`](../server/fakes/speech_reader.go) reads:

```go
from := 0
if wait.AfterIndex != nil {
	from = *wait.AfterIndex
}
for i := from; i < len(f.spoken); i++ {
```

`from = *wait.AfterIndex`, and the loop starts **at** `from`. Every server-side
unit test has therefore been asserting inclusive behaviour against an inclusive
double, while the real bridge was exclusive. This is `AGENTS.md`'s stated limit
of hand-written fakes — *"what they cannot prove is that the real adapter
behaves like the fake"* — realised in full, and it settles which side moves: the
fix makes the **bridge** agree with what the server was already tested against,
rather than the reverse.

**The conformance test could not have caught it.**
[`real_bridge_session_test.go:639`](../server/tests/conformance/real_bridge_session_test.go)
asserts only:

```go
if waited.Index < before.Index {
```

`waited.Index >= before.Index` passes under **both** edges. The one tier that
runs the real Go binary against the real Python bridge was checking the wrong
inequality, so the drift had nothing standing in its way.

### What `wait_for_log` does, which closes an open question

Board entry 11.29 asks whether `wait_for_log` shares the shape and should move
with it. **It does not, and it should not.**
[`log_journal.py:275`](../bridges/nvda/addon/globalPlugins/nvdaMcpBridge/domain/entities/log_journal.py)
is already inclusive:

```python
first = max(start, self._oldest_position)
```

and it is reached by a differently-named parameter — `sincePosition`, not
`afterIndex` — whose docstring says *"the first record **at/after** `start`"*.
The log side is correct today and its naming already matches its behaviour.
11.29 is therefore a **lane-1, speech-only** entry, smaller than the board
allowed for.

---

## Part 2 — the shape

### Decision 1: fix the comparison — **agreed in conversation, 2026-08-23**

The bridge moves to the inclusive edge. `first` becomes `after_index` rather
than `after_index + 1`.

The alternative on the table was to reword the three documents to promise
"strictly after" and leave the shipped comparison alone. It was rejected for
three reasons, in order of weight:

1. **The repo's own convention is a half-open window with an inclusive left
   edge** — `entries_since`, `slice_since`, `find_since` and `get_speech` all
   render it. `wait_for_speech` would be the single exception, and an exception
   that exists in one command only is one every future reader has to re-learn.
2. **The fake and the documents already say inclusive**, so rewording means
   changing four things to match one, and changing the server's fake to be
   *less* like the taught pattern.
3. **Rewording makes the taught pattern teach arithmetic.** "Bookmark, act, wait
   on the bookmark" would become "bookmark, act, wait on the bookmark minus
   one", and a subtraction in a documented recipe is a defect with a manual
   workaround, not a design.

**The cost is accepted and stated plainly:** this changes behaviour in a shipped
command. Any caller who noticed the exclusive edge and compensated for it — by
passing one less than their bookmark — will, after this change, match one
utterance earlier than they did before. We judge that population to be close to
empty and its failure mode mild (a match one entry too early, visible in the
returned `index` and `text`), against a defect whose failure mode is a silent
timeout on the documented path. `run_sequence` is the only in-tree compensator,
and it is compensating *wrongly* — it is fixed by this change, not broken by it.

### Decision 2: `None` and `0` stay distinct — **agreed in conversation, 2026-08-23**

Under an inclusive edge, `after_index=None` (`first = 0`) and `after_index=0`
(`first = 0`) select the same entries. They stay **two requests** anyway:

- On the wire and at the server they are already deliberately distinct.
  [`wait_for_speech.go:85`](../server/domain/controllers/tools/wait_for_speech.go)
  carries the reasoning — *"a different request from 'at or after index 0', and
  this tool must not decide"* — and `speech_tools_test.go:218` asserts the
  pass-through of an unset value.
- They coincide **harmlessly**, because index 0 is the empty sentinel
  (`indexed_buffer.py:20`) and no real capture is ever there. So "no constraint"
  and "at or after 0" agreeing in effect is a property of the sentinel, not a
  collapse of meaning.

Collapsing `None` into `0` at the bridge would contradict an explicit server
decision to save one branch. The bridge keeps `int | None`; the docstring gains
a sentence saying the two now agree and why that is fine.

### What does NOT change

- **No wire change.** The parameter, its name, its type and its optionality are
  all untouched; `PROTOCOL_VERSION` does not move. This is a behaviour fix
  behind an unchanged shape.
- **No server change**, other than one conformance assertion (below). The tool
  description at `wait_for_speech.go:51` is already correct and stays as written.
- **No `wait_for_log` change**, per Part 1.
- **No `run_sequence` change.** It passes the plan's own start mark and is
  correct under an inclusive edge; today's `trigger_not_found` is cured by the
  entity fix, with nothing to edit at the call site.

---

## Part 3 — what ships

1. `index_of` starts its scan **at** `after_index`, and its docstring says one
   consistent thing.
2. Unit tests that pin the edge from both sides — the entry's own measured case
   (a match sitting exactly at the bookmark) and the neighbour it must not
   swallow (nothing before the bookmark matches).
3. The conformance assertion is tightened from a comparison that passes under
   both edges to one that fails under the wrong one, so this cannot drift back
   unnoticed.

## Class/file layout

No new files, no new classes. Four files change; the role column says why each
is touched.

| File | Role | Change |
|---|---|---|
| `bridges/.../domain/entities/speech_buffer.py` | **entity** (existing) | `index_of`: `first` becomes `after_index` rather than `after_index + 1`. Docstring rewritten — one claim, the `None`/`0` overlap named, the NVDASpyLib provenance kept as the reason it read the way it did. |
| `bridges/nvda/tests/unit/domain/entities/test_speech_buffer.py` | unit test (existing) | `test_index_of_respects_exclusive_after_index` is renamed and inverted; a test is added for the live case — an entry AT the bookmark is found — and one for the left neighbour being excluded. |
| `bridges/nvda/tests/unit/domain/controllers/commands/test_wait_for_speech.py` | unit test (existing) | One handler-level test that the bookmark-act-wait pattern finds the first utterance the action caused. |
| `server/tests/conformance/real_bridge_session_test.go` | conformance (existing) | The index assertion becomes one that fails under an exclusive edge. |

`wait_for_speech.py` (the handler) is **not** in the list: it passes
`params.afterIndex` straight through and holds no arithmetic. That is the
layering working — the edge lives in the entity, so the fix has exactly one
site.

## What is deliberately not built

- **A shared "index window" helper across the three buffers.** Tempting, since
  speech, braille and the journal all render half-open windows. But the
  journal's coordinate is a *position* with its own oldest-record clamp, not a
  buffer index, and merging them would couple two vocabularies that spec 0021
  deliberately separated.
- **A deprecation path for the old edge.** No version negotiation, no tolerated
  legacy spelling. The exclusive edge was never documented as such outside the
  contradicting docstring, so there is no promise to keep faith with.

## Honest limits

- **We cannot prove nobody was compensating.** The argument in Decision 1 is a
  judgement about a population we cannot enumerate, not a measurement.
- **The unit fix is provable; the live behaviour is not, until it is run.** The
  measured evidence came from a live session and the fix must be confirmed the
  same way — the PR carries a live checklist re-running the entry's exact three
  calls, plus the `run_sequence` plan whose trigger arrives first.
- **The tightened conformance assertion guards the edge, not the wait.** It
  proves the boundary; it says nothing about timing, merging or the grace
  window.

## Open questions

**None outstanding.** Both were closed in conversation on 2026-08-23 and are
recorded as Decisions 1 and 2 above. The board's third question — whether
`wait_for_log` moves with this — was answered by reading the code, in Part 1.

## Not in scope

- The braille buffer's own wait, if it grows one. It has no `after_index` search
  today.
- `run_sequence`'s trigger semantics beyond the edge. Spec 0036's amendment is
  unchanged; this makes its stated case reachable.
