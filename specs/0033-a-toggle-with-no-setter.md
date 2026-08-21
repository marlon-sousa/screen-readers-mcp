# 0033 — a toggle with no setter

Status: **drafted 2026-08-20, AGREED 2026-08-20** — in one conversation with
[0024](0024-a-session-the-agent-can-hear.md), which is what this entry has asked
for since it was opened. Board entry **11.17**. Comes out of
[0027](0027-the-first-external-run.md) ask 2 — the first external run, reported
by someone who had never read this repo's specs.

**To be decided together with [0024](0024-a-session-the-agent-can-hear.md) and
board entry 11.11.** Same gesture, two sessions, complementary remedies: 0024
gives the agent the *tone* it cannot hear, so it learns which mode it landed in;
this gives it a way not to land in the wrong one at all. Neither makes the other
redundant — hearing the tone still leaves the toggle non-idempotent, and a setter
still leaves every other earcon inaudible.

---

## Part 1 — the evidence

> *"NVDA+space is a toggle, and there's no setter. With no idempotent way to say
> 'be in browse mode', automation has to `get_state`, branch, press, then
> re-check — and if it guesses wrong it flips the wrong way and silently corrupts
> everything after. `set_browse_mode("browse"|"focus")` would remove a whole
> class of automation bug. Your own config makes this sharper: an agent that
> assumes auto-switching gets wrong answers and, as I just demonstrated, blames
> the app."*

Two findings, not one. The ask is the first. **The last clause is the second, and
it is the more interesting**: an agent blaming the application for a reader-mode
confusion is precisely the failure [0023](0023-drive-it-like-a-user.md) predicts,
reached independently by a reporter who had never read 0023. A prediction
confirmed by someone outside the argument is worth more than the argument.

### What the toggle costs, exactly

`NVDA+space` flips. To *arrive* somewhere, an agent must read, compare, press and
read again — and every one of those steps but one can be wrong:

| step | what can go wrong |
|---|---|
| read | the mode changes between the read and the press (a page finishes loading) |
| compare | nothing; this is the only safe step |
| press | against a stale read, this flips *away* from the target |
| re-check | catches it one round trip later, after the keys that followed have already gone somewhere |

The failure is silent and *retroactive*: by the time the re-check disagrees, the
agent has typed into a search field. That is the same shape
[0025](0025-one-round-trip-per-intention.md) found in the settle — a step whose
answer is stale before it is read — and the same shape 11.11 found in the tone.

---

## Part 2 — the shape, and why not the one that was asked for

**`set_browse_mode` is not adopted.** [0005](0005-multi-reader-direction.md)
principle 2 makes the **capability** the unit of reader difference, chosen on
purpose with the examples "JAWS lacking braille, TalkBack lacking config". A tool
per toggle would put a per-toggle catalog in the handshake and a reader
conditional in the server — a new tool, a new gate and a new document every time
a reader gains a switch.

**The shape is `setState`, mirroring `getState`.** Same struct, fields optional,
set the ones that are present. A reader that cannot set anything does not
announce the capability, the tool never runs, and the server carries no reader
conditional either way.

### The rule for what may be set

A setter invites a list of everything `getState` reports. That list is wrong, and
it needs a test as sharp as 0024's, for the same reason: so the *next* field can
be judged without re-running this argument.

> `setState` may set a mode **only where the reader already gives its user a
> command for it.** It adds idempotence, never capability.

The justification is 0023's, and it is the same one that admits this spec at all.
The agent simulates a user. A user *can* be in browse mode — there is a key for
it — so an agent asking to be in browse mode is asking for a state the user's own
reader offers, arrived at without the guessing the keystroke's non-idempotence
forces on automation. A setter for something no keystroke can reach would not be
simulating a user; it would be reaching into the reader, which is the product
under test.

### Applying it

