# 0029 — connecting as somebody: personas

Status: **agreed 2026-08-17.** Board entries **11.19** (the persona exists and
travels) and **11.20** (the reader says what its vocabulary is). 11.19 is
implemented in the PR carrying this spec; 11.20 follows.

**Amended during 11.19's implementation, in two places**, per the workflow rule:

- **`adapters/nvda_cue.py` gains an optional `second_hz`** (5.3). The session
  start cue is two *ascending* tones and then speech, where the existing helper
  beeped twice at one pitch. Extending it beats a second implementation here,
  for the reason its own header gives: the tricky parts — speaking past the
  suppression filter, spacing the beeps, staying on NVDA's main thread — are
  exactly the parts worth having once. The announce and askUser cues are
  unchanged, because the parameter defaults to the first pitch.
- **`fakes/connection_control.go` copies the persona onto the scripted session**,
  as the real dialer does. Without it every caller reading the persona back
  looked broken while being correct — the fake, not the code, was the thing
  that had lost the field.

One thing the tests caught that is worth recording rather than quietly fixing:
`TestNoPersonaTextNamesAKeystroke` failed on its first run, because the `user`
profile's example finding said *"Tab cycles through the message field"*. The
document that states the rule broke it, in an example, within an hour of the
rule being written. The test is therefore not paranoia, and it is the reason
that check exists at all rather than being left to review.

**Corrected 2026-08-17, before agreement, in the part that matters most.** The
first draft followed board entry 11.19 in describing `user` as a *competent*
screen reader user, for whom "a workaround is a legitimate win and object
navigation is exactly what a competent user reaches for". **That is wrong, and it
was the load-bearing sentence.** The ordinary user is not a screen reader expert;
their vocabulary is the one the ARIA authoring practices assume of the person at
the keyboard; and a task that needs object navigation, the review cursor or a
simulated click has **failed**. Parts 1 and 2 are rewritten around that, and the
third persona is widened from *add-on developer* to **`expert`**, which covers
the developer and also the accessibility expert inspecting a site with every
instrument in hand. Board entry 11.19 carries the same amendment.

**Corrected again the same day, on where the documents live.** The draft shipped
*three* static per-persona resources from the server, holding each stance
together with the vocabulary it may use. **TalkBack disposes of that**: it has no
keyboard and does not run on Windows, so a server-owned document naming Tab,
Alt+Down or Windows+Tab would be issuing instructions that do not exist on the
reader being driven. There is now **one concrete document, supplied by the
bridge** (Part 4), and the server keeps a single general one that states only
what survives every platform: what a screen reader is, how this MCP is meant to
be used, and what the personas are — enough to choose one, and to confirm that
choice with the human, before connecting.

**And re-cut into two different PRs, 2026-08-17.** The board split these entries
by lane — server half, then reader half — which was right while the server owned
the vocabulary and is not right now that it does not: shipping the server half
alone would tell a `user` session its vocabulary is bounded and give it no way to
learn what is in it. The seam is now **mechanism, then document**: PR 1 makes the
persona exist, travel and be recorded; PR 2 gives the reader its own document.
Both touch both lanes. Part 6 says exactly which changes belong to which.

**One spec for both**, because the split *between* them is the design: the server
states what a persona is and the rule its vocabulary obeys, each bridge
enumerates that vocabulary on its own reader, and neither document works alone.

---

## Part 1 — the problem: a finding with no stance behind it

Everything this server has built so far answers *what the reader did*. Nothing
says *who was asking*, and without that a finding cannot be read.

Take the one claim this whole project exists to support: **"that control is
reachable."**

- Said by a session standing in for an **ordinary user**, it can only mean *I got
  to it with the keys any interface is entitled to assume I have.* If it took
  object navigation, it was not reached at all — **that is the finding, and the
  task failed.**
- Said by a session standing in for an **expert**, the same sentence means *the
  reader can get to it*, object navigation included, because the expert is
  finding out how the thing works and has every instrument in hand. That claim is
  true and useful, and it is perfectly compatible with a page an ordinary user
  cannot operate.

Two sessions, the same tool calls, the same speech, the same word *reachable* —
and one of them is a pass while the other is consistent with an unusable
interface. Today nothing in a session record, in `screenreader://info` or in any
result distinguishes them, so a reader of the evidence afterwards cannot tell
which claim was being made. The evidence is complete and the claim is missing.

So an agent connects **as somebody**, says so before it starts, and the
declaration travels with everything the session produces.

## Part 2 — the three personas

### 2.1 Three questions, not three ranks

Each persona asks a different question, and that — not seniority — is what
separates them:

- **`user` — *can I do this?*** with only the keys an interface may assume of me.
- **`validator` — *is this right?*** driven exactly the same way, but observed
  precisely enough to say what is wrong.
- **`expert` — *how does this actually work?*** with every instrument the reader
  has.

The tempting model is a ladder, and it is wrong. **`user` and `validator` drive
with the *same* restricted vocabulary**, so that the word *reachable* means the
same thing in both their reports; what the validator adds is not freedom to act
but power to observe. **`expert` differs in kind rather than in rank**: it is the
only one for which nothing is off limits, because what it owes is understanding
rather than a verdict.

So **observation power rises `user` → `validator` → `expert`, while action
latitude does not rise between the first two at all.** That is board entry
11.19's formulation, and the 2026-08-17 correction is what finally makes it true:
the earlier draft gave the *user* more action latitude than the validator, which
left the ordering incoherent.

### 2.2 The rule is universal; the vocabulary is the platform's

