# 0035 — attendance is declared, not derived

Status: **drafted 2026-08-21, not agreed.** Board entry **11.27**. Comes out of a
question asked during the 11.11/11.17 live run: *is the agent warned whether the
machine is unattended?*

The answer was **yes, already** — and finding out why produced this entry.

---

## Part 1 — the evidence

Spec [0032](0032-a-bound-on-the-silence.md) shipped `silenceCap` in the handshake,
and [`entities/silence_cap.go`](../server/domain/entities/silence_cap.go) renders
it into one sentence an agent can act on. There are three:

| what arrived | what the agent is told |
|---|---|
| nil | "This reader did not say… Assume it does not, and **narrate anyway**." |
| `enabled: false` | "This machine is configured as **UNATTENDED**… Do not spend round trips narrating to an empty room." |
| `enabled: true` | "**A HUMAN IS EXPECTED AT THIS MACHINE**… Announce before any stretch of work…" |

So the fact is delivered, at connect, in a field `connect_reader` declares
**required**. Nothing needs adding for an agent to *know*.

### Where it comes from, which is the entry

On the bridge the setting is called `unattended`, and the policy is built as:

```python
return cls(enabled=not unattended, warn_after=warn_after, lift_after=lift_after)
```

The wire then carries **only `enabled`**. The server receives it and renders
"UNATTENDED" by inverting it back.

So the round trip is: **attendance is declared → a cap flag is derived → the
derived flag crosses the wire → attendance is reconstructed by inverting it.**

Today that is lossless. `enabled = not unattended` is a bijection, so inverting
recovers exactly what the machine's owner set. **There is no bug to fix right
now, and this spec should not pretend otherwise.**

### Why it is worth an entry anyway

The wire carries the **derived** value and not the **declared** one, and the
inversion is only correct while `unattended` is the *sole* input to `enabled`.
The moment anything else can turn the cap off, `enabled: false` stops meaning
"nobody is there", and the server keeps saying it does. Three ways in, none
exotic:

- **A per-session or per-machine reason to disable the cap.** A user who finds
  the 90-second lift disruptive and would rather the agent simply narrated turns
  the cap off. They are sitting right there. The server tells the agent the room
  is empty.
- **A bridge with no cap machinery.** 0005's whole posture is that a second
  reader will differ. A JAWS or TalkBack bridge that has not implemented a
  silence cap has two options today: claim `enabled: true` for a cap it does not
  run, or send `enabled: false` and have every session told nobody is listening.
  Both are false, and the second is the harmful one.
- **A cap that lifts for a reason of its own.** 0032 already distinguishes "the
  cap is configured" from "suppression is currently in force"; any future state
  in that area is another way for the two facts to come apart.

**The failure has a direction, and it is the bad one.** Getting it wrong towards
"attended" costs round trips spent narrating to an empty room. Getting it wrong
towards "unattended" tells a well-behaved agent to **stop narrating to a human
who is there** — leaving a blind person mute, uninformed, and holding a machine
that has stopped explaining itself. That is precisely the harm 0032 exists to
prevent and the harm 11.11 was opened for, arrived at from the opposite end.

The bridge already knows this asymmetry and reasons from it. Its own config
reader says so, and defaults accordingly:

> the failure mode of getting it wrong is a blind person unable to hear their own
> computer, with nothing to stop it

That reasoning is applied to *reading the setting* and then discarded when the
setting is *transmitted*.

---

## Part 2 — the shape

> **Carry the fact the machine's owner declared. Do not reconstruct it from a
> policy derived from it.**

### Why not simply add `attended` to `SilenceCapInfo`

It is one line and it is tempting, and it puts a fact inside a structure named
for something else. `silenceCap` answers *does this machine bound the silence,
and with what thresholds*. Attendance is not part of that answer: it is the
**machine fact** from which today's policy happens to be derived, and the entry
exists precisely because the two must be able to disagree. Nesting the cause
inside the effect would make the next reader believe they are one thing, which is
the belief being corrected.

### What ships instead: a sibling field at `hello`

```jsonc
// HelloResult
{
  "attended": true,          // or false, or absent
  "silenceCap": { "enabled": true, "warnAfterSeconds": 45, "liftAfterSeconds": 90 }
}
```

`attended` is its own optional field beside `silenceCap`, and **absent is a third
answer**, exactly as nil is for the cap: *this bridge does not say*, which is an
older build rather than a claim either way.

### The three-state rendering, and the compatibility path

| `attended` | `silenceCap` | what the agent is told |
|---|---|---|
| `true` | anything | a human is here; narrate. Cap thresholds appended when there is a cap. |
| `false` | anything | nobody is expected; do not spend round trips narrating. |
| absent | `enabled: true` | a human is here — **inferred**, as today |
| absent | `enabled: false` | today's sentence, **and it keeps today's wording** |
| absent | nil | "did not say… narrate anyway" — unchanged |

The last three rows are a **compatibility path and not the truth**, and the code
should say so where it lives. An older bridge that predates this field is exactly
the situation the inversion was written for, and it is still the best guess
available for one. What changes is that a bridge which *can* speak declares, and
the guess stops being the primary route.

### It stays read-only

