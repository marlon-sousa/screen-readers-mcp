# 0045 — a wire module named after the contract, not the reader

Status: **proposed 2026-08-29.** Board entry **11.36**, lane 2 (both halves in
practice). Opened on 2026-08-29 by lane 3, which is about to write a **third**
binding of this contract.

The one-line summary:

> **`nvda_mcp_wire` was named when NVDA was the identity rather than the first
> bridge. It becomes `screenreader_wire`, imported as
> `screenreader_wire.protocol`. No behaviour changes and `PROTOCOL_VERSION` does
> not move.**

Shipped in one PR with [spec 0044](0044-the-local-endpoint-off-windows.md), by
the maintainer's decision: both are lane-2 work that exists to unblock lane 3,
and both touch `specs/wire/v1/protocol.md`.

---

## Part 1 — the evidence

### The name was already scheduled to change, and the condition has been met

[Spec 0005](0005-multi-reader-direction.md), which decided the server is a
reader-agnostic chassis, left one thing open:

> Marlon is deciding. The `nvda_mcp_wire` package rename is deferred until the
> repo name settles, so both rename once, together.

The repo settled: it is **`screen-readers-mcp`**, the Go module is
`github.com/marlon-sousa/screen-readers-mcp/server`, the binary is
`screenreader-mcp`, and every MCP resource is `screenreader://…`. The Python
wire module is the last thing in the tree still named after NVDA that is not
*about* NVDA.

### What the name now claims, and why that is worse than untidy

The module is the reference implementation of a contract that:

- `bridges/nvda/` implements in Python,
- `server/adapters/wire/` implements in Go, generated from the schema this
  module produces,
- and lane 3's **13.3** is about to implement in Swift, against
  `specs/wire/v1/schema.json`.

`shared/AGENTS.md` and `specs/0006` already say the shared module is the
*contract*, not NVDA's code. A Swift bridge for VoiceOver reading
`python -m nvda_mcp_wire.schema` in the generation instructions is being told
something false about what it is implementing.

### Blast radius, measured

`rg` over the working tree, excluding `.git`: **73 occurrences across 43
files**. By kind:

| Kind | Files | What changes |
|---|---|---|
| The package itself | `shared/nvda_mcp_wire/` (4 files), `pyproject.toml`, `pyrightconfig.json`, `uv.lock`, `README.md`, `tests/unit/` (2) | Directory name, distribution name, `include`, imports |
| Tooling | `scripts/doctor.py`, `scripts/drift.py`, `bridges/nvda/sync_shared.py`, `bridges/nvda/tests/conftest.py`, root `pyrightconfig.json`, `.gitattributes`, `.github/workflows/release-nvda-bridge.yml` | Paths and one `python -c` |
| Documents | `AGENTS.md`, `shared/AGENTS.md`, `CONTRIBUTING.md`, `ROADMAP.md`, `specs/wire/v1/protocol.md`, ~20 specs | Prose naming the path |

**Nothing in the add-on package changes.** `sync_shared.py` copies one file to
`addon/globalPlugins/nvdaMcpBridge/protocol.py`, and the add-on imports it as
`from . import protocol`. The source path in that script changes; the
destination, the import and every line of bridge code do not.

**Nothing in `server/` changes.** The Go binding is generated from
`schema.json`, which is a file path, not a module name.

## Part 2 — the shape

### Decision 1: `screenreader_wire`, distribution `screenreader-wire` — **agreed in conversation, 2026-08-29** (recorded in [spec 0043](0043-the-voiceover-bridge-is-one-swift-bundle.md), open question 2)

Imported as `screenreader_wire.protocol`, so both halves still address the
contract through a module named `protocol` — the rule `AGENTS.md` states, and
the reason the module inside the package keeps its name.

**`screenreader` rather than `screen_readers`**, because it is the identifier
the product surface already uses (`screenreader-mcp`, `screenreader://…`). The
repo and Go module are plural, so the two conventions were already inconsistent
and one had to win; the one an agent sees at runtime won.

**What ruled out the short names** — `wire`, `protocol` — is hard invariant 1:
this module is copied verbatim into the add-on and runs inside NVDA's
interpreter, sharing `sys.modules` with every other add-on. A collision there is
not a name clash, it is somebody's screen reader.

### Decision 2: no compatibility alias — **agreed in conversation, 2026-08-29**

No `nvda_mcp_wire` shim re-exporting the new module. There are no external
consumers (the distribution has never been published), the two in-repo consumers
are renamed in the same commit, and `AGENTS.md` forbids re-export facades in
this package specifically. A shim would be a second name for the contract, which
is the exact defect being repaired.

### Decision 3: the rename is mechanical, and the two documents that *decided* something get a dated line — **agreed in conversation, 2026-08-29**

Every occurrence naming a real path or import becomes the new one, in specs
included: a document pointing at `shared/nvda_mcp_wire/protocol.py` after this
lands is pointing at nothing, and this repo's specs are read as current
description, not as archaeology.

Two places get more than a substitution, because they recorded the *decision*
rather than the path:

- `specs/0005-multi-reader-direction.md` — its "Open — repository name" section
  gains a line saying the deferred rename happened, dated, naming this spec.
- `shared/AGENTS.md` — one line on why the package is named for the contract, so
  the next person to propose `wire` finds hard invariant 1's argument where they
  are standing.

### Decision 4: `PROTOCOL_VERSION` does not move, and `DEFAULT_PIPE_NAME` keeps its name — **agreed in conversation, 2026-08-29**

The wire *shape* is untouched: no frame, field, command, enum or default value
changes. Under the policy in `shared/AGENTS.md` a rename of the reference
implementation's package costs no version bump, and a bridge built against v1
yesterday is a bridge built against v1 tomorrow.