The ordinary user has a bounded toolkit, and on a Windows desktop reader it is
the one the ARIA authoring practices assume of the person at the keyboard: Tab
and Shift+Tab between controls, the arrows within a list or radio group or menu,
Space to check a checkbox, Alt+Down and Alt+Up to open and close a combo box,
typing into an edit field, first-letter and single-letter navigation, browse and
focus mode — plus the reader's ordinary **reading** commands: report the focused
object, report the title, read the window, read the line, say-all.

**But that list is not this document's to state, and an early draft of this spec
was wrong to claim it was.** It asserted the list was reader-agnostic because Tab
and the arrows are the same on NVDA and JAWS. **TalkBack breaks it.** There is no
keyboard, and there is no Windows: an ordinary TalkBack user swipes, explores by
touch, and works the local and global context menus. A document that told such a
session to press Alt+Down would be issuing instructions that do not exist.

So the vocabulary is **platform-specific**, and it goes where every other
concrete thing goes — the bridge (Part 4). What this document states is the part
that survives the platform change:

> **The ordinary user's vocabulary is whatever the platform's own accessibility
> contract assumes of an ordinary user of that platform.** Nothing beyond it is
> available to the `user` persona, and needing something beyond it is a
> **failure**, not a workaround.

And the test for what falls inside it, which is the genuinely portable part:

> **A command that re-reads what is already there is in. A command that reaches
> what focus cannot is out.**

Reading commands make no claim about reachability — a user who presses
report-title has routed around nothing and hears only what was already in front
of them, which is why they are inside the vocabulary on every platform. Object
navigation, the review cursor, a simulated click and TalkBack's equivalents make
exactly that claim, which is why they are the boundary. **The rule is normative
and reader-agnostic; the instances are the bridge's to enumerate**, which is
Part 4's precedence structure (4.1) applied to the vocabulary itself.

Two consequences that are easy to miss:

**The boundary is a rule, not a costume.** An earlier draft worried that an agent
cannot honestly simulate *not knowing* a command, and that a persona built on
pretended ignorance would produce a guess about a hypothetical person rather than
an observation. Naming the vocabulary dissolves that: nobody is asked to forget
anything. The commands are known and **out of scope**, the way a load test is not
allowed to warm its own cache. The task that then fails is a fact about the
interface.

**The reading commands have to be inside it, or the method document contradicts
itself.** Spec 0023's loop — act, settle, listen, orient, escalate — has *"press
the reader's own report-the-focused-object command and listen"* as step 4, and
that document is deliberately persona-independent (3.6). A `user` persona
forbidden to ask the reader where it is could not follow the guidance every
persona is told to follow.

### 2.3 What the validator adds is observation, not latitude

The validator drives exactly as the user drives, with the same vocabulary and the
same limits. If it drove more freely, its central claim would decay into the
expert's: *reachable* would stop meaning *reachable by ordinary means*, which is
the only thing it was asked.

What it gains is the ability to say **what** is wrong, not merely that something
is. `get_focus_info` and `get_state` let it state findings a user can only feel —
canonically, a control that claims a name and a role and yet announces nothing
when it receives focus, which is a bug invisible from either observation alone
(spec 0023's "asserting in a test", which turns out to be *this persona's*
paragraph rather than everyone's).

It may reach outside the ordinary vocabulary in exactly one circumstance: to
**characterise a failure it has already found** — proving that a control exists
in the reader's object model and simply cannot be focused — and never to get past
one. When it does, it says so, naming what it used and what that showed.

### 2.4 The expert: nothing is off limits, because the question is *how does this work*

The third persona wants to inspect the whole thing. It reads the reader's own
event log, tracks what happened around a keystroke, and works out the mechanism:
`get_log`, `wait_for_log`, `get_log_position` and `set_log_level` (specs 0020 and
0021) exist for this stance more than any other, alongside `get_config`,
`set_config`, `get_focus_info` — and object navigation and the review cursor,
which here are ordinary equipment rather than a boundary being crossed.

**Widened from the board's "add-on developer" on 2026-08-17.** The developer
debugging their own add-on is one instance; an accessibility expert taking a site
apart to find out *why* it behaves as it does is the same stance with a different
subject, and "developer" is the wrong word for that person. `expert` covers both,
and the distinguishing mark holds for either: **the screen reader stops being the
instrument you observe through and becomes part of what you are examining.**

The obligation that comes with the latitude is to **say which route was taken**,
because a finding of this persona's will be read by someone standing in one of
the other two, for whom the same sentence means something narrower.

### 2.5 The three stances, as shipped

These are the short forms, and they are **normative text**: this is what travels
back in `connect_reader`'s result, so the wording is settled here rather than in
review of the implementing PR.

| value | the question it asks | success is | the sharp edge |
|---|---|---|---|
| `user` | *can I do this?* | the task is done **inside the platform's ordinary vocabulary** | needing anything that reaches past focus — object navigation, a review cursor, a simulated click, or this reader's equivalent — is a **failure**, not a workaround |
| `validator` | *is this right?* | the answer is true and precisely characterised | drives with the **same** vocabulary as `user`; what it gains is observation, not latitude |
| `expert` | *how does this actually work?* | you understand the mechanism | nothing is off limits — the reader's log, config and internals are the instruments you came for |

**`user`** — *You are standing in for an ordinary screen reader user, not an
expert, and your vocabulary is bounded. It is whatever this platform's own
accessibility contract assumes of an ordinary user of it — the keyboard
interaction its interface patterns specify — together with your reader's ordinary
reading commands, which are inside the boundary because they only re-read what is
already in front of you. Anything that reaches a control your focus cannot reach
is outside it. Read `screenreader://reader-guidance` for the exact list on the
reader you are driving: it is the only document that can name it, because these
are different commands, and sometimes not commands at all, on a different
platform.*

*If the task cannot be done inside that boundary, **the task has failed**. What
lies outside it is not a workaround available to you; those are commands this
persona does not have. Do not reach for one to rescue a run.
Report where it stopped and what you last heard. You may say that another stance
could investigate further — you may not borrow its result and call the task
done.*

**`validator`** — *You are asking whether this interface is correct and usable by
ordinary means, and your answer is the deliverable, not a completed task. **Drive
exactly as `user` drives**, with the same vocabulary and the same limits, so that
"reachable" means the same thing in your report as in theirs. What you gain is
not freedom to act but power to observe: `get_focus_info` and `get_state` let you
state findings a user can only feel — a control that claims a name and a role and
yet announces nothing when it receives focus is a bug visible from neither
observation alone. You may reach outside the ordinary vocabulary in one
circumstance only: to **characterise a failure you have already found**, never to
get past one. When you do, say so, naming what you used and what it showed.*

**`expert`** — *You are here to find out how the thing actually works, not to
return a verdict. Nothing is off limits: object navigation and the review cursor,
the reader's own event log (`get_log`, `wait_for_log`, `get_log_position`,
`set_log_level`), its configuration (`get_config`, `set_config`) and its view of
the focused object (`get_focus_info`) are the instruments you came for rather
than shortcuts to feel bad about. Success is understanding the mechanism, which
usually means the reader's account and the application's behaviour side by side.
Say which route you took: your findings will be read by someone standing in one
of the other two stances, for whom the same sentence means something narrower.*

