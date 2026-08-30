# AGENTS.md — working in screen-readers-mcp

Operating manual for anyone (human or agent) developing this repo. For *what
we're building and why*, read the design specs in [`specs/`](specs/) — start
with [`0001-agent-driven-nvda-over-mcp.md`](specs/0001-agent-driven-nvda-over-mcp.md).
For *what to do now*, read [`ROADMAP.md`](ROADMAP.md) — the status board; its
first non-Done entry is the next step, and its Spec field says whether that
step is a spec conversation or implementation.

## Where the rest of the manual is

This file is the spine: what we are building, how the repo is laid out, the
four-role vocabulary both halves share, the hard invariants, the workflow, and
the task list. It is self-contained — an agent or contributor who reads only
this file has everything needed to work the repo safely.

The detail that belongs to **one** project lives beside that project, so a
session working there picks it up without carrying the rest:

| File | What is in it |
|---|---|
| [`shared/AGENTS.md`](shared/AGENTS.md) | The wire contract: the stdlib-only rule, and the policy that a `PROTOCOL_VERSION` 1 shape may still be changed in place. |
| [`server/AGENTS.md`](server/AGENTS.md) | The Go half: its ports/entities/controllers/adapters inventory, the Go mechanics of the shared rules, build tags and the Go-only test rules. |
| [`bridges/nvda/AGENTS.md`](bridges/nvda/AGENTS.md) | The NVDA bridge: its architecture, the command-handler dispatch layer, its test shapes, the rules for driving a live NVDA, and the NVDA gotchas. |
| [`bridges/voiceover/AGENTS.md`](bridges/voiceover/AGENTS.md) | The VoiceOver bridge: its five elements, how the repo's rules render in Swift, what the module graph enforces, the endpoint's duplicated derivation, and the macOS gotchas. |
| [`docs/dev-commands.md`](docs/dev-commands.md) | Why each gate in the task list exists and what it cost to learn, plus the underlying commands `poe` wraps. |

Each project file assumes this one and does not repeat it. Nothing below is
optional reading because a project file exists: if a rule is here, it applies
everywhere.

## How this repo is developed

**Agentic-first.** The system is built and reviewed largely by an AI agent
working in this repository — which is why this manual is written to be read by
one, and why a rule here is phrased as an invariant rather than a convention.

That is also the reason the `../nvda` checkout is a stated prerequisite in
[`CONTRIBUTING.md`](CONTRIBUTING.md) (a sibling directory named `nvda`, at tag
`release-2026.1`) rather than an optional convenience. An agent cannot rely on
recalled API knowledge for a codebase that changes every release: it reads the
real source to confirm what a function does before writing an adapter against
it. Hence the rule below — consult `../nvda/source`, never guess a signature —
and the `nvda-headless-testing` approach that exercises add-on logic against it
without launching NVDA.

None of which makes an agent mandatory. Every command in `CONTRIBUTING.md` is
one a human can type, and nothing in the build, the tests or the type check
requires one.

## What this is

An MCP server that lets an AI agent **drive NVDA** (the screen reader): send
keyboard gestures, read back what NVDA speaks/brailles, and introspect its
state. First use case: functional testing of NVDA add-ons; the primitives are
general.

Direction ([spec 0005](specs/0005-multi-reader-direction.md), **Decided**):
the server is a **reader-agnostic chassis** — NVDA is the first bridge, not
the identity. A "bridge" is whatever implements the wire contract for one
screen reader (JAWS and TalkBack sketches live in the spec). The server core
never special-cases a reader; reader identity is announced by `hello` and
surfaced, reader vocabulary rides through as opaque data, and the repo stays
a monorepo until a second bridge is real. **The second bridge is now real** —
`bridges/voiceover/`, since board entry 13.2 — and the monorepo stays, which was
decided in conversation on 2026-08-29 and recorded in
[spec 0043](specs/0043-the-voiceover-bridge-is-one-swift-bundle.md): spec 0005's
split trigger was declined, not merely unmet.

The chain, top to bottom — each item talks only to the next:

1. An MCP client (Claude Code, …) speaks MCP over stdio to the server.
2. `server/` — `screenreader-mcp`, a statically linked **Go** binary — speaks
   JSON lines to the bridge over a **local endpoint** by default, or loopback
   TCP (`127.0.0.1:8765`), chosen in the bridge's control dialog
   ([spec 0010](specs/0010-named-pipe-transport.md),
   [0011](specs/0011-bridge-control-ui.md)). The local endpoint is a
   *requirement*, not a mechanism: it is addressed by a bare **name**
   (`local:nvdaMcpBridge`) which resolves to a named pipe on Windows and to a
   Unix domain socket under `$XDG_RUNTIME_DIR` or `~` on POSIX, so one shipped
   default works on every host ([spec
   0044](specs/0044-the-local-endpoint-off-windows.md)). It never dials on its
   own: the agent calls `connect_reader`, and the capability-gated tools appear
   on a successful `hello` ([spec 0013](specs/0013-mcp-server.md)).
3. `bridges/nvda/` — the `nvdaMcpBridge` NVDA addon (a global plugin) — drives
   NVDA itself. Silent capture registers a `filter_speechSequence` filter and
   **never swaps the synth**; the user's real synthesizer stays loaded, so a
   crash cannot strand them mute
   ([spec 0008](specs/0008-transparent-silent-capture.md)).

The two halves are separate processes and meet **only at that local endpoint**,
so the server survives NVDA restarts and NVDA's embedded Python never hosts the
asyncio MCP server.

What must match between them is the **wire protocol version**, not their
version numbers: `hello` compares `PROTOCOL_VERSION` and never the components'
own versions, so each releases on its own cadence
([spec 0012](specs/0012-packaging-and-release.md)).