| field | the user's own command (NVDA) | verdict |
|---|---|---|
| `browseMode` | `NVDA+space` | **in** — the demonstrated failure, and the whole first cut |
| `speechMode` | `NVDA+s` cycles it | passes the rule, **still out of the first cut** — see below |
| `sleepMode` | `NVDA+shift+s` | same |
| `inputHelp` | `NVDA+1` | **out** — input help exists to *describe* keys instead of acting on them, so an agent that turned it on would silently disarm every gesture it sent afterwards. Nothing wants this. |

`speechMode` and `sleepMode` pass the membership rule and are still not in the
first cut, for a reason the rule does not cover and the board should decide
explicitly: **they are the two settings that can leave a human unable to hear
their own machine.** [0032](0032-a-bound-on-the-silence.md) exists because a
silent session can do that by accident; `setState {speechMode: "off"}` would do
it deliberately, through a tool, and the silence cap counts *suppression* — not a
speech mode the agent switched off. Admitting them means answering that first.
The one-field cut costs nothing to reverse, because the shape is already "fields
optional".

---

## Part 3 — what ships

### 1. `setState`, answering with the state after

```jsonc
// -> setState
{ "browseMode": "browse" }

// <- result
{ "state":   { "browseMode": "browse", "speechMode": "talk",
               "sleepMode": false, "inputHelp": false },
  "changed": ["browseMode"] }
```

**It answers with the state *after*, not with `ok: true`.** The agent's next
question is always "am I there now", and 0025's finding is that a question
answered in the same round trip costs nothing. That also makes the tool
self-verifying: a caller that ignores the result is no worse off, and one that
reads it never needs the re-check row from Part 1.

**`changed` names the fields this call actually moved.** An empty list means the
reader was already in the asked-for state. That distinction is the repo's
recurring lesson — 0020/0021's `capturedAtLevel`, 0023's `ok: true`, 11.24's
`announced`: *one observable, two situations* is the defect, and the two here are
"you flipped it" and "it was already so", which a test asserting that its own
setup did nothing surprising has to tell apart.

### 1a. The set-domain is narrower than the get-domain

Board entry 11.17 names this and it is the sharpest thing in the entry, because
it is the one asymmetry a mirror-the-getter shape hides:

- **`"none"` is readable and not settable.** It means the focus has no
  `treeInterceptor` at all, which cannot be conjured. `setState {browseMode:
  "none"}` is **rejected outright**, not attempted — the tri-state was chosen
  over a nullable bool precisely so that "there is no document here" is a real
  answer, and the setter has to honour that rather than quietly widen it.
- **Even `"browse"`/`"focus"` can fail**, when the focused object is not a
  browsable document. That failure must say *the focused object is not a
  browsable document*, in those terms. Not a bare error, and above all **not a
  silent no-op**: `changed: []` already means "it was already so", and letting it
  also mean "this was impossible" would rebuild, inside the one field designed to
  separate two situations, a third one it cannot express. An agent that gets a
  bare failure goes looking in the wrong component — which is the failure 0027's
  reporter demonstrated and 0023 predicted.

`speechMode`, `sleepMode` and `inputHelp` are symmetric: what can be read can be
written. Only `browseMode` — the one field in the first cut — carries the
asymmetry, so it is not a general rule to build machinery around, but it is the
rule for the field that ships.

### 2. Setting what is already set does nothing at all

Not "presses the key twice and lands back where it started" — **nothing**: no
script runs, no `focusMode.wav`, no utterance. A human in a live session must not
be made to listen to a tone every time an agent restates a precondition, and an
agent must be able to state that precondition on every step without paying for
it. This is what makes it a setter rather than a wrapper around a toggle, and it
is why `changed` can be honest.

**And the compare happens INSIDE NVDA, not in the handler** — board entry 11.17's
own words, and the thing that actually fixes the bug rather than moving it. Read
`treeInterceptor.passThrough` and act only if it differs, in one step on NVDA's
main thread: then there is no window between the read and the write, and the
operation is idempotent *by construction* rather than by the caller's care. A
handler that read through the inspector, compared in the domain, and then asked
the setter to write would have rebuilt Part 1's race one layer down, with a
shorter window and the same shape. The layout below puts the comparison in the
adapter for exactly this reason.