Each full document (Part 3.5) additionally carries: what the persona is *for*, an
example of a finding stated in its vocabulary, what evidence a report from it
must contain, and — for `user` and `validator` — the explicit note that the
boundary is **not enforced**, and what to do instead of relying on a wall
(Part 3.2).

## Part 3 — the decisions: the persona itself

### 3.1 `persona` is required on `connect_reader`, with no default

Required, exactly like `mode` and `reader`. Not optional, and **not defaulted to
`user`**.

A default here is worse than an omission: it silently attributes a stance nobody
chose, and a validator-shaped claim resting on a defaulted `user` session is a
claim nobody can withdraw, because nobody knows it was made. And optional-with-no
-default fails differently: the field would be omitted by exactly the agents that
most need to choose one, and `unstated` would become the commonest value in every
session record.

The cost is one enum choice on a call an agent makes once per session. The error
message for a missing or unknown value lists all three with their success
criterion, so a wrong guess self-corrects in the same turn — the pattern
`connect_reader` already uses for an unknown reader name, and here it doubles as
the teaching moment.

### 3.2 Instruction only, and the trigger that would change that

The boundary that now matters most — `user` and `validator` may not leave the
ordinary keyboard vocabulary — **cannot be enforced by this server**, and a fence
that covers everything except the thing it was built for is worse than no fence.

Object navigation is `pressGesture` with the reader's own keys. Recognising it
would mean teaching this server one reader's key map, which spec 0005 principle 2
forbids and `ToolCatalog` could not express in any case. A server-side gate could
therefore withhold `get_focus_info` while a `user` session object-navigates its
way to a false pass: **partial enforcement that reads as total**, buying nothing
where the risk is and costing an 11.6-shaped "why is this tool missing" confusion
where it is not.

**A bridge could enforce it, and that is worth writing down rather than
discovering later.** Unlike the server, a bridge knows its own key map — NVDA can
resolve a gesture to the script it is bound to, so "this keystroke *is* object
navigation" is an exact question there, not a heuristic one. Once 11.20 hands the
bridge the persona, refusing or flagging an out-of-vocabulary gesture becomes
possible for the first time. **It is deliberately not built.**

**The decision, 2026-08-17:** *deliver the right information to the agent
according to the persona it declared; if violations then turn out to be common,
gate.* Ship the instruction, watch the session records, and let evidence rather
than anticipation decide whether a wall is ever built. That names the trigger,
which is what keeps *not yet* from silently meaning *never* — and it keeps
something a gate destroys in the meantime: **an agent that steps outside its
persona and says so has produced evidence**, where an agent that hits a wall has
produced a failed run. The deliverable is the report.

### 3.3 Chosen before connecting, and fixed for the session

The persona determines what the run *means*, and meaning cannot be retrofitted
onto a session that already ran. So it is a `connect_reader` argument, the
documents are static and readable before any session exists, and changing persona
means `disconnect_reader` then `connect_reader` again — which is correct rather
than inconvenient, because it is genuinely a different run.

This is **not** because the human is unreachable mid-session: `announce` and
`ask_user` exist. It is the wrong moment, not an impossible one.

### 3.4 The stance rides back in the connect result

A persona the agent declares but never reads is a label, not an instruction. The
first external run (spec 0027) is the evidence: that agent never read
`screenreader://guidance` either, and dropped to PowerShell for something the
document would have told it.

So `connect_reader` returns, alongside the reader and its capabilities:

- `persona` — what was declared;
- `stance` — the short form from Part 2.5, in full;
- `readerGuidance` — the URI of the reader's own concrete document, **present
  only when the connected bridge announced the `guidance` capability** (Part 4).
  This is the one an agent most needs and the one it cannot have read in advance.

The short form and not a page of prose: connect is the one moment the agent is
guaranteed to be reading, but text repeated in every result is text paid for on
every reconnect, and the concrete instructions are one resource read away.

### 3.5 One general document, and the persona profiles are composed into it

There is **one** server-side document, `screenreader://guidance`, and it holds
only what is true of every screen reader on every platform:

1. **what a screen reader is** — the ground an agent needs before any of this
   means anything;