The rest of that policy — when a shape may be changed in place, and what would
make it cost a version bump instead — is in
[`shared/AGENTS.md`](shared/AGENTS.md), with the contract it governs.

## Layout

| Dir | What | Host / Python |
|---|---|---|
| `shared/` | Canonical **stdlib-only** wire protocol (`screenreader-wire`). Envelope + per-command dataclasses + `from_dict` validator + JSON-lines helpers, plus `schema.py` (generates the published `specs/wire/v1/schema.json` from the dataclasses; **not** synced into the addon). Unit-tested once. | desktop CPython |
| `server/` | The MCP server (`screenreader-mcp`): MCP tool → bridge command → result. stdio, official Go SDK. Its wire binding is generated from `specs/wire/v1/schema.json` into `server/adapters/wire/` — private to the server, because what is shared between implementations is the contract, not code. | Go (static binary, `CGO_ENABLED=0`) |
| `bridges/nvda/` | The NVDA addon, built with scons. Inert until a session connects. | NVDA's embedded CPython 3.13 |
| `bridges/voiceover/` | The macOS VoiceOver bridge: one Swift `.app`, built by `build.sh` because SwiftPM cannot emit bundles. It holds the **capture voice** — a speech synthesis provider macOS hands every utterance as SSML — **`Sources/ScreenReaderWire/`, the contract's third binding** (hand-written Swift value types gated against `specs/wire/v1/schema.json` by `scripts/drift.py --swift`), and, since 13.4, **the bridge session**: `VoiceOverBridgeDomain` (ports, `Session`, handlers, entities) and `VoiceOverBridgeAdapters` (the two listeners, the JSON-lines channel, `Wiring`). It **listens** on the local endpoint the server dials, and since 13.5 it **hears**: the capture voice appends JSON lines to a file in its own container — the only door out of a sandboxed speech provider — and `ContainerFileSpeechSource` tails it into the session's `SpeechBuffer`, so `hello` announces `speech` and the five speech commands answer. A silent session is still refused until 13.6. The dialog is 13.10. Its `pyproject.toml` carries **no Python**: it is the declaration file `scripts/bridges.py` reads, and [spec 0046](specs/0046-the-voiceover-bridge-class-by-class.md) names that a wart and declines the cheap fix. | Swift 6 (macOS only) |
| `specs/` | Numbered design specs (RFC-style `NNNN-title.md`). | — |

`shared/`, `server/`, `bridges/nvda/` and `bridges/voiceover/` each carry their
own `AGENTS.md` with the rules specific to them; see the index above. The
VoiceOver one arrived with **13.4**, which is what gave that bridge a domain with
rules of its own; its `README.md` stays beside it and is the document for
*using* the bundle — building it, registering and removing the capture voice —
while the `AGENTS.md` is the document for changing it.

## Internal architecture — ports & adapters (bridge AND server)

**Both** the bridge addon and the MCP server use the same **hexagonal**
(ports-and-adapters) design. The bridge's side-effecting edge is NVDA; the
server's is the MCP/stdio SDK and the TCP socket to the bridge — same shape,
learn it once.

**Every class has exactly one of four roles.** This is the vocabulary — if you
cannot name a new class's role, it is in the wrong place:

| Role | Lives in | What it is |
|---|---|---|
| **port** | `domain/ports/` | An `abc.ABC` the domain needs from the outside world. |
| **controller** | `domain/controllers/` | An orchestrator. Handed the ports it needs by `wiring.py`; runs a whole use case, driving entities and calling out through ports. **The answer to "who connects what".** |
| **entity** | `domain/entities/` | A stateful thing the app reasons about. Pure — never does IO. |
| **adapter** | `adapters/` | A concrete implementation of a port. The only place NVDA / the MCP SDK / the OS / real IO lives. |

"Pure Python" does **not** mean "domain". JSON-lines framing is pure and still
belongs in an adapter, because it is none of the three domain roles — it lives
behind the `MessageChannel` port, so the Session's collaborators are *only*
ports.

```
<package>/
  __init__.py     # entry point ONLY. The bridge's exposes GlobalPlugin lazily
                  # via a module-level __getattr__, so importing the package
                  # does NOT import NVDA (tests import the domain directly).
  domain/         # PURE core: no NVDA / no MCP SDK / no sockets / no JSON.
    ports/        #   ONE PORT PER FILE (abc.ABC + @abstractmethod); a port's own
                  #   DTO / signalling types live in its file. No re-exports.
    controllers/  #   the orchestrators, one per file
    entities/     #   the pure stateful model, one class per file
  adapters/       # the ONLY place NVDA / the MCP SDK / the OS / real IO lives
    ports/        #   seams BETWEEN adapters (the domain never sees these)
    ...           #   one class per file (private helpers may share the file)
  wiring.py       # composition root: picks adapters, stacks them, hands the
                  # controller its ports. Stays PURE so it is type-checked.
```

Which file plays which role in each half — the bridge's session, handlers,
entities, ports and adapters, and the server's Go equivalents — is inventoried
in [`bridges/nvda/AGENTS.md`](bridges/nvda/AGENTS.md) and
[`server/AGENTS.md`](server/AGENTS.md).

Rules that keep this honest:

- **Every module header states its ROLE and its relationships**, not just what
  the code does: which port it implements, what it depends on, who builds it,
  who uses it. If a reader has to ask "what is this class for and who connects
  it?", the header has failed — that question is the review test.
