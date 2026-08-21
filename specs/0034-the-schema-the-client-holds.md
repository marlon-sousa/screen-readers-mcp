# 0034 — the schema the client holds

Status: **agreed 2026-08-21.** Board entry **11.26**. Comes out of the
11.11/11.17 live run (PR #70), where it was not the thing under test: it turned
up because a checklist item could not be performed.

**Amended on agreement, twice, and both amendments make the spec smaller.** The
draft was written from the board entry rather than from the code, and the code
had already done some of it. Part 3.3's substantive half **ships already** — spec
0031's `screenreader://tools` publishes every tool's full input schema, composed
from the registry, with an integration test asserting it equals the tool's own —
so what is left there is one paragraph of framing rather than a new mechanism,
and the `ToolGate` parameter summary the draft proposed is **withdrawn** as a
second publisher of a fact already published. Part 3.2's scope shrank for a
mechanical reason: `decodeParams` uses a plain `json.Unmarshal`, so the unknown
and missing fields it carefully excluded **cannot reach it at all**. Both are
marked in place below.

---

## Part 1 — the evidence

The server gained one optional parameter, `normalize`, on `connect_reader`. The
binary was redeployed. The next call sent this:

```jsonc
{"reader": "nvda", "mode": "live", "persona": "expert", "normalize": "true"}
```

and failed with:

```
json: cannot unmarshal string into Go struct field connectParams.normalize of type bool
```

`"true"`, a **string**, where the schema published by the running server says
boolean. The client was not being careless: it was serialising against the
`inputSchema` it had cached, which did not declare the field at all. A
`/mcp reconnect screen-reader-testing` fixed it at once.

### What this contradicts, in writing

[`adapters/mcp/sdk_server.go`](../server/adapters/mcp/sdk_server.go) says, of
spec [0022](0022-the-server-explains-itself.md) option (c):

> A client that caches `tools/list` for the life of the process is holding a
> correct list — which is the whole point, and what closes board entry 11.6 for
> **BOTH** of the failures wearing its symptom: our own `poe redeploy` freezing a
> client's list, and an external client that simply never re-listed.

That claim is half true, and the half that is false is the one it names first.
Making the tool **list** a constant removed every reason it could change *within
a build*: no session opens or closes it, nothing is published or retracted, and
`tools/list_changed` is never emitted because there is nothing to announce. What
it cannot do — what nothing inside one process can do — is make the list constant
**across builds**. `poe redeploy` replaces the build. The list did not change that
day; a **schema inside it** did, and the client was holding the old one.

So 11.6 is closed for the failure it was opened for, and this is a different
failure with the same first symptom. **It is not "11.6 again"**, and the
distinction is the same one 11.22 and 11.6 needed from each other: a shared
symptom is not a shared cause.

### Why it is worse than a missing tool

A tool the client cannot see fails **loudly and early**: the agent cannot call it,
notices, and says so. That is 11.6's failure, and it is recoverable because it is
obvious.

A schema the client holds stale fails **quietly and late**, and it fails
*typed*. The call is made. The argument is serialised — wrongly, but plausibly.
The rejection, when it comes, is about JSON and Go structs. Nothing in it names
the actual situation, which is that two parties disagree about what this tool
takes. An agent reading that error learns about unmarshalling; it has no reason
to suspect its own cache, and every reason to suspect the value it sent.

Three ways it degrades, in descending order of how visible they are:

| the change | what the client does | what the agent sees |
|---|---|---|
| new parameter, new type | serialises against the old schema | a type error naming a field it did send |
| new parameter, absent from the call | omits it, because it does not know to send it | the server's DEFAULT, silently — no error at all |
| loosened enum or bound | may refuse client-side, or send the old set | a refusal of a value the server would now accept |

**The middle row is the dangerous one**, and it is the one this repo should care
about most: nothing fails. The agent asked for the default because it did not
know an alternative existed, and every party involved behaves correctly. That is
one observable — a successful call — for two situations: *the caller chose the
default* and *the caller could not have chosen anything else*.

---

## Part 2 — what a server can and cannot do about it

**It cannot refresh the client's cache.** There is no notification that means
"re-read what you already read"; `tools/list_changed` announces a changed *list*,
and by 0022 (c) this list never changes. Emitting it falsely to provoke a re-list
would be lying on the wire to work around a client, which is the kind of remedy
this repo has rejected before.

**It cannot tell staleness from a plain mistake.** A stale client sending
`"true"` and a current client sending `"true"` because its author typed a string
produce the *same bytes*. The server has no copy of what the client holds. Any
message about staleness is therefore a **hypothesis offered to the reader**, and
must be written as one — the alternative is to state a cause the server cannot
know, which is the failure 0027's reporter demonstrated from the other side.

**What it can do is make the situation legible, and stop giving false advice.**
Those are the two things that ship.

---

## Part 3 — what ships

### 1. The redeploy instruction is wrong, and is corrected

[`scripts/redeploy.py`](../scripts/redeploy.py) tells the human:

> RECONNECT ONLY IF YOU ADDED OR REMOVED A TOOL in this build

The run proves this wrong. No tool was added or removed; one parameter was, and
the reconnect was required. The instruction stands where a developer reads it at
exactly the moment they could act on it, so it is worth getting right:

> **Reconnect if the SURFACE changed in this build** — a tool added or removed,
> **or a tool's parameters or result changed.** The client caches `tools/list`,
> and that cache includes each tool's schema, so a parameter this build added is
> a parameter the client will not send correctly until it lists again.

A documentation fix is a small thing to put in a spec. It is here because the
current text is not merely incomplete: it tells a developer, in the imperative,
*not* to do the thing that would have saved the session — and it was written with
the confidence of a lesson learned.

**Two more sentences in the same message are corrected with it**, because they
are where the false confidence comes from rather than where it lands: the message
tells the reader that the stranded cache "is still a correct one" and that this
is "the whole of board entry 11.6". The first is true of the LIST and false of
the schemas inside it; the second is what Part 1 corrects. The amended text says
what a constant list does buy, and then says plainly that a rebuild is the case
it does not cover.

**And it goes in [`AGENTS.md`](../AGENTS.md) too** (agreed on review). The two
places are not redundant: the script is read at the moment a developer could act
on it, and the manual is where a session looks the rule up beforehand — and the
manual's copy carried the same wrong "only if you added or removed a tool". A
rule that is wrong in two places is not fixed by correcting one.

### 2. The decode failure says what it might mean

Today a parameter type error is reported exactly as the JSON decoder phrased it.
It should keep that (it is precise, and precision is what a developer needs) and
gain the hypothesis:

```
could not read the arguments {"reader":"nvda","normalize":"true"}: json: cannot
unmarshal string into Go struct field connectParams.normalize of type bool. The
value for "normalize" is a string, but this tool takes a boolean. If you did not
expect this parameter to be new, your client may be holding a tool schema older
than this server build -- a client caches tools/list, and that cache includes each
tool's parameters. Read screenreader://tools for the parameters this build
actually takes: a resource is read live and is never cached, so it describes the
build that is running even when a cached list does not. Re-listing the tools is
client UI -- only the human at the keyboard can reconnect this MCP server
```

*(Amended to the shipped wording. The draft's version dropped the decoder's own
sentence; the point of the hint is that it is ADDED to that sentence, so showing
it without is showing the wrong thing. It also read "reconnect the MCP server",
in the imperative, at an agent that cannot — the third property below is the one
that catches it.)*

Three properties this wording has to keep:

- **It hedges honestly.** "may be holding" and "if you did not expect", because
  the server does not know. It offers the reading it cannot confirm and names the
  cheap way to settle it, rather than asserting a cause.
- **It names the remedy the agent can perform**, and separately the one only a
  human can. Reading a resource is an agent's move; `/mcp reconnect` is not, and
  the message must not send an agent to a control it cannot reach — spec 0032's
  silence-cap sentence takes the same care.
- **It is a per-call error, not a session fault.** Nothing about it ends a
  session.

**Scope: type mismatches only, on a field the tool declares.** Malformed JSON is
not evidence of staleness and must not collect this hint — a hypothesis attached
to everything is noise, and the next reader learns to skip it.

> **Amendment, on agreement.** The draft also excluded "an unknown field" and "a
> missing required one". Those exclusions were unnecessary, and finding out why
> is worth recording: `decodeParams` calls a plain `json.Unmarshal` with no
> `DisallowUnknownFields`, and required-ness is checked by each tool afterwards,
> not by the decoder. So a field no struct declares is **ignored**, an absent one
> is **left at its zero value**, and neither produces an error that could reach
> the hint. **Type mismatch and malformed JSON are the only two errors this
> function can return**, which makes the scope a fact of the code rather than a
> rule somebody must remember — and `params_test.go` asserts the silence
> directly, so the limit is pinned rather than asserted in prose.
>
> It also closes the draft's second open question in the negative. The mirror
> case — a client still sending a parameter this build REMOVED — cannot be hinted
> at, because it does not fail. Making it fail would mean turning on
> `DisallowUnknownFields`, which rejects harmless extras from any client and is a
> much larger change than the hint; **not done**, and named here so a later
> session sees it was considered.

### 3. `screenreader://tools` already publishes each tool's parameters — and now says why that matters

**Amended on agreement. The draft was wrong about the code, and in the cheapest
possible direction: this was already built.** Spec 0031's tools document does not
merely record which capability gates which tool. `toolsDocument` renders, per
tool, a `Parameters:` block containing that tool's full `InputSchema()` and a
`Returns:` block containing its `OutputSchema()`, both composed from the registry
the running process holds — so a tool that gains a parameter gains a document
entry by construction, which is exactly the property the draft asked for. The
embedded frame already announces it ("the parameters it takes … both as JSON
Schema"), and
`TestEverySchemaInTheDocumentParsesAndMatchesTheToolsOwn` already asserts, per
tool, that the published schema equals the tool's own, read through a real MCP
client.

So the mechanism is met and **the `ToolGate` parameter summary the draft proposed
is withdrawn**. It would have been a second rendering of a fact the document
already renders in full — and the draft's own objection to duplicating
descriptions applies with more force to duplicating the shape, since the shape is
the part a stale cache gets wrong. `tool_catalog.go` and `registry.go` are
untouched by this entry.

**What was genuinely missing is the reason to read it**, and that is what ships
in its place. The frame told an agent that this document is *static* — "Read it
before you connect. Nothing in it changes during a session." That is true, and
read alone it is an invitation to treat the document the same way a client treats
the tool list: fetch once, keep. The one property that makes it the right thing
to read at the moment of a puzzling argument error is the property the frame
never stated, because before this entry nobody had a reason to state it: **a
resource is read live on every request, and a tool list is cached.** The document
is therefore the only channel in this server that always describes the build that
is actually running.

The frame gains a short section saying so, and saying what to do with it: read
the parameters here rather than trusting the ones you hold, both when a tool
rejects an argument you believed was right and when you want to be sure you are
not missing an option. It repeats the split the error message makes — reading
this is a move the agent can make in the same turn; re-listing the tools is
client UI only the human can reach.

That last use is the middle row of Part 1's table getting its only defence. An
agent that suspects it is missing an option can look, rather than concluding from
a successful call that there was nothing to miss.

### 4. It does not need a live NVDA

Every claim here is about this server and its client, and none of it touches a
reader. The integration tier already runs a real MCP client against this real
server, which is where the resource's content is asserted. **This is the first
entry in a while with no live checklist**, and saying so is part of the estimate.

*(Amended: the draft said "conformance tier". The conformance tier is the one
that needs a real bridge; the tier that reads this document through a real client
is `server/tests/integration`, and it is where the existing assertion lives.)*

---

## Class/file layout

Per AGENTS.md, a spec names every file before the code exists. **Amended on
agreement**: three rows are struck, because Part 3.3's mechanism was already
built — `tool_catalog.go`, `registry.go` and a new assertion in
`tools_resource_test.go` are all withdrawn, and `tools_resource.go` needs no
change at all. One row is added: the frame, which is where the missing half was.

| File | Role | Collaborators |
|---|---|---|
| `server/domain/controllers/tools/params.go` (existing, holds `decodeParams`) | The one place every tool decodes its arguments, which is why the hint has exactly one home. It inspects the decoder's error for a **type** mismatch (`*json.UnmarshalTypeError`), and only then wraps it with the hypothesis and the pointer at the resource. Every other decode error passes through untouched. `sentAs`, `takes` and `article` are private helpers that phrase it: the two types are named as the published schemas spell them, since the whole point is to send the reader to one. | Called by every tool's `Execute`. |
| `server/domain/controllers/tools/params_test.go` (new) | unit | In-package, because `decodeParams` is unexported. A type mismatch gains the hint and keeps the original detail; the types are named in schema vocabulary; malformed JSON does NOT gain it; and an unknown field and an absent one produce **no error at all**, which pins the honest limit rather than asserting it in prose. |
| `server/adapters/mcp/documents/tools-frame.md` | agent-facing document (existing) | Gains the section that says this document is read live and never cached, and is therefore what to trust when a cached list may be older than the build. The frame stays free of any tool name, so the existing drift guard is unaffected. |
| `scripts/redeploy.py` | dev tooling (existing) | The corrected instruction, plus the two sentences above it that carried the same false confidence. |
| `AGENTS.md` | dev manual (existing) | The same correction where a session looks the rule up, with the reason it is 11.26 and not 11.6. |
| `server/adapters/mcp/sdk_server.go` | adapter (existing) | The comment quoted in Part 1 is amended: 0022 (c) closed the within-build half, and this entry is the across-build half. Left uncorrected it is a confident statement that a future session would trust. |

**Withdrawn from the draft's layout**, with the reason, so a reader of the diff
is not left wondering: `server/domain/entities/tool_catalog.go` and
`server/domain/controllers/tools/registry.go` (a `ToolGate` parameter summary
would duplicate what `tools_resource.go` already composes from the same
registry); `server/adapters/mcp/tools_resource.go` and its unit test (they
already render and already match); and `server/tests/conformance/` (the
assertion exists, one tier down, in
`server/tests/integration/mcp_tools_resource_test.go`).

---

## What is deliberately not built

- **A build fingerprint an agent compares against its cache.** An agent cannot
  read its own cached schema, so there is nothing to compare a fingerprint
  *with*. It would be a number that changes, telling nobody anything.
- **Emitting `tools/list_changed` to provoke a re-list.** The list did not
  change. Sending a notification whose meaning is false, to trigger a behaviour
  we want, is a lie on the wire — and a client is entitled to ignore it, so it
  would be an unreliable lie.
- **Server-side tolerance of the wrong type** (accepting `"true"` for `true`).
  It would make this exact bug invisible, which is the opposite of the entry's
  purpose, and it would silently accept genuinely wrong calls forever after.
- **Anything about the middle row's silence beyond the document.** Detecting
  "the caller would have passed this had they known" is not something the server
  can do; publishing the truth where the agent can read it is.

---

## Honest limits

- **The hint can be wrong**, and will sometimes appear when a current client
  simply sent the wrong type. It is written as a hypothesis for that reason, and
  the cost of a wrong hypothesis here is one sentence a developer discards.
- **It does not fix the middle row.** An agent that never suspects a missing
  parameter will not read the document, and nothing here makes it. The document
  is a defence available to an agent that *wonders*, which is strictly better
  than today's nothing and strictly worse than a cache that was correct.
- **The reconnect remains a human action.** Nothing in this spec lets an agent
  recover on its own; it lets an agent explain, precisely, what the human should
  do. Board entry 11.6 reached the same limit and it has not moved.

---

## Open questions

**All three were settled on agreement**, and the answers are recorded here rather
than deleted, because two of them were settled by facts rather than by taste.

- **Should the tools document also carry the result shape?** ~~The same argument
  applies to output schemas, and the same objection (duplication) applies
  harder.~~ **Moot: it already does.** `toolsDocument` renders `OutputSchema()`
  beside the input schema, and the integration tier checks both. The question was
  asked from the board entry rather than from the code.
- **Is a type mismatch the only trigger worth hinting on?** **Yes, and not by
  choice.** The mirror case — a client still sending a parameter this build
  removed — produces no error to hint on, because `decodeParams` ignores fields
  no struct declares. Catching it would mean `DisallowUnknownFields`, which
  rejects harmless extras from every client; not done. See 3.2's amendment.
- **Does the corrected redeploy text belong in AGENTS.md too?** **Yes, both
  places.** The manual carried the same wrong rule, so correcting only the script
  would have left the wrong version where a session reads it first. The two say
  the same thing at different lengths and neither is the other's summary.

---

## Not in scope

Board entry 11.6's original failure (a session opening and the client not
re-listing) is Done and stays Done — see Part 1. Entry 11.22's tools document is
the machinery this builds on rather than a question it reopens.
