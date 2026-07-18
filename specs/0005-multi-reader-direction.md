# Spec 0005 — direction: one server, many screen readers

Direction RFC, agreed in conversation on 2026-07-18. Unlike specs 0002–0004
this is not an implementation contract for one PR: it records architecture and
distribution decisions that future entries are judged against, the same way
RFC 0001 does. It adds one concrete board entry (lane 1, entry 8 — spec 0006)
and amends the scope of entries 9 (session C) and 12 (session F).

## Context

The project was conceived around NVDA, but the server's value generalizes: an
AI agent that can drive **a** screen reader and read back what it says is just
as useful pointed at JAWS on Windows or TalkBack on Android. This RFC settles
how much of that future we build now, and how we keep the rest cheap later.

## Decided — one repository until a second bridge is real

The repo stays a monorepo (shared wire contract + server + NVDA bridge). The
reasons, so they can be re-examined if the facts change:

- The wire contract is still churning. In one repo a protocol change is one
  atomic PR touching `shared/` and both halves; split repos would turn every
  change into coordinated releases with version skew and contract-test
  overhead — cost paid for independent teams we do not have.
- The artifact a non-Python bridge would reuse is **not** the Python package
  (a JAWS bridge would be C#/COM, a TalkBack bridge Kotlin — neither can
  import `nvda_mcp_wire`). What they need is the published wire contract
  (spec 0006), which lives happily inside this repo.
- The uv workspace already gives each component its own package, and
  `git filter-repo` can extract a directory with full history, so a later
  split loses nothing by waiting.

**Split trigger:** work on a second reader's bridge starting in earnest. At
that point the published wire contract becomes the canonical boundary, the
server keeps the (reader-neutral) repo, and the NVDA bridge extracts to an
NVDA-named repo. Until then, do not split.

## Decided — the server is a reader-agnostic chassis

The server core never special-cases a screen reader. The principles, which
session D's spec must encode:

1. **No reader conditionals in server code.** The server's domain and MCP tool
   surface speak generic vocabulary: speech since an index, braille, press
   gesture, state, config. There is no `if reader == "nvda"` anywhere.
2. **Reader identity is surfaced, not hidden.** The AI client must know which
   reader it is driving — NVDA's browse/focus mode, JAWS's forms mode and
   keystrokes are different mental models, and the model already knows them
   from training. The `hello` handshake announces `reader` (name + version)
   and `capabilities`; the server passes that through to the MCP client.
3. **Reader vocabulary rides through as data.** Gesture ids, config key
   paths, state values are opaque payloads the AI composes and the bridge
   interprets; the server routes and buffers. (Precedent: LSP/DAP — the
   editor ships no language semantics, yet you debug Python in it.)
4. **The bridge endpoint is configuration at the composition root.** The
   server dials the bridge; "which bridge" is a host/port setting (v1: one
   target, loopback default). Multi-reader later is a named endpoint map —
   still data, the only code is a lookup. Config names the expectation;
   `hello` verifies what actually answered and a mismatch fails the session
   loudly at connect.

## Decided — a "bridge" is whatever implements the wire contract for one reader

A bridge is **not** necessarily a plugin inside the reader. It is the set of
components that implements the wire contract for one screen reader, and the
shape differs per reader because the readers differ in openness:

| Reader | Capture | Gestures | Transport | Notes |
|---|---|---|---|---|
| NVDA | in-process spy synth / speech hooks | `inputCore` in-process | add-on owns the loopback socket | The deluxe bridge: real introspection, config access, synth swap-and-restore. |
| JAWS (future) | custom SAPI 5 voice (COM DLL) selected in JAWS receives all utterances | OS-level `SendInput` (JAWS hooks the keyboard globally) | ordinary external process owns the socket | JAWS scripts cannot own a TCP port and do not need to. Focus info approximated via UI Automation; braille likely unsupported (driver SDK not public). Small official COM surface (`JawsApi`) exists for extras. |
| TalkBack (future) | custom Android `TextToSpeechService` selected as system TTS (public API) | companion app's accessibility service dispatches synthetic gestures | companion app socket over `adb forward` or Wi-Fi | TalkBack itself is open source (AOSP). Injected-touch interaction with TalkBack's gesture interception is unverified — check when real. |