- **Adapters are LAYERED so the untestable part shrinks to a leaf.** An adapter
  may depend on another adapter, but only through a seam in `adapters/ports/` —
  never on a concrete adapter. The upper adapter holds every decision and is
  unit-tested against a fake seam; the **leaf** makes no decisions and does
  nothing but call the OS, so there is nothing to unit-test in it:

  | Decisions (tested vs a fake) | Seam | Leaf (untestable, ~15 lines) |
  |---|---|---|
  | `FileTranscript` — transcript vocabulary | `FileWriter` | `TextFileWriter` — real `open`/`write` |
  | `JsonLinesChannel` — framing + encode | `Transport` | `SocketTransport` — real socket |

  If you are tempted to put a decision in a leaf, it belongs one layer up.

- **One interface/class per file, and NO re-export facades.** Each port,
  controller, entity and adapter is its own file; a small private helper may
  share its owner's file (e.g. `_LineReader` inside `json_lines_channel.py`). A
  **DTO or signalling type lives in the same file as the port/adapter that owns
  it** (`AdapterSet` with `AdapterFactory`; `Timeout`/`ChannelClosed` with
  `MessageChannel`). Import each from its own file
  (`from ..ports.clock import Clock`) — the `__init__.py` files carry
  documentation, never re-exports, so every import names its file and a module's
  dependencies are exactly the ports it lists. This applies to
  `shared/screenreader_wire` too: import from `screenreader_wire.protocol`, so
  both halves address the wire contract through a module named `protocol`.
- **Enumerations are `enum`, never class-of-`Final`-constants.** Wire enums
  (`CaptureMode`, `Command`) are `enum.StrEnum` in `protocol.py` (members are
  `str`, so JSON stays plain); domain-only enums (`TeardownReason`) are plain
  `enum.Enum`. `Request.cmd` stays a raw `str` so an unknown command yields a
  clean error instead of a validation crash.

The rules that only one half renders live with that half: the bridge's ABC
ports, `wiring.py`, the no-DI-container argument, the "mode is only known after
`hello`" rule and the exempt NVDA edge are in
[`bridges/nvda/AGENTS.md`](bridges/nvda/AGENTS.md); the Go mechanics — interface
assertions, no package-level mutable state — are in
[`server/AGENTS.md`](server/AGENTS.md).

## Testing

The domain is pure, so it is unit-tested headlessly under desktop Python with
its ports faked. The rules below come with their reasoning, because each looks
like a style preference and is actually a correctness argument.

### Where a test lives — `tests/unit/` mirrors the source tree

**`tests/unit/` is a mirror of the package, file for file**, so the path alone
answers "which test covers this file?" and "where do I add a test for this?":

```
addon/globalPlugins/nvdaMcpBridge/domain/entities/speech_buffer.py
tests/unit/domain/entities/test_speech_buffer.py
```

The mirror applies per package, not just to the bridge:
`shared/tests/unit/test_protocol.py` ↔ `screenreader_wire/protocol.py`.

**In Go the mirror is the language's own convention**, so the server renders the
same rule differently — one test file beside each source file, `package
foo_test` by default, and the scenario tiers behind build tags. That is in
[`server/AGENTS.md`](server/AGENTS.md).

One test module per source module — **do not** let a test module cover its
neighbours. (The rule earns its keep immediately: one `test_speech_buffer.py`
was quietly testing three units — the base, speech and braille — so the base's
index bookkeeping got tested through whichever subclass was handy. Mirroring
forced it into `test_indexed_buffer.py`, which now tests the base's contract
through a minimal stub subclass, while each buffer tests only what it adds.)

**A source file with no test file is a deliberate statement, not an omission:**

| No test file | Why |
|---|---|
| `domain/ports/*.py` | ABCs — no behaviour to test. |
| `domain/controllers/commands/command_handler.py` | The handler ABC + `CommandError` — an interface, like a port. (`session_context.py` and `registry.py` DO carry behaviour and are tested.) |
| leaf adapters (`real_clock.py`, `text_file_writer.py`, `socket_transport.py`) | They make no decisions; there is nothing `open()` doesn't already guarantee. If you are adding a test here, you have put a decision in a leaf — move it up. |
| `plugin.py` | The NVDA edge. Covered by the integration tests, not units. |

**Fakes mirror the ports they stand in for**, same one-class-per-file rule and
no re-export facade: `tests/fakes/clock.py` ↔ `domain/ports/clock.py`, imported
as `from fakes.clock import FakeClock`. Test scaffolding that is **not** a port
double — builders, helpers — lives in a sibling `tests/support/` package
(`from support.context import make_context`), so `fakes/` stays exactly the port
doubles and nothing else.

Keep test module basenames unique across the tree (pytest's prepend import mode
requires it). Mirroring gives that for free, since source basenames are unique.

### Doubles are hand-written stateful fakes, not mocks

One per port, in `tests/fakes/` (one file per fake, mirroring the port's
file), each **subclassing its ABC** — so a fake that
forgets a method fails at construction exactly as the real NVDA adapter would.

The domain drives its collaborators through *real protocols* (wait loops, index
reads, state transitions) and asserts on resulting behaviour, so the doubles
need **behaviour**, not call-recording. A `Mock` returns a `Mock` for every
call, so you would hand-script return values per test — re-implementing the
collaborator, badly, and exercising less. `create_autospec`'s selling point
(catching contract drift) is already covered here by the **ABCs at runtime** plus
**pyright strict in CI**.

The cost is real and accepted: fakes are code we maintain. What they cannot
prove is that the *real* adapter behaves like the fake — only that signatures
match. That guarantee comes from the milestone-6 live-NVDA integration tests,
not from the unit doubles.

### Fixtures for uniform collaborators; builder helpers for scenarios

