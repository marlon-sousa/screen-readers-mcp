# 0038 — attendance you can ask for again

Status: **agreed 2026-08-23.** Board entry **11.30**, lane 2 (the server), and
**shipping in one PR with [0037](0037-the-inclusive-left-edge.md)** — see that
spec's status note for why the two travel together. Opened 2026-08-22 by the conversation following 11.16's live run,
from the question *"can the agent know whether the machine is attended?"*

---

## Part 1 — the evidence

**It can, and only in one place.** `connect_reader`'s `silenceCap` field is the
single point at which an agent learns whether a human is at the reader. It is
deliberately one sentence rather than a flag —
[`silence_cap.go:66`](../server/domain/entities/silence_cap.go) says why, and
spec [0035](0035-attendance-is-declared-not-derived.md) settled it — and it
gives four answers: attended and capped, attended and uncapped, unattended, or a
reader too old to declare it (which resolves towards narrating).

Nothing else carries it:

| surface | what it answers instead |
|---|---|
| `status` | `suppressing` says whether speech is being withheld **right now** — a per-moment fact, not a per-session one. |
| `screenreader://info` | the reader, its version, the mode, the capabilities, the persona, the log path. Not attendance. |
| `screenreader://guidance` | how to *use* attendance once you know it. It teaches the reasoning; it cannot tell you the answer for this session. |

So the fact is delivered once, correctly, and then only memory holds it.

### Attendance is fixed; the agent's memory of it is not

Spec 0035 made attendance connect-only for a good reason, and **this entry does
not question it**: it cannot change while a session lives, so there is nothing
to re-read *in the reader*.

What can change is **who is holding the fact**:

- a context that has been compacted;
- a sub-agent handed a live session;
- a session picked up after a restart.

None of them can recover it. The only route back is to disconnect and reconnect
— throwing the session away in order to ask a question about it, which on a
silent session also means a stretch where the human hears nothing while the
reconnect happens.

### Why this fact and not any other in the connect result

**Losing it fails towards silence at an occupied machine.**

An agent that cannot remember whether anyone is listening, and reasons carefully
from what it *does* have, reaches a defensible and wrong conclusion: round trips
spent narrating to an empty room are waste, so do not spend them. That is
exactly the wrong answer for a blind person sitting in front of a reader that
has gone quiet — and `sentenceAttendedUncapped` names the case with the least
margin of all: *"nothing will interrupt the session to restore speech, however
long you work."* There is no lift coming, so the only thing standing between
that person and a silent machine is the agent choosing to speak.

Every other field in the connect result fails towards an ordinary mistake. An
agent that forgets the reader's version guesses a gesture wrong and sees an
error. An agent that forgets the mode gets speech it did not expect. An agent
that forgets attendance leaves somebody in the dark and never finds out.

### What makes it small

**No wire change and no bridge traffic.** The server already holds both inputs
for the life of the session —
[`reader_session.go:81`](../server/domain/entities/reader_session.go) carries
`SilenceCap` and line 103 carries `Attended` — and `connect_reader` renders them
at [`connect_reader.go:370`](../server/domain/controllers/tools/connect_reader.go)
with a single call:

```go
SilenceCap: session.SilenceCap.Sentence(session.Attended),
```

Re-publishing the sentence is one more call to the same method on state that is
already in hand. Nothing is asked of the bridge, and nothing new crosses the
local endpoint.

---

## Part 2 — the shape

### Decision: it goes in `screenreader://info` — **agreed in conversation, 2026-08-23**

The resource gains the sentence. `status` does not.

The resource's **own header already argues this case**, for a different fact and
in the same words this entry needs
([`info_resource.go:14`](../server/adapters/mcp/info_resource.go)):

> A RESOURCE rather than `initialize.instructions`, which was considered and
> rejected: instructions are frozen at handshake time, and the bridge usually
> connects long afterwards. A resource is read when the agent wants it and
> always describes the session that exists now.

An agent recovering from a compaction is that same argument a second time: the
fact it needs was delivered at a moment it no longer has, and a resource is the
mechanism this server already built for exactly that. Two properties matter and
both are the resource's:

1. **It is served live and never cached**, so it describes the session that
   exists now rather than the one that existed when something was listed.
2. **Reading it costs no tool call and asks nothing of the human** — which is
   the whole point for an agent that has lost its context and is trying to
   recover without interrupting anyone.

There is a second reason, from the resource's existing contents: `info` already
carries `Persona`, and its comment says why — *"an agent that reads this
document to find out what it is driving also needs to know what it is standing
in for, and the two together are what make a finding interpretable afterwards."*
Attendance is the third member of that set. What you are driving, what you are
standing in for, and whether anybody is listening are one question asked three
ways, and they should be answerable in one read.

### Why not `status`, and the honest counter-argument

The counter-argument is real and was weighed: an agent that has lost its context
is arguably likelier to reach for a **tool** than to remember that a resource
URI exists. Tools are listed; resources must be known about.

It loses on two grounds:

- **`status` answers a different kind of question.** Its fields are per-moment —
  `suppressing`, `live`, `liveError`, the connection state. Attendance is fixed
  for the session's whole life. Putting a constant beside a set of live readings
  invites exactly the misreading that `suppressing` already attracts: that it
  might change, and therefore should be re-polled.
- **The discovery objection is answerable without moving the fact.** An agent
  that reads `screenreader://info` at all finds attendance there; one that does
  not is reached by the guidance documents, which is where "read this when you
  have lost your bearings" belongs. If it later turns out that agents genuinely
  do not find the resource, that is evidence for a **guidance** change, not for
  duplicating a session constant into a per-moment tool.

**Both places** was the third option and is deliberately not taken. It costs
nothing at runtime, but it puts one sentence in two surfaces that must then be
kept in step, and it weakens the distinction — per-session facts in the
resource, per-moment facts in `status` — that makes either of them readable. If
the duplication is ever wanted, it is cheap to add later; removing it once
agents depend on both is not.

### What the field says

The **same sentence**, verbatim, that `connect_reader` returns. Not a shortened
form, and not a boolean.

Two reasons. The sentence is already load-bearing prose written to be acted on —
spec 0035 chose one sentence over a flag precisely so the agent is told what to
*do*, not just what is true — and an agent recovering from a compaction needs
the instruction more than an agent reading it at connect, not less. And a second
rendering would be a second thing to keep true; `Sentence()` is the one place
the four cases are decided, and both callers go through it.

### What does NOT change

- **No wire change.** `PROTOCOL_VERSION` does not move; nothing new is asked of
  the bridge.
- **No change to `connect_reader`.** It keeps returning the sentence exactly as
  it does today. This adds a second way to read the same fact, not a replacement.
- **No change to attendance being connect-only, read-only, or reader-declared.**
  Spec 0035's decisions stand untouched — in particular an agent still cannot
  *set* it, for 0035's reason: an agent that could declare the room empty could
  excuse itself from narrating.
- **No `status` change.**

---

## Part 3 — what ships

1. `screenreader://info` carries the attendance sentence whenever a session
   exists, rendered from the same `SilenceCap.Sentence(Attended)` that
   `connect_reader` uses.
2. It is absent — the field omitted, not empty — when no session is connected,
   like every other session-derived field in that document.
3. The resource's description gains a clause so an agent skimming the tool and
   resource list learns the answer is in there.

## Class/file layout

No new files, no new classes, no new ports. Three files change.

| File | Role | Change |
|---|---|---|
| `server/adapters/mcp/info_resource.go` | **adapter** (existing) | One field on the `info` struct — `Attendance string`, `omitempty` — with a comment saying it is a session constant and why it is re-readable. One line in `describe` calling `session.SilenceCap.Sentence(session.Attended)`. One clause added to the resource's `Description`. |
| `server/tests/integration/mcp_info_resource_test.go` | integration test (existing) | The attended and unattended sentences appear for a connected session; the field is absent with no session; the text is identical to what `connect_reader` returned for the same handshake — the assertion that keeps the two renderings from drifting. |
| `server/README.md` | docs (existing) | The `screenreader://info` row names attendance among what the resource answers. |

`silence_cap.go` and `reader_session.go` are **not** in the list, and that is the
design holding: the sentence is already rendered by a domain entity from state
the session already carries, so a second consumer costs the domain nothing. The
adapter reads what is there.

Note the layering point in the one line that changes `describe`: `info_resource.go`
is an adapter reading a **domain entity's** rendering. That is the allowed
direction, and it is why `Sentence()` lives on the entity rather than in
`connect_reader` — spec 0035 put it there for `Persona.Stance`'s reason, and this
entry is the payoff.

## What is deliberately not built

- **A `get_attendance` tool.** A tool call to re-read a session constant is the
  round trip this entry exists to avoid.
- **A shortened or structured form** — no boolean, no enum beside the prose. The
  four cases are prose because prose is what an agent acts on; a flag beside it
  would immediately become the thing agents read, and it cannot express
  "attended but uncapped".
- **Re-asking the bridge.** Nothing is fetched. The fact cannot change while the
  session lives, so asking would add traffic and a failure mode to re-derive a
  constant.
- **Putting it in `status` as well.** Argued above; cheap to add later if
  evidence calls for it.

## Honest limits

- **This does not make an agent read the resource.** It makes the fact
  recoverable; whether a compacted agent thinks to look is a guidance question,
  and the guidance documents are not changed by this entry. If a later run shows
  agents still going silent after a compaction, that is the next entry and it is
  about guidance, not about this field.
- **The integration test proves the two renderings agree at one moment**, not
  that they cannot diverge — they share a method, which is the real guarantee;
  the test is the tripwire.
- **A sub-agent handed a live session still has to be told the session exists.**
  This fixes what it can ask; it does not fix hand-off.

## Open questions

**None outstanding.** The board's question — where it belongs, and whether the
same prose or a shorter form — was closed in conversation on 2026-08-23: the
resource, and the same sentence.

## Not in scope

- Anything about the inactivity watchdog's visibility. That is board entry
  **11.23** and a different question — how long the session has left, not who is
  listening.
- Hand-off of a live session between agents, in general.