### 3. The guidance says which one to reach for

`screenreader://guidance` teaches the read-compare-press-recheck loop by
omission. It should say: **to arrive at a mode, use `setState`; to test the
toggle itself, press the gesture.** That is the 0023 reconciliation below, in one
sentence an agent can act on.

### 4. It needs a live NVDA run

Board entry 11.17 says so, and it is right: the whole mechanism is NVDA's private
browse-mode internals, and the two claims that matter most — *setting what is
already set makes no sound*, and *a non-browsable focus says why* — are claims
about what a human hears and what an agent is told, on a real reader. The
implementing PR carries the checklist in its body, per AGENTS.md.

---

## Class/file layout

Per AGENTS.md, a spec names every file before the code exists.

| File | Role | Collaborators |
|---|---|---|
| `bridges/nvda/addon/.../domain/ports/state_setter.py` (new) | **port** — write the mode-state the reader offers its user a command for. Separate from `state_inspector.py` rather than added to it: a port called *inspector* that mutates is a mislabelled role, and the two are separately implementable — a bridge may well read a mode it cannot set. | Implemented by the NVDA adapter; held by the `AdapterSet`. |
| `bridges/nvda/addon/.../adapters/nvda_state_setter.py` (new) | **adapter** — NVDA's own browse/focus path (`treeInterceptor.passThrough`), never a synthetic gesture injection. **Owns the compare-and-set**: it reads and writes in one step on NVDA's main thread and answers whether it changed anything, so no window exists between the two (Part 3.2). It is also where "the focused object is not a browsable document" is detected, because that is a fact only NVDA holds. | Wraps NVDA; built by `AdapterFactory`. |
| `bridges/nvda/addon/.../domain/controllers/commands/set_state.py` (new) | **controller** — the `setState` handler. `mutates_reader = True`, so an observe-only session (0017) refuses it exactly as it refuses a keypress. Validates the request against the **set-domain** (Part 3.1a) before touching anything, asks the setter for each field present, and assembles `state` + `changed`. It does NOT compare — that would be the race, one layer down. | `SessionContext`, `state_inspector` (for the answer), `state_setter`. |
| `bridges/nvda/addon/.../domain/controllers/commands/registry.py` | registry (existing) | One handler entry. **No capability is added** -- see the capability question below. |
| `shared/nvda_mcp_wire/protocol.py` + `specs/wire/v1/protocol.md` | wire (existing) | `SetStateParams` (every field optional), `SetStateResult { state, changed }`, and the command name. **No new capability row**: `setState` joins `state` in the table, as `setConfig` sits with `getConfig`. `PROTOCOL_VERSION` 1 is pre-release (AGENTS.md) and both halves ship from this repo, so this costs a rebuild rather than a migration. |
| `server/domain/ports/state_writer.go` (new) | **port** — the server's mirror of the same. | Implemented by `adapters/bridge/json_lines_client.go`. |
| `server/domain/controllers/tools/set_state.go` (new) | **controller**, one per tool, gated on the new capability. Reuses `stateResult`, the struct `get_state` and the observation half already publish, so an agent reads one shape wherever it arrives from. | `ToolContext`. |
| `server/adapters/mcp/documents/guidance-method.md` | document (existing) | Part 3.3 — arrive with `setState`, test the toggle with the gesture. |
| `bridges/nvda/tests/unit/.../commands/test_set_state.py` (new) | unit | Already-there writes nothing and reports `changed: []`; a difference writes once and reports it; an absent field is never touched; `"none"` is refused before the adapter is reached; a non-browsable focus answers the specific reason rather than a bare failure or a no-op; observe-only refuses the whole command. |
| `server/domain/controllers/tools/set_state_test.go` (new) | unit | The gate, the pass-through, the result shape. |
| `server/tests/conformance/...` (existing) | conformance | The real binary against the real bridge, as every command has. |

### The capability question — settled 2026-08-20, against this spec's own first recommendation