For 0032's reason, unchanged: an agent that could declare the room empty could
switch off its own obligation to narrate. There is no setter, and `setState`
(spec [0033](0033-a-toggle-with-no-setter.md)) does not acquire one — attendance
fails that spec's membership rule outright, since it is not a mode the reader
gives its user a command for.

---

## Part 3 — what ships

1. **`attended: bool | None` on `HelloResult`**, wire-documented in
   `protocol.md` §3 beside `silenceCap`, with absent as the third answer.
2. **The NVDA bridge sends it** from the `unattended` config key it already
   reads — `attended = not unattended` — computed once, next to the policy, so
   the two are visibly derived from the same source rather than one from the
   other.
3. **The server records it on the session** and renders the sentence from it when
   present, falling back to today's inference when absent.
4. **`connect_reader` keeps reporting one sentence**, not two fields. The agent's
   job did not change and neither should its reading: what changes is that the
   sentence is now true for reasons that will still hold when a second bridge
   exists.

**Deliberately NOT a new capability.** Following 0033's settled precedent: this
is a fact in the handshake, like `synth` and `logPath`, not a command group. A
bridge that has nothing to say omits the field.

---

## Class/file layout

| File | Role | Collaborators |
|---|---|---|
| `shared/nvda_mcp_wire/protocol.py` | wire (existing) | `HelloResult.attended: bool \| None = None`, defaulting to absent so an older bridge is unchanged. `PROTOCOL_VERSION` 1 is pre-release and both halves ship from this repo, so this is a rebuild rather than a migration. |
| `specs/wire/v1/protocol.md` | wire contract (existing) | §3, beside `silenceCap`: the three states and the rule that a consumer must not infer attendance from the cap when the field is present. |
| `bridges/nvda/addon/.../domain/controllers/commands/hello.py` | controller (existing) | Reads `unattended` alongside the cap policy it already builds, and fills the field. |
| `bridges/nvda/addon/.../domain/entities/silence_cap.py` | entity (existing) | The policy keeps its own shape; what is added is that `unattended` is carried out of it rather than only into it. |
| `server/adapters/wire/wire.gen.go` | generated (existing) | Regenerated; no hand edit. |
| `server/adapters/bridge/handshake.go` | adapter (existing) | Maps the field onto the session, nil preserved. |
| `server/domain/entities/reader_session.go` | entity (existing) | `Attended *bool` — a pointer, because absent is a third answer. |
| `server/domain/entities/silence_cap.go` | entity (existing) | `Sentence` takes attendance as an argument rather than inferring it, and the fallback is commented as a compatibility path. Its signature changing is the point: a caller can no longer get the sentence without having considered the fact. |
| `server/domain/entities/silence_cap_test.go` | unit (existing) | The five rows of Part 2's table, including attended-but-uncapped — the case that cannot be expressed today and is the entry's whole reason. |
| `server/domain/controllers/tools/connect_reader.go` | controller (existing) | Passes the session's attendance to `Sentence`. The result shape does not change. |
| `bridges/nvda/tests/unit/.../test_hello.py` | unit (existing) | The field is sent, and matches the config key. |
| `server/tests/conformance/` | conformance (existing) | The value crosses the real binary against the real bridge — the only tier where the Python that writes it meets the Go that reads it. |

---

## What is deliberately not built

- **A settable attendance.** See Part 2.
- **`attended` inside `SilenceCapInfo`.** See Part 2; it is the shape this entry
  exists to avoid.
- **Removing the inference.** An older bridge still needs it, and it is still the
  best available guess for one.
- **A richer answer than a boolean** ("attended by whom", "attended until"). No
  run has needed one, and the fact an agent acts on is binary.

---

## Honest limits

- **Nothing is broken today**, and this spec must not be read as a bug report.
  It is a fact travelling in a form that is correct only while one derivation
  holds, and the cost of being wrong later is borne by a person who cannot hear
  their machine. That is the entire argument, and if the reviewer does not accept
  it, this entry should be closed rather than watered down.
- **The bridge still derives `attended` from `unattended`** — the negation moves
  one step earlier rather than disappearing. What changes is *where* it happens:
  at the source, once, beside the setting, instead of at the far end of a wire by
  a party that never saw the setting.
- **A second bridge could still lie**, declaring a human it does not have. The
  wire cannot prevent that and does not try; what it can do is stop *forcing* an
  honest bridge into a false answer, which is today's situation for a reader with
  no cap.

---

## Open questions

- **`attended` or `unattended` on the wire?** The bridge's config says
  `unattended` and the server's sentence says both. A positive field reads better
  in a schema; matching the config key reduces the chance of an inversion bug in
  the one place inversions have already proved slippery.
- **Should the cap's `enabled` stay derived on the bridge**, or become its own
  setting once attendance travels separately? Splitting them fully is a config
  change for the human at the reader, which is a different kind of decision.
- **Does `status` report attendance too?** It reports what is currently true of a
  session; attendance is fixed for the session, like mode, which argues for
  connect only.

---

## Not in scope

The silence cap's thresholds, its warning, and its lift are 0032's and unchanged.
Board entry 11.11's channel normalisation is a different remedy for a different
half of the same silence.