2. **how this MCP is expected to be used** — 0023's method, unchanged: act,
   settle, listen, orient, escalate; a successful result means delivery, not
   consequence;
3. **what the personas are**, with a profile of each: what it stands for, what
   counts as success, and what it must not do — stated as the *rule* of 2.2
   rather than as any platform's key list.

Point 3 is why the document must stay readable **before connecting**: the persona
is chosen then, and an agent may want to put the choice to the human first. It
cannot do that with `ask_user`, which needs a session — so it asks in its own
conversation with the person who started it, which is another reason the profiles
have to exist somewhere reachable without a reader.

**The profiles are composed from the domain, not written into the resource
text.** `entities.Persona` holds `Stance()` (the short form, which the connect
controller renders) and `Profile()` (the longer one), and the guidance resource
builds its persona section by iterating `AllPersonas()`. So a persona cannot be
added without a profile, the connect result and the document cannot drift apart,
and the domain keeps the text a *domain controller* needs — which it must, since
the domain may not import an adapter.

### 3.6 The 0023 amendment is larger than a pointer

0023's guidance document opens with *"The stance: you are standing in for a
user"*, and its introspection section tells the agent that `get_focus_info` and
`get_state` "are not how you find out where you are". Under personas, **both of
those sentences belong to particular personas**: the first is `user`'s and
`validator`'s, and the second is actively wrong for the `expert`, for whom the
reader's own model is part of the subject.

Since there is now no separate persona resource to point at, guidance **absorbs**
the stance rather than delegating it: the opening section becomes "what a screen
reader is" plus the three profiles, the method sections stay exactly as they are
(they never varied by persona), and the introspection section gains the
`expert`'s exception. What it must **not** absorb is anything concrete — it keeps
saying "your reader's report-focus command", never "NVDA+Tab", because after this
correction that restriction is the whole reason the bridge's document exists.

**This is an amendment to spec 0023, riding in the 11.19 PR**
per the workflow rule.

### 3.7 Declared everywhere the session is described

`status`, `screenreader://info`, and `screenreader://session-record` each gain the
persona, because each is somewhere a person or an agent reads a session back
afterwards and has to know what its claims meant.

The session record needs one thing more than a passthrough, and it is easy to
miss: the record is a **bounded** list of calls (`MaxRecordedCalls`, oldest
evicted), so in a long session the `connect_reader` call carrying the declaration
can age out of the very record that is supposed to preserve it. The persona
therefore goes on the **document**, read from the live session, not left to be
recovered from a call that may no longer be there.

## Part 4 — the decisions: the reader's own document

**The server defines the personas; each bridge defines what that persona should
and should not use on its reader.** The rule is reader-agnostic and belongs to
the server ("do not route around the problem"); the instances are reader-specific
and only the bridge author knows them — NVDA's escape hatches are object
navigation and the review cursor, JAWS's is the JAWS cursor.

This also answers a gap 11.14 could only flag: **readers differ in what they
offer, not merely in which keys they use for it.** JAWS has a native way to list
open windows; NVDA has none. A static reader-agnostic document has no way to say
so, and "the agent already knows" is not a safe assumption. A bridge-supplied
document can say it, and it ships with the reader it describes, so it cannot rot
in the one place nobody checks.

### 4.1 Precedence: the server is normative, the bridge instantiates

Stated in the wire contract, and — because the server never parses the bridge's
text and so can never check it — **stated again in the frame the server wraps
around it** when serving the resource:

> This is `<reader>`'s account of how to hold the `<persona>` stance on this
> reader. The stance itself is normative and lives at
> `screenreader://guidance`. A bridge may name its reader's escape
> hatches and the commands that constitute them; it may not redefine what the
> persona is for or what counts as success. Where the two appear to disagree, the
> stance wins.

Framing rather than parsing is the whole trick: the server enforces precedence
where precedence is actually decided — in the agent's reading — without acquiring
an opinion about a document written by a bridge it has never seen.

### 4.2 An unknown persona must degrade, never break — so it crosses the wire as a string

This has to be designed in on day one, or adding a fourth persona becomes a
synchronised release across every bridge. Three decisions carry it:

1. **`persona` is a plain `str` in `HelloParams`, not an enum.** If the shared
   contract typed it as a closed enum, `from_dict` would raise on an unrecognised
   value and **the handshake would fail** — a newer server would be unable to
   connect to any existing bridge the moment a persona is added. A string cannot
   fail that way. The known values are documented in the protocol prose as
   informative, and the server — which validates at its own tool boundary — stays
   the authority on the set.
2. **A bridge must not reject an unknown persona.** Written into §4 of the
   protocol beside the existing "must ignore an unknown capability string" rule,
   which is the same carve-out for the same reason.
3. **`getGuidance` says whether it recognised it.** `recognised: false` with the
   bridge's general guidance is a real, useful answer; silence would leave the
   agent believing it had persona-specific instruction when it had not.

The field defaults to `""` so an *older server* — one that does not know about
personas — still handshakes with a new bridge. Both directions degrade.

### 4.3 `getGuidance` takes no parameters

The persona is fixed at `hello`; `getGuidance` answers for the session's persona
and nothing else.

A `persona` parameter would let an agent fetch the validator's instructions from
a `user` session, which quietly undoes 3.3: the persona would become a thing you
consult rather than a thing you are. It also removes any question of what happens
when the two disagree.

### 4.4 Lazy, cached for the session, and served as an opaque resource

**Lazy**: nothing is fetched at connect. The round trip happens on the first read
of `screenreader://reader-guidance`, so a session that never asks never pays.

**Cached**: the document is static for the session, so a second read costs no
round trip. The cache is keyed on the live connection itself, so a disconnect and
reconnect cannot serve the previous session's text.

