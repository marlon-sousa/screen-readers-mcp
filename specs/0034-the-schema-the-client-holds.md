# 0034 — the schema the client holds

Status: **drafted 2026-08-21, not agreed.** Board entry **11.26**. Comes out of
the 11.11/11.17 live run (PR #70), where it was not the thing under test: it
turned up because a checklist item could not be performed.

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

### 2. The decode failure says what it might mean

Today a parameter type error is reported exactly as the JSON decoder phrased it.
It should keep that (it is precise, and precision is what a developer needs) and
gain the hypothesis:

```
value for "normalize" is a string, but this tool takes a boolean.
If you did not expect this parameter to be new, your client may be holding a tool
schema older than this server build -- reconnect the MCP server so it lists the
tools again. Read screenreader://tools for the parameters this build actually
takes; a resource is read live and is never cached.
```

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

**Scope: type mismatches only, on a field the tool declares.** An unknown field,
a missing required one, or malformed JSON are not evidence of staleness and must
not collect this hint — a hypothesis attached to everything is noise, and the
next reader learns to skip it.

### 3. `screenreader://tools` publishes each tool's parameters

The tools document today records **which capability gates which tool**. It should
also record **what each tool takes**: parameter names, types, and whether each is
required.

This is the substantive half, and the reason is mechanical rather than
editorial: **a resource is read live on every request, and `tools/list` is
cached**. So the resource is the one channel in this server that always describes
the build that is actually running. An agent that hits a puzzling argument error
can read the document and see the truth without a reconnect, without a human, and
without knowing that caching exists.

It also gives the middle row of Part 1's table its only defence. An agent that
suspects it is missing an option can look, rather than concluding from a
successful call that there was nothing to miss.

**Names, types and requiredness — not the descriptions.** The descriptions are
long, they are already in `tools/list`, and duplicating them would create the
second publisher of one fact that this repo keeps deleting (0024 Part 3.3 was
withdrawn for exactly that). What the document adds is the part a stale cache
gets *wrong*, which is the shape.

### 4. It does not need a live NVDA

Every claim here is about this server and its client, and none of it touches a
reader. The conformance tier already runs a real client against the real binary,
which is where the resource's content is asserted. **This is the first entry in a
while with no live checklist**, and saying so is part of the estimate.

---

## Class/file layout

Per AGENTS.md, a spec names every file before the code exists.

| File | Role | Collaborators |
|---|---|---|
| `server/domain/controllers/tools/params.go` (existing, holds `decodeParams`) | The one place every tool decodes its arguments, which is why the hint has exactly one home. It inspects the decoder's error for a **type** mismatch (`*json.UnmarshalTypeError`), and only then wraps it with the hypothesis and the pointer at the resource. Every other decode error passes through untouched. | Called by every tool's `Execute`. |
| `server/domain/controllers/tools/params_test.go` (new or existing) | unit | A type mismatch gains the hint and keeps the original detail; a missing required field, an unknown field and malformed JSON do NOT gain it. |
| `server/domain/entities/tool_catalog.go` | entity (existing) | `ToolGate` gains the tool's parameter summary — name, type, required — so the table stays the single source for what the document says about a tool. Still no reader name and still no capability logic. |
| `server/domain/controllers/tools/registry.go` | registry (existing) | Fills the summary from each tool's own `InputSchema()`, so a tool that gains a parameter gains a document entry **by construction** rather than by somebody remembering — the property the catalog comment already claims for the gate. |
| `server/adapters/mcp/tools_resource.go` | adapter (existing) | Renders the parameters into the document. |
| `server/adapters/mcp/tools_resource_test.go` (existing) | unit | Every registered tool appears with its parameters; the rendered types match the schema the tool publishes. |
| `server/tests/conformance/` (existing) | conformance | The document, read through a real client from the real binary, names a parameter that exists — the tier where a drift between schema and document would show. |
| `scripts/redeploy.py` | dev tooling (existing) | The corrected instruction. |
| `server/adapters/mcp/sdk_server.go` | adapter (existing) | The comment quoted in Part 1 is amended: 0022 (c) closed the within-build half, and this entry is the across-build half. Left uncorrected it is a confident statement that a future session would trust. |

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

- **Should the tools document also carry the result shape?** The same argument
  applies to output schemas, and the same objection (duplication) applies harder,
  since a result shape is larger. Parameters are what a *caller* gets wrong.
- **Is a type mismatch the only trigger worth hinting on?** An unknown-field
  error could equally mean a client sending a parameter this build *removed* —
  the mirror case. It is rarer, and adding it widens the hint's blast radius.
- **Does the corrected redeploy text belong in AGENTS.md too?** The script is
  where it is read at the right moment; the manual is where somebody looks
  afterwards.

---

## Not in scope

Board entry 11.6's original failure (a session opening and the client not
re-listing) is Done and stays Done — see Part 1. Entry 11.22's tools document is
the machinery this builds on rather than a question it reopens.