**Use a fixture when every test wants the same thing** ("a buffer on the fake
clock"). The point is not DRY — it is that a fixture makes a *relationship*
structural. `clock` (conftest) plus `speech(clock)` guarantees the buffer's
clock **is** the one the test advances. Hand-wiring that per test permits:

```python
clock = FakeClock()
buf = SpeechBuffer(FakeClock())   # a DIFFERENT clock
clock.advance(2.0)                # advances nothing the buffer can see
```

which passes silently and asserts nothing. The fixture makes that unwritable.

Prefer a **named variant fixture** (`silent_speech`) over a factory fixture
(`make_speech(exact=True)`) when there are only a couple of variants — a name
reads better than an argument.

**Do NOT reach for a fixture when each test customises construction.** The
session tests vary the swapper (one that raises on restore), the gesture sender
(one that rejects an id), the `SessionConfig`, the transport script — that is a
**builder helper** (`run_session(...)` with optional overrides), not a fixture.
Fixtures suit uniform collaborators; builders suit per-test scenarios. Forcing
fixtures there means one fixture per permutation.

**A fixture lives at the narrowest scope that serves it** — that is what the
mirrored tree buys us:

| Used by | Lives in |
|---|---|
| one test module | that module (`speech`, `silent_speech`, `braille`) |
| sibling modules in one directory | a `conftest.py` beside them |
| everything | `tests/conftest.py` (`clock`) — also the harness bootstrap |

Promote a fixture only when a second module actually needs it; do not start at
the root. Function scope (the default) is what we want: a fresh instance per
test, no state leaking between them.

**Why fixtures are fine when we rejected a DI container** (they are both
injection with the same "where does this come from?" indirection): pytest never
ships in the addon, the dependency is *visible in the test signature*, and a
missing fixture fails at collection with a clear message. None of the container
objections — a compiled binary inside NVDA, a `sys.modules` collision, hiding
the *production* graph, runtime failures inside NVDA — apply. Explicit wiring in
production; fixtures in tests.

### Time is injected, never patched

`FakeClock.sleep` is an **instant advance**, so a 5-second timeout test runs in
microseconds. This is also why `freezegun` / `time-machine` are the wrong tool
here: they patch the global clock but leave `time.sleep` real, so the wait loops
would still sleep for real — and patching globals under a `Clock` port would
make the port pointless for testing.

The test shapes that belong to the bridge alone are in
[`bridges/nvda/AGENTS.md`](bridges/nvda/AGENTS.md): what its `tests/integration/`
holds — headless scenarios that run in CI, and live-NVDA ones that do not — and
the three things that cost real time when driving a live NVDA.

## Hard invariants — do not break

1. **`shared/screenreader_wire/protocol.py` stays stdlib-only.** It is copied
   *verbatim* into the addon (`bridges/nvda/sync_shared.py`) and runs inside
   NVDA's interpreter, sharing `sys.modules` with every other addon. No
   third-party imports, ever. (pydantic etc. were considered and rejected —
   see the spec.) The server may use third-party libs; the shared module may
   not.
2. **The addon never edits its copied `protocol.py`.** Edit the canonical file
   in `shared/`; the copy under `bridges/nvda/addon/globalPlugins/nvdaMcpBridge/`
   is a gitignored build artifact regenerated by `sync_shared.py`.
3. **The addon must be safe to leave installed.** Inert while no session is
   active: no synth swap, no side-effecting hooks. Every silent-mode teardown
   path restores the user's real synth in a `finally` (a crashed harness must
   never leave a blind user with a mute screen reader).