**Opaque**: the server transports and frames the markdown and never parses it.
That is what lets a bridge author write for their own reader without negotiating
a schema with this server.

**Always registered, like the other three resources.** An agent that reads it
with no session, or against a bridge that does not announce `guidance`, gets a
document saying so and pointing at the server's persona document — not a missing
resource. A bridge with no reader-specific instructions to give simply does not
advertise the capability, and everything degrades to the server's documents
alone.

### 4.5 Timing: chosen before, instantiated after

The persona is chosen before connecting and its reader-specific instantiation can
only exist afterwards. That is coherent and surprising, so it is written down, and
`connect_reader`'s result names the resource at the earliest instant it exists
(3.4) rather than leaving the agent to discover it.

```mermaid
sequenceDiagram
  accTitle: When each half of a persona's guidance becomes available
  accDescr: Before connecting, the agent reads the server's static persona document, which is normative and reader-agnostic. It then calls connect_reader with the persona, and the server carries the declaration to the bridge in hello and returns the short stance plus the reader-guidance URI. Only after the session exists can the agent read the reader-guidance resource; the server fetches the bridge's instantiation with getGuidance on that first read, frames it with the precedence rule, and caches it for the rest of the session.
  participant Agent
  participant Server as MCP server
  participant Bridge

  Agent->>Server: read screenreader://guidance
  Server-->>Agent: what a reader is, the method, the three persona profiles
  Agent->>Server: connect_reader(reader, mode, persona=validator)
  Server->>Bridge: hello(mode, persona=validator)
  Bridge-->>Server: capabilities include guidance
  Server-->>Agent: persona, short stance, reader-guidance URI
  Agent->>Server: read screenreader://reader-guidance
  Server->>Bridge: getGuidance
  Bridge-->>Server: NVDA's instantiation for validator (opaque markdown)
  Server-->>Agent: framed with the precedence rule
  Note over Server: cached for the session; a second read costs no round trip
```

### 4.6 What the NVDA bridge says

The server's document states the *rule* — the ordinary user's vocabulary is
whatever the platform's accessibility contract assumes, and re-reading is in
while reaching is out (2.2). **The bridge's document is where that becomes an
actual list of actual gestures**, and after the second correction it is the only
place any of it appears. It has two sections, because most of what an agent needs
here is the same whoever it is standing in for.

**The common section — identical for every persona.** It is the larger half:

- **the ordinary vocabulary itself, enumerated for this reader on this
  platform**: on NVDA, Tab and Shift+Tab, the arrows, Space on a checkbox,
  Alt+Down and Alt+Up on a combo box, typing, first-letter and single-letter
  navigation, browse and focus mode. This is the list 2.2 declines to state,
  because on a TalkBack bridge the same section would enumerate swipes, explore
  by touch and the local and global context menus, and every word of the NVDA
  list would be false.
- **the desktop's own keys**, which no reader-agnostic document could name:
  Windows+D to reach the desktop, Windows+Tab and Alt+Tab to move between
  windows, opening and navigating the Start menu. Spec 0023 tells the agent to
  *name* the application rather than cycle to it, and 11.14 established that this
  is setup rather than testing — but it stays the first thing any agent needs,
  and the reader fixes the platform, so this is the one document that can supply
  it. The gesture limit still applies and must be repeated here: a gesture is a
  discrete press and release, so a switcher that lives only while a modifier is
  held is not expressible.
- **the reader's ordinary reading commands, as gestures**: NVDA+Tab to report the
  focused object, NVDA+T for the window title, NVDA+B to read the whole window,
  read-current-line and say-all. These are what 0023's *orient* step means on
  this reader, and 2.2 puts them inside every persona's vocabulary.
- **the standard control interaction as it actually behaves here** — arrows in a
  list, Alt+Down on a combo, Space on a checkbox, Tab between controls, browse
  and focus mode and how NVDA switches between them.

**The per-persona section** is the smaller half, and it is where the split earns
itself:

- **what is outside the vocabulary, named with the gestures that constitute it**:
  object navigation, the review cursor, and simulated clicks — in both the
  desktop and the laptop layout, because a document that named only one would be
  wrong on half the installations. **This is the list a `user` session needs in
  order to recognise what it must not reach for**, which is why naming the
  gestures matters more than naming the concepts.
- **what is *not* outside it, and would be wrongly assumed to be**: browse mode,
  single-letter navigation, and the reading commands above. They are how a user
  reads, not a way around a break — a distinction no reader-agnostic document
  could draw, and exactly the kind of thing an agent would otherwise guess at.
- **`user`**: needing anything on the first list is a failed task. Report where
  you stopped; do not route around it.
- **`validator`**: same limit, and if you step outside to characterise a failure
  you have already found, say which command you used and what it showed.
- **`expert`**: all of it, plus NVDA's log, its speech-viewer semantics and its
  configuration — the reader is part of what you are examining.
- **what NVDA does not offer**: no native "list open windows" command — the
  concrete instance of "readers differ in what they offer", and the thing 11.14's
  static guidance could only warn about in the abstract.

**One document, composed by the bridge.** `getGuidance` returns the common
section and the persona's section as a single markdown text; there is no second
call and no structure for the server to reassemble. That keeps the wire exactly
as 4.3 describes and the text exactly as opaque as 4.4 requires — and it means a
bridge author writes the common half once instead of pasting it into three
documents that will drift.

The persona also lands in the **bridge's own transcript** at `hello`, so the
human-facing artifact on the reader's disk says what the session was standing in
for.

### 4.7 The human at the machine hears the persona