Two consequences, both already reflected in entries:

- The 7a domain ports (SpeechSource, GestureSender, SynthSwapper, …) are the
  durable seams: every reader's bridge decomposes into the same roles with
  different adapters. A future bridge design conversation starts from the
  port list.
- Capabilities are uneven per reader (JAWS-no-braille, TalkBack-no-config),
  so `hello` announces a capability set instead of the server discovering
  gaps via errors. That lands in entry 8 (spec 0006).

## Decided — the wire contract is two artifacts

1. **The Python module** (`shared/nvda_mcp_wire/protocol.py`) stays the
   canonical *implementation* for the all-Python era. Its same-bytes sharing
   between server and NVDA bridge is a drift guarantee worth keeping exactly
   as long as both halves are Python. Hard invariants 1–2 (stdlib-only,
   addon copy is a build artifact) are unchanged.
2. **The published contract** (entry 8, spec 0006) is the artifact future
   bridge authors consume: a hand-written prose semantics document plus a
   JSON Schema **generated from the dataclasses**, committed under
   `specs/wire/v1/` and guarded by a CI drift gate (regenerate, diff, fail on
   mismatch — the OpenAPI-from-code pattern). The schema captures shapes; the
   prose captures what schema cannot: handshake ordering, half-open index
   ranges, error model, heartbeat rules, capability meanings, versioning
   policy. The prose is the schema's equal partner, not an afterthought.

The "known place" for the contract is this repo, addressable by tag/raw URL;
graduate to release assets or Pages per protocol version when a second bridge
is real. Which artifact is *canonical* is revisited only when the first
non-Python bridge author arrives with real needs. Schema-first code
generation was considered and deferred for the same reason as the repo split:
all cost now, consumers later.

Protocol v1 has never shipped to an external consumer and `from_dict` ignores
unknown fields by design, so pre-release amendments to v1 (like `hello`'s new
fields) are free — no version-bump ceremony until someone external depends on
the contract.

## Decided — server language and distribution

- **The v1 server is Python** (session D as planned). The server is a thin
  chassis, so the language choice is not load-bearing yet; switching to Go
  now would forfeit the same-bytes drift guarantee, force the published
  contract work to complete first, and split the toolchain during peak
  protocol churn — while the bridge stays Python forever regardless.
- **A Go port is the packaging-era option, decided at session F** with real
  artifacts in hand: by then the contract is stable, the 7b wire scenario is
  an executable conformance test, and an official MCP Go SDK exists. A Go
  server would double as the first second-implementation stress test of the
  published wire spec. The competing option is PyInstaller (roadmap F's
  original sketch) with its known warts: artifact size, startup, antivirus
  false positives.
- **Distribution is per-piece native channels, with an optional Windows
  umbrella installer.** The NVDA add-on's canonical channel is the NVDA
  add-on store (that is where updates come from; side-loading orphans it).
  The server rides `uvx` for developers, potentially an `.mcpb` bundle for
  Claude Desktop users, and the umbrella installer for the QA persona. The
  installer becomes genuinely necessary no later than the JAWS bridge, whose
  SAPI spy synth needs admin COM registration — an installer job by nature.
  A TalkBack bridge is an Android app and can never be in a Windows
  installer, which confirms the per-channel pattern. All of this is session
  F's decision list; nothing changes for C or D.

## Open — repository name

Renaming is lossless (GitHub redirects old URLs; history, PRs, stars
survive), and two collisions argue for it: `bramd/nvda-mcp` and
`adil-adysh/nvda-mcp-bridge` already exist in exactly this niche. Candidates
discussed: descriptive (`screenreader-mcp` — free as of 2026-07-18) versus a
brand name (the Guidepup precedent; echolocation/auscultation metaphor veins).
Marlon is deciding. The `nvda_mcp_wire` package rename is deferred until the
repo name settles, so both rename once, together.

## Board impact

- Adds lane-1 entry 8 (published wire contract + capability-aware `hello`),
  spec 0006.
- Session C entry: real adapters supply live `reader`/`capabilities` values
  for the fields entry 8 adds.
- Session F entry: gains the decision list above (server language, umbrella
  installer, `.mcpb`).