`DEFAULT_PIPE_NAME` stays `DEFAULT_PIPE_NAME` with its value, even though spec
0044 renames the server's transport *kind* to `local` in the same PR. It is the
NVDA bridge's pipe name — a Windows fact about one reader — and renaming a
protocol constant is a contract change, which this entry explicitly is not.

### What does NOT change

- Any behaviour, anywhere. This entry is a rename and its consequences.
- The add-on package, its imports, its build, or the copied `protocol.py`.
- `server/`, including the generated Go binding.
- `specs/wire/v1/schema.json` — the generator's *output* is byte-identical,
  which `poe gates` proves.
- The root dev-task host's project name (`nvda-mcp-devtools`); see
  "Not in scope".

## Part 3 — what ships

1. `shared/nvda_mcp_wire/` → `shared/screenreader_wire/` (`git mv`, so history
   follows).
2. `shared/pyproject.toml`: `name = "screenreader-wire"`, the hatch wheel
   package, the description.
3. `shared/pyrightconfig.json` `include`, root `pyrightconfig.json`
   `extraPaths`/execution environment.
4. `shared/uv.lock` regenerated.
5. Imports in `shared/tests/unit/` and `shared/screenreader_wire/schema.py`.
6. `scripts/doctor.py`, `scripts/drift.py` (including the
   `python -c "…from screenreader_wire.schema import…"`),
   `bridges/nvda/sync_shared.py` (source path and the generated header line),
   `bridges/nvda/tests/conftest.py`.
7. `.gitattributes` comment, `.github/workflows/release-nvda-bridge.yml`'s
   version probe.
8. Documents: `AGENTS.md`, `shared/AGENTS.md`, `shared/README.md`,
   `CONTRIBUTING.md`, `ROADMAP.md`, `specs/wire/v1/protocol.md`, and the specs
   that name the path — plus the two dated lines of decision 3.

## Class/file layout

No class is added, removed or changed, and no file plays a new role. That is the
statement this section makes for this entry, and it is why the table below is
paths rather than roles.

| File | Role | Change |
|---|---|---|
| `shared/screenreader_wire/protocol.py` | the wire contract (moved) | Path only. Bytes identical — which is checkable, and is how "no behaviour changed" is proved. |
| `shared/screenreader_wire/schema.py` | generator (moved) | Path, plus its own module docstring and the `python -m` line it documents. |
| `shared/screenreader_wire/__init__.py`, `py.typed` | package files (moved) | Path; `__init__.py`'s prose. |
| `shared/tests/unit/test_protocol.py`, `test_schema.py` | unit tests (existing) | Imports. The mirror rule is unaffected: `tests/unit/test_protocol.py` ↔ `screenreader_wire/protocol.py`. |
| `shared/pyproject.toml` | project | `name`, description, `[tool.hatch.build.targets.wheel] packages`. |
| `shared/pyrightconfig.json`, `pyrightconfig.json` | type-check config | `include`, `extraPaths` — checked by `poe doctor`, which fails if a path stops resolving. |
| `bridges/nvda/sync_shared.py` | build script | `SOURCE` path and the `_HEADER` it stamps into the copy. |
| `bridges/nvda/tests/conftest.py` | test bootstrap | Docstring path. |
| `scripts/doctor.py`, `scripts/drift.py` | dev tooling | Paths and the `python -c` import. |
| `.gitattributes`, `.github/workflows/release-nvda-bridge.yml` | repo/CI | One comment, one path in a version probe. |
| Documents (see part 3) | documentation | The path; two of them a dated line. |

## What is deliberately not built

- **A compatibility alias.** Decision 2.
- **A `PROTOCOL_VERSION` bump.** Decision 4.
- **A rename of `DEFAULT_PIPE_NAME`** to match spec 0044's `local` vocabulary.
  It names the NVDA bridge's Windows pipe, and 0044 explicitly leaves the
  Python constants alone.
- **Renaming the root dev-task host** (`nvda-mcp-devtools`) or the add-on
  package (`nvdaMcpBridge`). The first is not shipped and is not the contract;
  the second is an installed add-on's identity on real machines and a change
  there is a migration, not a rename.
- **Publishing the distribution.** Nothing here makes it a package anybody
  installs from an index.

## Honest limits

- **Anyone with an existing `shared/.venv` has the old distribution installed
  into it.** `uv run poe fix` reinstalls the project venvs, and `poe doctor`
  reports a venv whose console scripts no longer resolve — but the first symptom
  after pulling this is likely an import error in an editor, not a failing gate.
  `CONTRIBUTING.md` gains the line.
- **Open PRs and branches touching `shared/` will conflict**, in the way a
  directory rename always does. Lane 1 has no open PR at the time of writing,
  which is part of why the entry is taken now.
- **Old PR bodies, issues and merged-commit messages keep the old name.** They
  are history and are not rewritten; the rename is discoverable from this spec
  and from spec 0005's dated line.
- **A rename cannot be proved by the gates alone.** `poe dev` proves the tree
  still type-checks, tests and generates an identical `schema.json`; it cannot
  prove no document still says the old name. The check for that is a final
  `rg nvda_mcp_wire`, and it is part of the PR.

## Open questions

None. Every decision above was taken in conversation on 2026-08-29 and recorded
in spec 0043's open-question 2 and board entry 11.36 before this spec was
written.

## Not in scope

- The Swift binding itself (lane 3, **13.3**), which this entry exists to
  precede.
- The repo name, the Go module path, the binary name and the MCP resource
  scheme — all already settled, and all the reason this name is the odd one out.