The bridge already tells the person sitting there that control was taken: two
ascending tones when a session establishes, two descending at teardown
(`SessionSignals`), played rather than spoken so they are heard even while silent
mode suppresses captured speech. **The tones say something has taken the reader.
They cannot say what it is standing in for.**

So `session_started` carries the persona, and the NVDA adapter follows its
ascending pair with one spoken line — *"MCP session open, as accessibility
validator"* — through the live synth, the same path `cue_and_speak` already uses
to be heard past the suppression filter.

**Bridge-side, not server-side**, although the server could perfectly well call
`announce` itself after a successful handshake. Three reasons, and the third is
the decisive one:

- **Order.** The tones are played by the bridge at the instant the session
  establishes. A server-side announcement arrives a round trip later and would
  interleave with them instead of completing them.
- **Language.** The utterance is an add-on string and can be localised, like
  every other word this add-on says to its user. Nothing the server speaks can
  be — it has no idea what language the person at the reader uses.
- **It would be built twice.** 11.19 has no persona at the bridge, so a
  server-side announcement built now would be replaced by this one in 11.20.
  That is precisely the waste [0028](0028-when-was-that-said.md) refused when it
  declined to put a stamp on results 0025 was about to reshape.

It joins the panic gesture and the control UI (specs 0011, 0016) as something the
human at the machine gets without asking, and it is guarded exactly as the tones
already are: a courtesy utterance that fails must never break a session that
established.

An **unrecognised** persona is spoken as received — the bridge does not have to
recognise a value in order to say it, and a human hearing an unfamiliar word is
better served than a human hearing nothing. An **absent** one, from a server that
predates this spec, leaves the tones alone exactly as today.

### 4.8 The payoff beyond documentation: auditable, not enforced

Once a bridge *names* the commands that fall outside the ordinary vocabulary, a
`user` or `validator` run becomes **auditable after the fact**: the session
record already stores every call with its params, so those gestures can simply be
looked for in it afterwards. The rule stays unenforced — no gate, no partial
fence — but it stops being unverifiable.

**This is also what makes 3.2's trigger checkable rather than rhetorical.** The
decision was to gate *if violations turn out to be common*; without a bridge that
names the gestures, nobody could ever tell whether they were. The audit is the
instrument that would justify the gate, and it ships first — which is the right
order, because it costs nothing and forecloses nothing.

Note also: if the object-navigation tool spec 0023 anticipates is ever built, the
restriction becomes gateable at the server too. That is an argument for building
it as its own tool rather than as more `pressGesture`.

## Part 5 — class and file layout

### 5.1 Server — the persona itself

| File | Role | Change |
|---|---|---|
| `domain/entities/persona.go` | **new** — entity | `Persona` string type; `PersonaUser`/`PersonaValidator`/`PersonaExpert`; `ParsePersona` (error lists all three with the question each asks); `Stance()` (short, for the connect result); `Profile()` (longer, for the guidance document); `AllPersonas()`. Mirrors `capture_mode.go`, plus the two texts (3.5) |
| `domain/ports/session_dialer.go` | port | `SessionOptions.Persona`. Doc amended: these are what the AGENT chose for the session, of which the wire fixes some at `hello` — persona joins that set in 11.20 |
| `domain/entities/reader_session.go` | entity | `Persona` field, with the comment that it is the one field the agent DECLARED rather than the bridge announced — until 11.20, when the bridge records it too |
| `adapters/bridge/handshake.go` | adapter | copies `opts.Persona` into the `ReaderSession` it builds, in the same place it copies the confirmed mode — so 11.20 changes one line, not a path |
| `domain/controllers/tools/connect_reader.go` | controller | required `persona` argument; result gains `persona` and `stance` |
| `domain/controllers/tools/status.go` | controller | `statusSession.Persona` |
| `adapters/mcp/info_resource.go` | adapter | `info.Persona` |
| `adapters/mcp/session_record_resource.go` | adapter | the document gains `persona`, read from a `SessionSource` (3.7); the adapter gains that second source |
| `adapters/mcp/guidance_resource.go` | adapter | the 0023 amendment (3.6): gains "what a screen reader is" and a persona section **composed by iterating `AllPersonas()`** rather than written inline; introspection section gains the `expert`'s exception; still names no reader's keys. The text stops being a bare `const` and becomes a `const` preamble plus the composed section |

No new tool, no capability change, no wire change, no bridge change.

### 5.2 Shared wire contract

| File | Role | Change |
|---|---|---|
| `shared/nvda_mcp_wire/protocol.py` | the contract | `HelloParams.persona: str = ""` (4.2); `Command.GET_GUIDANCE`; `Capability.GUIDANCE`; `GetGuidanceResult{persona: str, recognised: bool, text: str}` |
| `specs/wire/v1/schema.json` | generated, CI drift gate | regenerated |
| `specs/wire/v1/protocol.md` | hand-written prose | §3 gains `persona` and why it is a string; §4 gains the `guidance` capability row and the "must not reject an unknown persona" rule beside the unknown-capability one; §5 gains `getGuidance` |

Pre-release v1 permits the shape change (§8); both implementations are in-tree
and the `conformance` job covers them.

### 5.3 Bridge (lane 1)