4. **Type hints everywhere, enforced by pyright (strict).** CI fails on type
   errors. The pure **domain is fully strict-checked; the NVDA/SDK edge is
   not** — the side-effecting adapter files (and the bridge's `plugin.py`) are
   in pyright's `ignore` list, so their unresolved NVDA imports raise nothing.
   There is **no NVDA source dependency and no vendored stubs**; the `../nvda`
   checkout is a reference for reading real code, nothing more. (The edge is
   validated by the milestone-6 live-NVDA integration tests.)
5. **The domain never imports NVDA.** Everything under
   `nvdaMcpBridge/domain/` (and `protocol.py`) is pure Python, unit-tested
   headlessly. Only `nvdaMcpBridge/adapters/` may import `speech`,
   `synthDriverHandler`, `inputCore`, `config`, `api`, `braille`, … If you
   reach for an NVDA import in the domain, you're on the wrong side of a port.
6. **Decided means decided.** Items marked **Decided** — in this file,
   ROADMAP.md, or a spec's agreed sections — are settled. Do not relitigate
   them silently; to change one, propose it explicitly and update the doc in
   the same PR that implements the change.
7. **All documentation and communication must be screen-reader friendly:** no
   ASCII-art diagrams, no box-drawing flowcharts. Prose, numbered lists,
   headings, and tables. (Indented path listings in code blocks are fine;
   arrows-and-pipes drawings are not.) **To draw a diagram, use Mermaid** — a
   fenced code block tagged `mermaid`. It is text a screen reader can read as
   source, and it renders for sighted readers, so it serves both without a
   second version drifting out of date.
   - **Every Mermaid block must carry `accTitle` and `accDescr`.** They become
     the rendered SVG's accessible name and description; without them the
     diagram is an unlabelled graphic. `accDescr` states what the diagram
     *says*, not that it exists — "the agent reaches NVDA through two hops, the
     MCP server and the bridge add-on", never "architecture diagram".
   - **Not in the add-on docs.** `bridges/*/README.tpl.md` and anything under
     `addon/doc/` are rendered by scons through python-markdown with
     `markdownExtensions = []`, which has no Mermaid support: a fenced block
     ships into the `.nvda-addon` as literal `graph TD` source, and that file is
     the Help an NVDA user reads in the Add-on Manager. Those documents stay
     prose, lists and tables. Everywhere else Mermaid renders and is welcome:
     GitHub (root README, `ROADMAP.md`, PR and issue bodies) and VS Code's
     markdown preview — which is where **specs are reviewed**, so `specs/` is a
     first-class place for a diagram, not a grudging exception.

9. **A document served to an agent is a `.md` file, never a string literal in
   code.** Every MCP resource's prose — `screenreader://guidance`, the persona
   stances and profiles, `screenreader://reader-guidance`'s frame and the
   bridge's own persona documents — lives in a `documents/` directory beside the
   package that serves it. **The mechanism differs by language, and each has a
   trap that hides perfectly:**
   - **Go: `//go:embed`, one per file.** The bytes are copied at *compile* time,
     so an edited document changes nothing until the binary is rebuilt.
     `scripts/doctor.py` therefore counts `server/**/documents/*.md` among the
     server's build inputs; without that it would rglob only `*.go`, see nothing
     newer than the binary, and pronounce a stale one current while the running
     server served the previous wording to every agent that read it.
   - **Python: shipped in the add-on and read at run time**, because there is no
     compile step to embed anything into. The bundler rglobs the whole addon
     tree, so the files are packaged either way — but they must also be in
     `buildVars.bundledDataSources`, or `scons` will not treat an edited document
     as a reason to rebuild and the `.nvda-addon` ships the previous text while
     reporting "is up to date". Same class of silent staleness, opposite
     mechanism.
   - **Why:** these are documents, written and revised as prose, whose entire
     readership is a model reading markdown. As `const` blocks they were
     unreadable to author and to review: the guidance document had **29** places
     where the raw string was closed, concatenated with a quoted backtick and
     reopened purely to emit a code span, and the persona texts were 21
     concatenation continuations. A reworded sentence produced a diff nobody
     could read. Embedded, the file *is* the document — backticks, quotes and
     all — and an editor wraps and spell-checks it.
   - **One `//go:embed` per file, not an `embed.FS` keyed by name.** A missing
     document is then a *compile* error rather than an empty string discovered
     at runtime, which is the guarantee `Persona.Stance()` and `.Profile()`
     depend on. The Python side cannot have that guarantee, so it buys the next
     best thing: a missing document raises rather than returning `""`, because an
     empty document reads to the agent as "this reader has nothing to say", which
     is a very different and much worse answer than "the build is broken".
   - **This does not extend to tool descriptions or JSON schemas.** Those are
     read together with the `Execute` that uses them; splitting one tool across
     three files costs more than the formatting noise it saves. The line is: a
     **document** gets a file, a **field value** stays in code.
   - `embed` is stdlib, so the domain may use it — `domain/entities/documents/`
     is where the persona texts live, and the architecture test's import rules
     are unaffected.

## Dev commands

Requires [uv](https://docs.astral.sh/uv/). **Run the doctor first, before
anything else** — including before your first search or test run:

```sh
uv run poe doctor    # is this machine able to work the repo?
uv run poe fix       # repair what it found (reinstalls the project venvs)
```

**The rule, for agents: if `poe doctor` fails, fix the environment before doing
anything else — do not build, do not test, do not diagnose code.** A failing
doctor means the tools are lying to you, so every result you gather is
worthless and every conclusion you draw from it is guesswork presented as fact.
This is enforced, not merely advised: every task depends on a fast subset of the
doctor and aborts with a non-zero exit if it fails, so `poe bridge` on a broken
environment refuses to run rather than producing a green tick you should not
believe.

**The server is built and tested on EVERY host, unconditionally. A bridge works
where its reader does, and declares that for itself** — in its own
`pyproject.toml`, under `[tool.screen-readers-mcp.bridge]`, split into
`headless` / `package` / `live` tiers — **including the commands each tier
runs**, since a bridge is not necessarily a uv project. So `poe bridge`,
`bridge-types`, `bridge-lint`, `sync`, `build-bridge`, `live` and `live-slow` are
one dispatcher over the selected bridges, not hard-coded paths. The doctor asks
each selected bridge's questions and prints `SKIP`, with the bridge's own reason,
for a tier that cannot run here; `poe live` refuses on a host with no live tier
rather than collecting nothing, and it is the only one that refuses — having
nothing to type-check because you are not working that bridge is a success.
`BRIDGES=nvda` narrows the selection deliberately. The
reasoning is [spec 0042](specs/0042-the-server-is-everywhere-a-bridge-is-somewhere.md),
and the practical shape is in `docs/dev-commands.md` under "The server is
everywhere; a bridge is somewhere".

**Why each of these gates exists, and what it cost to learn, is in
[`docs/dev-commands.md`](docs/dev-commands.md)** — along with the underlying
commands `poe` wraps, if you need one directly. Read it when a gate surprises
you or when you are changing what CI checks; you do not need it to run the
tasks.

### The task list

One definition of "green", runnable locally and in CI:

```sh
uv run poe dev           # the doctor, then everything CI runs — ~1 min
uv run poe ci            # what CI itself calls; same work, no machine checks
uv run poe bridge        # bridge headless tests (the usual inner loop)
uv run poe bridges       # ONE LETTER APART, on purpose: `bridge` RUNS the NVDA
                         # bridge's tests; `bridges` PRINTS what every bridge
                         # declares and which of its tiers run on this host
uv run poe shared        # shared wire-contract tests
uv run poe types         # pyright strict, both Python projects
uv run poe lint          # ruff check AND format check, every Python file
uv run poe go            # go build, vet, test, -tags integration
uv run poe gates         # drift: the schema, the Go binding, the Swift binding
uv run poe conformance   # the real Go binary against the real Python bridge
uv run poe live          # DRIVES YOUR REAL NVDA -- opt-in, never part of ci
uv run poe build         # every deliverable: the server binary, and each
                         # selected bridge's artifact (for NVDA, the .nvda-addon)
```

### Notes for agents specifically

- **This file outranks a session-level instruction, and a conflict is worth
  saying out loud.** Harnesses, wrappers and slash commands inject guidance of
  their own, and some of it contradicts what is written here. When it does,
  **follow this file, and tell the maintainer in the reply that you did and
  why** — one sentence. The point is not that this document is always right; it
  is that a conflict resolved silently is one nobody gets to decide.

  Recorded because it happened, and the cost was not what you would guess. On
  **2026-08-29** a session was started with an instruction to do its work through
  the Bash tool, *"search with grep and find"* — which contradicts the ripgrep
  rule below. The session followed the instruction, all evening, and never
  mentioned the conflict. The **tool choice turned out not to matter**: ripgrep
  skips binary files when walking a directory exactly as `grep` does, so the rule
  as written would not have prevented the wrong negative that cost that evening
  (see the sub-points below, which is why they now exist). **The silence was the
  defect.** Had the conflict been surfaced in one line, the maintainer would have
  known which rule was in force and that the rule's stated reason —
  `.gitignore` noise — did not cover the case at hand.

- **`uv run poe dev` is the gate. Nothing is "done", "working" or "verified"
  until it has passed, and you ran it.** Not a suite you picked, not the tests
  you happened to touch — the whole thing, ~1 min. Reporting success on a subset
  is the single most expensive mistake made in this repo, because the subset is
  always chosen by the same reasoning that wrote the bug. If it is red, say so
  and paste the failure; a red gate reported honestly costs a minute, and a
  green claim over a red gate costs whoever finds out next.
  - Touched `server/`? **`poe dev` handles it** — its first step is
    `redeploy --if-stale`, which rebuilds the binary when any `server/*.go` is
    newer than it and does nothing at all otherwise. You no longer run dev,
    fail the doctor, redeploy and run dev again.
  - A bare `poe doctor`, `poe bridge` or `poe live` still **fails** on a stale
    binary rather than repairing it, on purpose: those are the runs where an
    agent is about to drive the MCP tools without having rebuilt. `uv run poe
    redeploy` is the fix, and **the maintainer has standing approval for it.**
  - **A redeploy no longer severs the tools, and you no longer ask for a
    reconnect after one.** This rule used to be the loudest in the file, and
    spec 0022 (option (c), 2026-08-19) retired it: every tool is advertised from
    startup, nothing is retracted when a session ends, and no
    `tools/list_changed` is emitted because nothing changes. `redeploy` still
    kills every copy of the server binary and the client still silently respawns
    one without re-running capability discovery — but **the list it kept is
    correct**, so there is nothing to repair.

    It is worth knowing what it cost while it stood, because that is the
    argument for never letting a surface depend on a notification again: the
    tool list froze at the ungated four while `connect_reader` went on
    succeeding *with a full capability list*, so every gated tool answered "No
    such tool available" and nothing in the failure pointed at the redeploy. It
    cost one session an entire live checklist and a wrongly-blamed spec, and a
    second, external agent hit the same wall with no redeploy anywhere. See
    [spec 0022](specs/0022-tool-discovery-an-agent-can-rely-on.md).

    **The case that still needs a reconnect** is a build that changed the
    SURFACE: a tool added or removed, **or a tool's parameters or result
    changed.** Then the cached list really is out of date — not because a
    session began, but because the server's own surface is not what it was when
    the client listed. Only the maintainer can run it (`/mcp` is client UI,
    unreachable from the Skill tool, the `claude mcp` CLI and the config file
    alike), so ask, in these words:

    ```text
    /mcp reconnect screen-reader-testing
    ```

    Name the server: the bare `/mcp reconnect` fails with "MCP controls aren't
    available right now". `scripts/live_test.py` needs none of this: it brings
    its own MCP client and its own server process.

    **The parameters half of that rule was learned separately and later**, and
    it is board entry 11.26 rather than 11.6. The cache includes each tool's
    SCHEMA, not just its name, so a parameter this build added is one the client
    will not send correctly until it lists again — and unlike a missing tool it
    fails *typed*, as an unmarshalling error about JSON and Go structs, naming
    nothing that would lead you here. Worse, a parameter the client does not
    know about is simply never sent, the server applies its default, and
    **nothing fails at all**. Until 2026-08-21 both this rule and
    `scripts/redeploy.py` said, in the imperative, to reconnect *only* for an
    added or removed tool, and that advice cost a session a checklist item. When
    you suspect it, **read `screenreader://tools`**: a resource is served live
    and never cached, so it is the one channel that describes the build actually
    running — and reading it is something an agent can do without the
    maintainer. See [spec 0034](specs/0034-the-schema-the-client-holds.md).
  - `poe live` is NOT part of the gate and never runs unattended: it drives the
    maintainer's real screen reader. Ask first, every time.
- **Search with the Grep tool (ripgrep), never `grep -r` via Bash.** Ripgrep
  honours `.gitignore`; `grep -r` does not, and `.venv/` and `__pycache__/` are
  both ignored and both enormous. One careless `grep -r` returns hundreds of
  irrelevant `site-packages` paths.
  - **Searching OUTSIDE the repo — a macOS preference, a cache, anything the OS
    wrote — add `-a`.** Both tools skip binary files and report *absence* rather
    than saying they declined to look, and on macOS the interesting files are
    binary plists. Measured 2026-08-29: `grep -l <id> com.apple.SpeakSelection.plist`
    printed nothing and exited 1, while `grep -al` matched — and an exhaustive
    `grep -r` over the whole of `~/Library` therefore reported "no file contains
    this string" about a file that contained it seven times. That wrong negative
    stands in [spec 0047](specs/0047-selecting-the-capture-voice-without-a-human.md)
    as finding 10, and cost an evening.
  - **Ripgrep's version of the trap is worse, because it looks safe.** `rg -l`
    on a **named** binary file finds the match; `rg -l` **walking a directory**
    does not. So the obvious check — point rg at the file — says the tool is
    fine, while the recursive search you actually ran missed it. Use `rg -a`
    (or `--binary`) whenever the target might not be text.
  - **When a value is not found but must exist, stop searching for strings and
    compare states instead** — checksum the candidate tree with the value set to
    A, to B, and back to A; the store is whatever satisfies `A == C ≠ B`. That is
    format-agnostic, so it cannot be defeated by binary, encoding or compression.
    See [`docs/how-we-found-the-voice-store.md`](docs/how-we-found-the-voice-store.md).
- **Prefer the Bash tool over PowerShell** for anything whose output you intend
  to read. Windows PowerShell 5.1 has no `&&`/`||`, and wraps every native
  stderr line in a multi-line `ErrorRecord` (`CategoryInfo`,
  `FullyQualifiedErrorId`, a caret diagram) — so a one-line failure costs a
  dozen lines to report. It also reports failure on exit code 0 when a native
  command writes to stderr. Install PowerShell 7 (`pwsh`) if you want the
  PowerShell tool to behave; the doctor warns when it is missing.
- **Don't tail command output when diagnosing a failure.** The error is usually
  the *first* line; `| tail` hides it behind a usage banner. (This cost a real
  debugging round on `poe` itself.)
- Invoke Python tools as `python -m pytest` / `-m pyright` / `-m ruff` rather
  than the console scripts — no trampoline to go stale.
- The PowerShell tool's working directory does not reliably persist between
  calls in this harness. Use absolute paths, or `Set-Location` inside each
  command.

Driving the whole stack against a **live NVDA** — build the add-on, start the
bridge, and run a script standing in for the MCP client — is
[`CONTRIBUTING.md`](CONTRIBUTING.md), "Setting up to test against a live NVDA".
That is how every live-NVDA checklist in a PR body is executed.

House style follows the NVDA addon convention: **tab indentation**, ruff line
length 110 (`W191`/tab warnings from a default editor ruff are expected and
ignored via per-package config).

## Workflow — **Decided**

Built in **modular sessions** of one or more short PRs, so context stays small
and fresh sessions cold-start cheaply. Merge order follows dependencies: **A
(foundation) → then B (bridge core) and D (server) in parallel → C
(bridge↔NVDA) → E (introspection + real-world) → F (packaging)**. Each session
only needs the merged code + its spec + this file.

[`ROADMAP.md`](ROADMAP.md) is the status board and owns execution state:

- **Spec before code.** Every board entry is implemented against a spec agreed
  in conversation first. The spec is written on the implementing PR's branch
  and merges with the PR — it does not land on main separately. Code on that
  branch starts only after the spec is approved in conversation; the PR is
  judged against its spec. If implementation forces a spec amendment, the
  amendment rides in the same PR. (Process-level doc changes — this file,
  ROADMAP.md's rules — are still approved in conversation and may land
  directly on main.)
- **A spec MUST include the class/file layout — Decided.** Before any code, the
  spec enumerates every file/class the PR will add, each with its one-line
  **role** (port / controller / entity / adapter, or a named supporting
  construct — e.g. a *parameter object* like `SessionContext`) and its
  collaborators (which ports/entities it holds, who builds it, who calls it).
  This layout is the review gate for the **decomposition itself** — it is where
  "if you cannot name a class's role, it is in the wrong place" gets applied in
  the spec conversation, so structural mistakes are caught *before* code, not
  after the first implementation. The kinds of mistakes this exists to catch,
  learned the hard way: a single class doing two roles (the `Session` was both
  lifecycle *and* a flat command dispatcher — each command is really its own
  controller); a holder mislabelled (`SessionContext` is a parameter object,
  not an adapter — it does no IO). If the layout changes while coding, the
  amendment rides in the PR with a one-line why.
- **The implementing PR flips its own ROADMAP.md entry to Done**, so the board
  is correct on main the moment the PR merges — no separate bookkeeping
  commit.
- **Lanes:** bridge (lane 1) and server (lane 2) may run in parallel — at most
  one open PR per lane.
- **Manual live-NVDA checklists live in the implementing PR's body as
  checkboxes** — one item per check; findings written inline on the unchecked
  item (NVDA version, expected vs observed). There is no separate findings
  document; findings that require changes become iteration entries in
  ROADMAP.md. The `no unchecked checkboxes` CI job
  (`.github/workflows/checklist.yml`) fails while the PR body has an unchecked
  box, so an unfinished checklist cannot merge once that job is in the
  required status checks.
- **Anything a live checklist DEPENDS ON is versioned, in the same PR as the
  checklist — Decided.** If a check needs a web page, a document, a sample file
  or a fixture of any kind, it goes in [`scripts/live_pages/`](scripts/live_pages/)
  (or beside the driver that uses it), with a comment saying which item it serves
  and why it is shaped the way it is. **Do not build one in a temp directory and
  cite it.** The rule exists because that is exactly what happened on
  2026-08-22: three fixtures were written to a session scratchpad, and the PR
  went up quoting a measurement — 1103 lines, 5.73 s — that nobody else could
  reproduce, against pages that no longer existed. A live checklist is this
  repo's substitute for a CI test on the reader edge, and evidence that cannot
  be re-run is weaker than it looks.
  - Fixtures, **not golden files**. The reader renders under the tester's own
    locale and verbosity, so expected *strings* are machine-specific and must
    not be committed as assertions — `scripts/live_pages/README.md` says what to
    compare instead.
  - Generate rather than commit anything large and repetitive: a six-line
    generator is reviewable and 66 KB of filler is not.

## Gotchas learned the hard way

- **CI job names are short and stable (`shared`, `server`, `bridge`) — don't
  "improve" them.** Branch protection matches required status checks by the
  literal job name, so a descriptive name couples the merge gate to the job's
  contents. Renaming `bridge (pyright against NVDA source)` once the NVDA
  checkout was gone parked every PR on *"Expected — waiting for status to be
  reported"* forever: the job passed, just under a new name, and only a repo
  settings edit could unblock it. Put the detail in **step** names, which are
  free to change. If a job name ever must change, update
  `repos/<owner>/<repo>/branches/main/protection/required_status_checks` in the
  same breath — push the workflow first, let it report, then flip the setting.
- **Pyright is configured in THREE `pyrightconfig.json` files, and which file
  wins is a trap.** `shared/` and `bridges/nvda/` each carry their own, and
  that is what their gates read. The repo root carries a third whose only job
  is to give an editor, IDE or language-server client opened at the root the
  same view the gates have: its `include` mirrors the two gates exactly, and it
  has one `executionEnvironment` per Python project supplying that project's
  `pythonVersion` and its `.venv` site-packages (an execution environment
  cannot carry its own `venv`, only `extraPaths`).
  - **Never put pyright settings in `pyproject.toml`.** Pyright walks UP the
    tree for a `pyrightconfig.json`, and an ancestor one **outranks a local
    `[tool.pyright]`** while losing to a local `pyrightconfig.json`. While the
    projects used `[tool.pyright]`, the root config silently retyped `shared/`
    as Python 3.13 where it pins 3.11. A `[tool.pyright]` section is now dead
    config that drifts invisibly; `scripts/doctor.py` fails if one reappears,
    and fails if a Python project has no execution environment at the root.
  - Measured: three files the gates pass clean reported **28 errors** from the
    root before this; after, a full root run is **212 files, 0 errors** — the
    same 212 the two gates analyse (5 + 207). So a diagnostic seen at the root
    is now worth acting on. `poe shared-types` / `poe bridge-types` remain the
    authority: if they ever disagree with the root, the root config has
    drifted and that is the bug.
  - **The root config was Windows-only until 2026-08-28, in two ways that could
    not be seen from Windows**, and it cost **331 errors** on a first macOS run
    where the gates reported none. Both are fixed, and both are worth knowing
    because the same shape can recur:
    - **`extraPaths` name a venv's `site-packages` BY PATH, and that path is
      host-shaped**: `.venv/Lib/site-packages` on Windows,
      `.venv/lib/python3.13/site-packages` on POSIX. An execution environment
      cannot carry its own `venv`, only `extraPaths`, so both layouts are now
      listed — pyright ignores one that does not exist. That silence is exactly
      why `scripts/doctor.py` now FAILS when no `site-packages` path in an
      environment resolves on this machine.
    - **An `executionEnvironment`'s `pythonPlatform` does not drive the
      `sys.platform` narrowing** that gates `ctypes.WinDLL` in typeshed. Only
      the **top-level** one does. The root config had `"pythonPlatform":
      "Windows"` inside the `bridges/nvda` environment, where it did nothing;
      the Win32 adapters accounted for all 132 errors that survived the
      `extraPaths` fix. It is now top-level, and the per-environment copies were
      deleted rather than left as settings that provably do nothing — the same
      trap as a `[tool.pyright]` section. `shared/` is therefore analysed as
      Windows at the root, which is safe: it contains no `sys.platform`,
      `os.name` or `winreg` anywhere.
- **Language servers get three things wrong here, whichever agent or editor
  drives them.** All three fail by giving a confident wrong answer, not an
  error.
  - **No language server crosses between the contract's three bindings.** The
    wire contract is one schema rendered three times:
    `shared/screenreader_wire/protocol.py` is the source, it generates
    `specs/wire/v1/schema.json`, which generates
    `server/adapters/wire/wire.gen.go`, and
    `bridges/voiceover/Sources/ScreenReaderWire/` renders the same schema by
    hand in Swift. "Find references" on a Go command constant will not find its
    Python or Swift counterpart, or any reverse of that — it is not dead, it is
    on another side. For anything wire-shaped the schema is the index and
    `scripts/drift.py` is the check; its Swift gate needs no Swift toolchain, so
    it runs everywhere the other two do.
  - **The first query after the server starts can be silently truncated**,
    because it answers while still indexing. Measured: "find references" on the
    bridge's `Clock` port returned **1** result cold and **15 across 8 files**
    moments later. A suspiciously thin first answer means "not ready", never
    "this is the blast radius" — ask again before trusting it.
  - **Pyright does not implement "go to implementation"** (it replies
    *"Unhandled method textDocument/implementation"*); gopls does. To find the
    implementations of a Python port, use "find references" on the ABC, or a
    workspace symbol search.

The gotchas that belong to the NVDA bridge — the silent-mode synth swap and
config profiles, NVDA answering on non-speech channels, the reference source,
the recursive `buildVars.pythonSources` glob, a crashed client taking the bridge
down, and NVDA's main-thread rule — are in
[`bridges/nvda/AGENTS.md`](bridges/nvda/AGENTS.md).