`getState` is gated on `state`. Three options were on the table:

1. **`setState` joins `state`.**
2. **A new capability — `stateControl`.**
3. Per-field advertisement. **Rejected**: the per-toggle catalog 0027's ask was
   already turned down for, one layer further in.

This spec first recommended (2). **The decision is (1)**, and the argument that
turned it is one that was sitting in the tree the whole time: **`getConfig` and
`setConfig` both gate on `config`.** That is the exactly analogous pair — a getter
and a setter over the same subject — and it ships as one capability today.
Splitting `state` while `config` stays joined would leave an agent to remember
which pairs split and which do not, for no gain either of them can point at.

The deeper problem with (2) is that **the split does not carry the information the
asymmetry actually has.** The asymmetry here is real and it is PER FIELD, on the
one reader that exists: `getState` reports four modes, `setState` accepts one in
this cut and at most three ever, `inputHelp` is excluded on purpose, and
`browseMode: "none"` is readable and not settable. A `stateControl` string says
only "can set *some* modes", which the tool's existence already says, while the
per-field truth is carried by the set-domain rejection in Part 3.1a — which this
spec builds either way.

The case for (2) rested on a reader that reads modes it cannot set. No such
bridge exists; 0005's capability-as-unit is about differences that DO exist, and
its own examples (JAWS lacking braille, TalkBack lacking config) are whole groups
a reader does not serve, not halves of one. The wire is pre-release, so if such a
bridge ever arrives, adding the capability then costs a rebuild — which AGENTS.md
already accepts — whereas shipping one now that never differs from `state` is a
permanent extra concept in every handshake.

One smaller thing the reversal disposes of: `stateControl` would have been the
first camelCase string in a set of ten single lowercase words.

**What this means for the code**: `set_state` is gated on `CapabilityState`, the
`StateWriter` port is handed out on the same announcement as `StateInspector`,
and the port stays SEPARATE from the inspector even so — a port called *inspector*
that mutates is a mislabelled role, and one capability may hand out two ports
just as `config` does.

### A documentation defect found while drafting this

`protocol.md` §4 still reads *"`focus`, `state` and `config` are defined by this
contract and served by no bridge yet, so it does not announce them."* The NVDA
bridge has announced all three for some time — `NVDA_CAPABILITIES` in
`registry.py` lists ten groups — and 0025's state snapshot depends on `state`
being announced. Two documents disagree, and the wire contract is the one an
outside implementer would trust: the same class of defect as 11.24(a), which is
why it is named here rather than fixed silently. **It rides in this spec's PR**,
which is already editing that section to add a capability row.

---

### One thing the draft did not anticipate: an ignored field is a lie

`from_dict` **ignores** a field the params type does not declare. So a client
asking `setState {speechMode: "off"}` against a `SetStateParams` that declares
only `browseMode` would get `changed: []` back — the exact reading of "it was
already so". One observable, two situations, inside the one field built to
separate two situations.

So the handler refuses `speechMode`, `sleepMode` and `inputHelp` **by name, with
the reason each is withheld**, before parsing. That is not extra machinery for a
hypothetical: it is the same argument as Part 3.1a's "none", applied to the
fields the get-domain reports and the set-domain does not take.

## Its relationship to 0023 — not a contradiction

0023's stance is that the agent simulates a user, and that a tool reaching past
the user's own vocabulary tests the wrong product. `setState` looks like such a
tool and is not, on two grounds:

- **Everything it sets, the user's own keyboard can set.** That is the membership
  rule in Part 2, and it is what stops this growing into a control panel.
- **It is setup, not the test.** An agent verifying *"NVDA+space toggles browse
  mode"* presses `NVDA+space`; this spec does not touch that and must not be used
  for it. An agent verifying *"the search results announce their headings"* needs
  to **be** in browse mode first, and today it gets there by guessing. A test's
  setup being deterministic does not compromise what the test observes; it is the
  precondition for the observation meaning anything.

Worth one sentence because it is the line somebody will cross: **arrive with
`setState`, assert with the gesture.**