| File | Role | Change |
|---|---|---|
| `domain/entities/reader_guidance.py` | **new** — entity | NVDA's **common** section, its per-persona sections, and the general fallback; `guidance_for(persona) -> tuple[str, bool]` composes common + persona into one text and reports whether the persona was recognised. An unrecognised one gets the common section alone, which is most of the value (4.6) |
| `domain/controllers/commands/get_guidance.py` | **new** — command handler | reads the session's persona, returns `GetGuidanceResult`. `marks_log = False`: it touches nothing NVDA logs |
| `domain/controllers/commands/session_context.py` | parameter object | `persona: str`, installed by hello like the other session-scoped state |
| `domain/controllers/commands/hello.py` | handler | records `params.persona` into the context and the transcript |
| `domain/ports/transcript.py`, `adapters/file_transcript.py` | port + adapter | `session_opened` also records the persona |
| `domain/ports/session_signals.py` | port | `session_started(persona: str)` — the signal that already means "control was taken" now carries what it was taken *as* (4.7) |
| `adapters/nvda_session_signals.py` | adapter | keeps the ascending pair, then speaks one localisable line through the live synth, past the suppression filter |
| `adapters/nvda_cue.py` | adapter helper | **amended**: an optional `second_hz`, so the ascending pair can reuse the one definition of "beep, then speak past the suppression filter" |
| `domain/controllers/session.py` | controller | passes the session's persona when it plays the start signal; still guarded, so a failed utterance cannot break an established session |
| `domain/controllers/commands/registry.py`, `wiring.py` | registry + composition root | register the handler; announce the `guidance` capability |

### 5.4 Server (lane 2) — the reader's document

| File | Role | Change |
|---|---|---|
| `adapters/wire/wire.gen.go` | generated binding | regenerated; CI diffs it |
| `domain/ports/guidance_reader.go` | **new** — port | `GuidanceReader{ Guidance() (ReaderGuidance, error) }` and its DTO. Nil on `ReaderConnection` unless the capability was announced — the same structural gate every other capability uses |
| `ports/session_dialer.go`, `adapters/bridge/handshake.go` | port + adapter | `ReaderConnection.Guidance`, wired when `guidance` is announced; `opts.Persona` now goes into `hello` |
| `adapters/bridge/json_lines_client.go` | adapter | the `getGuidance` call and its mapping |
| `domain/controllers/reader_guidance.go` | **new** — controller | the lazy fetch, the per-session cache keyed on the live connection, and the degraded documents for "no session" and "capability not announced" (4.4) |
| `adapters/mcp/reader_guidance_resource.go` | **new** — adapter | `screenreader://reader-guidance`; wraps the opaque text in the precedence frame (4.1) |
| `domain/controllers/tools/connect_reader.go` | controller | result gains `readerGuidance`, present only when the capability was announced |
| `wiring/wiring.go` | composition root | builds the controller, hands it to the resource |

**`guidance` is the first capability that gates a resource rather than a tool**,
so `ToolCatalog` is untouched — worth saying out loud, because every previous
capability arrived by adding names to it.

### 5.5 Tests

| File | Tier | Asserts |
|---|---|---|
| `server/domain/entities/persona_test.go` | unit | parsing, the error naming all three, and that **every** value in `AllPersonas()` has a non-empty stance and document |
| `server/domain/controllers/tools/connect_reader_test.go` | unit | `persona` is required; an unknown value is refused at the boundary with the listing; the result carries persona, stance and URI |
| `server/adapters/mcp/*_test.go` | integration (in-memory MCP client) | the guidance document contains a profile for **every** value in `AllPersonas()` and names no reader's keys; info, status and the session record all report the persona; the session-record document keeps it after the connect call has been evicted |
| `bridges/nvda/tests/unit/domain/controllers/commands/test_get_guidance.py` | unit | the declared persona's text comes back; the **common section is present for every persona**, including an unrecognised one, which yields `recognised: false` rather than an error |
| `bridges/nvda/tests/unit/domain/controllers/commands/test_hello.py` | unit | the persona reaches the context and the transcript; an absent `persona` field still handshakes |
| `bridges/nvda/tests/unit/domain/controllers/test_session.py` | unit | the start signal is given the session's persona, and a signal that raises still leaves the session established (the guard) |
| `server/domain/controllers/reader_guidance_test.go` | unit | fetched once and cached; refetched after a reconnect; both degraded documents |
| `server/tests/conformance/real_bridge_session_test.go` | conformance | persona travels in a real `hello` over a real pipe and `getGuidance` returns the bridge's text — **including the unknown-persona path**, which is unreachable from the server's own validated tool surface and so can only be exercised here |

