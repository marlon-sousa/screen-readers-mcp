# 0030 — the second external run: feedback as received

Status: **a findings record, not a design spec.** Nothing here is agreed or
proposed; it is evidence. Received 2026-08-18. Numbered into `specs/` for the
same reason as [0027](0027-the-first-external-run.md): the board records what we
decided to *do* about feedback, and decisions move — an entry gets absorbed,
split, renumbered or deferred, and each move loses a little of the original ask.
The demands outlive our current plan for them, so they are written down once,
plainly, and the board points here rather than the other way round.

---

## Where it came from, and why the source matters

An external agent — **not a Claude model** — drove this MCP through a real task
on 2026-08-18: find the three DeepSeek result titles on a search results page.
**The task was completed.**

This is the second session nobody on this project was sitting at, and the first
driven by a model from a different family. That matters for a specific reason.
Every affordance this project publishes — `screenreader://guidance`,
`screenreader://reader-guidance`, the tool descriptions — is prose written to be
read by an agent, and until now every agent reading it shared a lineage with the
one that wrote it. A different family reading the same documents is the closest
thing to an independent test of whether they say what we think they say.

Two standalone failures occurred during the run. The reporter attributes one to
itself and one to a silent session drop. **Both point at concrete gaps**, and the
reporter's own framing is that the MCP already provides everything needed — the
gaps are in *discoverability* and in *visibility of session liveness*.

---

## The report, as received

> ## 1. Tool discovery is the root cause of me reading source — fix that and I won't
>
> The hardest thing in this run was learning *which gated tools exist and what
> their parameters are*. My initial tool list showed only the four ungated tools
> (`connect_reader`, `disconnect_reader`, `list_readers`, `status`). After
> `connect_reader` the gated tools exist and I could call them, but I had no
> authoritative list of their names and schemas in front of me — which is
> precisely why I opened the Go source, the thing you rightly called me out for.
>
> Two things would remove that temptation entirely:
> - Have the client re-list tools on a successful `connect_reader` so the gated
>   set appears as first-class tool definitions (name + schema + description)
>   rather than something I piece together from prose. The AGENTS.md already
>   documents that a redeploy freezes tool discovery — this run shows the same "I
>   can call it but I can't see it listed" gap bites even without a redeploy.
> - Better: a single `screenreader://tools` resource that is a reader-agnostic
>   cheat-sheet — every tool name, what capability gates it, what it returns. A
>   document served for reading, per your invariant, not source spelunking.
>
> ## 2. The inactivity watchdog killed a live silent session while I was merely thinking — with zero warning
>
> The second disconnect was not the panic button. It was me being idle too long
> reading source, and the ~120s watchdog dropped the session with nothing told to
> me until my next call returned "needs a connected reader." The policy that
> `ping` proves liveness but does *not* reset the watchdog is correct — but an
> agent's idle time between tool calls is exactly when it reasons, and I had no
> signal that the clock was running.
>
> Useful change: expose time-to-expiry. Either `status` reports seconds
> remaining, or the bridge warns once ("inactivity timeout in 30s") before
> dropping, or a `keepalive` the agent is expected to send and whose absence is
> cheap to notice. The current failure mode — silent drop, discovered
> retroactively at the next call — cost a full reconnect and the attendant
> bridge-restart hand-off to you.
>
> ## 3. Minor: unify gesture notation, and confirm the human actually heard an announcement
>
> - `press_gesture`'s description says `"NVDA+f7"` (camel-case), while
>   `screenreader://reader-guidance` correctly says the literal form is
>   lower-cased and sorted (`"nvda+tab"`). I used the lower-cased form and it
>   worked, but the two documents disagree in casing and that is a small hazard
>   waiting to confuse.
> - When I announced through the `announce` parameter on
>   `press_gesture`/`type_text`, nothing in the returned result acknowledged that
>   the human heard it (by design, that channel isn't captured speech). A
>   one-line `"announced"` ack in the result would let an agent confirm the human
>   was told, instead of assuming.
>
> ## What worked well
>
> The reader-guidance document was excellent — it is the single reason I could
> drive correctly at all: the exact per-machine key bindings (including the
> remapped Portuguese NVDA UI), the browse-mode quick-nav letters (`h`, `k`,
> `e`), and the desktop keys (`windows`, `control+l`) were all there, in the
> literal form `press_gesture` accepts. That document is the model for what I
> needed everywhere else.
>
> Net: the MCP *does* provide everything I need; the gap was discoverability of
> that info (point 1) and visibility of session liveness (point 2). Closing those
> two removes both the temptation to read source and the silent drops.

---

## Traceability

Where each ask went. This table is the point of the file: an ask that gets
absorbed into another entry must still be findable from its original wording.

| Ask | Entry | Note |
| --- | --- | --- |
| 1a. Client re-lists tools after `connect_reader` | **11.6** | Already open, and this is independent corroboration from outside the project. 11.6 was written as a Claude Code client quirk cured by `/mcp reconnect`; this run shows the same gap in another client **without** a redeploy, which makes it a protocol-level concern rather than one client's bug. |
| 1b. A `screenreader://tools` cheat-sheet resource | **11.22** | New. The reporter's preferred fix, and the one that does not depend on client behaviour we do not control. |
| 2. Session liveness is invisible until it is too late | **11.23** | New. Three candidate mechanisms offered; the reporter is explicit that the current `ping`-does-not-reset policy is *correct*, so this is about visibility, not about relaxing the watchdog. |
| 3a. Gesture notation disagrees between two documents | **11.24** | New, small. A documentation defect, and exactly the class of thing an outside reader finds and an inside one cannot. |
| 3b. An `announced` acknowledgement in the result | **11.24** | New, same entry. Both are about a caller being able to trust what it was told. |

## What this run says about the documents

The praise is worth recording as precisely as the complaints, because it is
directional. `screenreader://reader-guidance` — the reader-specific document,
carrying the literal gesture strings and this machine's actual bindings — was
named as the single reason the run succeeded. `screenreader://guidance`, the
reader-agnostic method document, is not mentioned at all.

That is a signal about **where an agent looks when it is trying to act**: the
concrete, literal, this-machine document, not the one about method. Ask 1b is
the same shape — a cheat-sheet of literal tool names and shapes. The project's
instinct so far has been to write method and keep the concrete out of the
reader-agnostic layer, for good reasons (spec 0005 principle 2). This run does
not contradict that instinct, but it does say the concrete layer is the one
carrying the weight, and it is thinner than the method layer.