---

## What is deliberately not built

**A general "set any reader setting" tool.** That is `setConfig`, it exists, and
it is gated behind `config` — an agent with `getConfig`/`setConfig` can already
reach far more of NVDA than this. `setState` is the small, named, checkable
subset that corresponds to the user's own commands, and its value is exactly that
it is *not* general.

**`inputHelp`.** Part 2. A mode that describes keys instead of acting on them,
set by the thing that sends keys, is a trap with no use case.

**Setting focus.** Not a mode, not a toggle, and asynchronous — 0023's objection
in full force, unchanged by anything here.

**A `setState` that presses gestures underneath.** Tempting, because it would
need no new port. Rejected: a synthetic keypress goes wherever focus happens to
be, so it would inherit every failure mode this spec exists to remove, and it
would sound the tone Part 3.2 says must not sound.

---

## Honest limits

- **It is a race with the application, not a lock.** A page that finishes loading
  a millisecond after the write can restore browse mode by itself. `setState`
  removes the agent's own guessing; it cannot freeze NVDA's automatic switching,
  and nothing in this repo can. `changed` and the returned state describe an
  instant, like every other observation here.
- **It does not make the session hearing.** Every earcon that is not one of these
  modes stays inaudible to the agent — 11.11's half, and the reason these two
  entries are decided together rather than one being read as covering the other.
- **The NVDA adapter is version-coupled** in a way the read path is not:
  `browseMode`'s internals are private API. The read path samples state; the
  write path drives the reader's own switch. That belongs in the add-on's test
  matrix, and it is an argument for keeping the admitted set small.
- **`changed: []` is not proof of a quiet session.** It says this call changed
  nothing. Something else may have changed it a moment earlier, and the mode may
  differ again by the next call.

## Open questions — all settled 2026-08-20

- ~~**Does `changed` name fields, or carry before/after pairs?**~~ **Names.**
  Three reasons, ascending: the "after" is already in `state` on the same result,
  so a pair republishes half of it — which is the two-publishers-of-one-fact
  defect [0024](0024-a-session-the-agent-can-hear.md) Part 3.3 was withdrawn for,
  in the very conversation that agreed both specs. If more than names were wanted
  the honest shape would be `{keyPath, from}`, since "before" is the only thing
  not otherwise present. And for this cut `from` carries **no information at
  all**: the settable domain of `browseMode` is two values, so "it changed and it
  is now browse" already says what it was. The question reopens honestly the day
  a field with more than two settable values is admitted — `speechMode` would be
  one — and not before.
- ~~**Should `setState` be refused in `live` mode without an opt-in**, the way
  0024's normalisation is?~~ **No opt-in**, and the reason is sharper than "the
  human will hear it": **`setState` is strictly less invasive than a gesture the
  agent can already send.** `NVDA+space` is available in live mode today under
  `interact`, ungated by anything but that, and it reaches the same states with
  the added risk of flipping the wrong way. Gating the safe path while the unsafe
  one stays open would push agents back towards the toggle, which is the bug this
  entry exists to remove. The discriminator against 0024 is 0024's own test:
  normalisation changes a **configuration**, a persistent preference the user
  chose, for a whole session; this changes a **transient mode** the user's own
  keystroke changes many times a minute and hears change.
  **Recorded per FIELD, not per tool.** It holds because the first cut is
  `browseMode`. Admitting `speechMode` or `sleepMode` reopens it, because those
  can leave a human unable to hear their own machine — which is the same reason
  they are held back from the cut at all, and which gives the membership rule its
  second clause: *a mode that can leave the human unable to hear is not admitted
  on the strength of the rule alone.*
- ~~**Is `stateControl` the right name?**~~ **Moot**: there is no new capability.
  See the capability question above.

## Not in scope

The tone the agent cannot hear ([0024](0024-a-session-the-agent-can-hear.md),
board entry 11.11) and how an agent reads a whole document
([0026](0026-where-am-i-and-what-is-on-the-page.md)).