**Live-NVDA checklist** (11.20's PR): connecting as each of the three personas
succeeds and `status` reports it; the bridge's transcript on disk names the
persona; `screenreader://reader-guidance` returns NVDA's document for the declared
persona and a different one after reconnecting under a different persona; and
reading it twice makes only one round trip. **And the audible one** (4.7): the
two ascending tones are followed by the spoken persona, in **both** capture
modes — silent included, which is the case that would quietly fail if the
utterance went through the ordinary speech pipeline instead of the live synth.

## Part 6 — staging

**The seam is mechanism, then document — not server, then reader.** The board
originally split these entries by lane, which was right while the server owned
the vocabulary. After the second correction it is not: the server half no longer
stands up on its own, because it would tell a `user` session its vocabulary is
bounded and give it no way to learn what is in it. The entries are re-scoped
along the seam that survives the correction, and both PRs touch both lanes.

**PR 1 — the persona exists and travels (board entry 11.19).** Parts 2 and 3, the
wire's `persona` field (4.2), the bridge recording it (transcript and context),
and the spoken persona at session start (4.7). At the end of it a session
declares what it stands for, the agent is instructed in that stance at connect,
every artifact describing the session carries it, and the human at the machine
hears it. **Nothing in it promises a document that does not exist yet**, which is
the property the old split lost.

**PR 2 — the reader says what its vocabulary is (board entry 11.20).** The rest
of Part 4. Exactly these changes, and everything else in Part 5 belongs to PR 1:

- `Command.GET_GUIDANCE`, `Capability.GUIDANCE` and `GetGuidanceResult` in the
  shared contract, with §4 and §5 of the protocol document and the regenerated
  schema and Go binding;
- the bridge's `reader_guidance.py` entity, its `get_guidance.py` handler, and
  the registry and wiring that announce the capability;
- the server's `guidance_reader.go` port, `ReaderConnection.Guidance` and the
  handshake that populates it, the `getGuidance` call in
  `json_lines_client.go`, the `reader_guidance.go` controller with its cache and
  degraded documents, and the `reader_guidance_resource.go` adapter;
- in `connect_reader`, the `readerGuidance` field — and in `user`'s stance text,
  the closing sentence that names the resource, which is the one line PR 1
  deliberately omits.

Both PRs need an add-on rebuild and a live-NVDA run; the checklist in 5.5 splits
along the same line. The order is not negotiable — PR 2's document is meaningless
without PR 1's declaration — and this time the gap between them is harmless,
because PR 1 makes no promise PR 2 has to keep.

## What is deliberately not built

- **A tool gate of any kind, server-side or bridge-side.** Part 3.2. The server
  cannot build a whole one; the bridge could, and does not yet. The trigger for
  revisiting is named there rather than left to taste.
- **A persona parameter on `getGuidance`.** Part 4.3.
- **Changing persona mid-session.** Part 3.3. Disconnect and reconnect; it is a
  different run.
- **Per-persona tool descriptions.** Descriptions are fixed when a tool is
  registered, and a session's persona is not known then. Making them dynamic
  would mean re-registering tools on connect — 11.6's territory, for a benefit
  the connect result already delivers.
- **Three static per-persona resources.** Specified, then withdrawn the same day:
  a server-owned document holding a persona's *vocabulary* can only be written
  for one platform, and TalkBack has neither the keyboard nor the operating
  system it would assume. One general document plus one bridge-supplied document
  (3.5, 4.6).
- **A fourth persona for the inexperienced user.** Not needed after the
  2026-08-17 correction: `user` **is** that user (2.2). What was going to be a
  fourth stance is now the definition of the first.
- **A fourth "unstated" persona.** Part 3.1: the declaration is required, so
  there is no such state to name. The bridge's `recognised: false` is a different
  thing — an unknown persona, not an absent one.
- **An automated audit of a `user` or `validator` run.** Part 4.8 makes it
  *possible* — the session record plus a bridge that names the out-of-vocabulary
  gestures — and reading a record by hand is enough to answer 3.2's question.
  Building the audit is a separate entry, and it should not be built before there
  is a run to audit.
- **Enforcing precedence by parsing the bridge's document.** Part 4.1. The server
  frames it and never reads it.
- **A switch to silence the spoken persona at session start** (4.7). It is one
  short line, once, on a channel whose whole purpose is telling the human that
  their reader is being driven — the same argument that keeps the tones
  unconfigurable. A session that must be inaudible is one nobody is sitting at,
  and nobody is listening either.

## Honest limits

- **The persona is a declaration, not a constraint.** An agent can declare `user`
  and object-navigate its way to a pass the interface has not earned. Nothing
  here prevents that. What this buys is that the claim is now *attributable* and,
  after 11.20, *checkable* — not that it is true. The remedy if it happens often
  is named in 3.2, and deliberately not built before there is evidence it is
  needed.
- **The instruction only works on an agent that reads.** 3.4 puts the stance
  where it is hardest to miss; it cannot make it impossible to ignore.
- **A newer persona meets an older bridge as general guidance**, silently and
  correctly. That is the designed degrade (4.2), but it means a persona can be
  in use for a while before any bridge instantiates it, and nothing announces
  that gap except `recognised: false` in a result an agent may never fetch.
- **The bridge's document can be wrong or stale** and this server cannot tell.
  It ships with the reader it describes, which is the best available defence and
  not a guarantee. After the second correction it carries *more* weight than the
  first draft gave it — the ordinary vocabulary itself is now in there — so a
  bridge that writes it carelessly gets the `user` persona wrong for its whole
  platform, and nothing upstream can catch that.
- **A bridge that does not announce `guidance` leaves `user` under-specified.**
  The stance still arrives (3.4) and the rule still holds, but the concrete list
  of what is in and out of the vocabulary does not exist for that reader, and the
  agent falls back on what it already knows about it. That is tolerable and it is
  not good: the persona whose boundary matters most is the one that degrades
  furthest.
- **The three personas are a guess at the audience.** They came out of one
  conversation and one external run, not from three real users. If a fourth is
  needed, 4.2 is what makes adding it cheap.

## Open questions

**None.** Four were raised while drafting, and all four are settled:

- whether the persona should be **spoken at session start** — yes, 2026-08-16;
  bridge-side, riding the tones that already mark the taking of control (4.7).
- whether an **inexperienced user** deserves a fourth persona — no, 2026-08-17,
  and for a better reason than the one first given: `user` **is** the ordinary,
  non-expert user (2.2), so the stance that was going to be added is the one
  already there.
- **what `user` may actually use** — settled 2026-08-17 by the correction at the
  top of this document. The vocabulary is the ARIA keyboard contract, and needing
  more is a failure (2.2).
- **whether to gate** — no, and 3.2 names the trigger that would reopen it:
  *deliver the right information per persona; if violations turn out to be
  common, gate.*

## Not in scope

Anything that changes what a persona is *allowed* to call (Part 3.2), the
round-trip economics of driving ([0025](0025-one-round-trip-per-intention.md)),
and the object-navigation tool [0023](0023-drive-it-like-a-user.md) anticipates —
which, if it is ever built, changes what is enforceable here (4.8) but is not
part of this.
