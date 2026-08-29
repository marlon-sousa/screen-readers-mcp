# 0042 — the server is everywhere, a bridge is somewhere

Status: **proposed 2026-08-28.** Board entry **11.34**, neither lane (dev
tooling, tests and CI). Opened on 2026-08-28 by the first attempt to work this
repo from macOS.

This spec is about the *repo*, not the product. Nothing in `server/` or
`bridges/nvda/`'s shipped code changes behaviour. What changes is the set of
assumptions the tooling makes about the machine it is standing on, and the
place those assumptions are written down.

The one-line summary, which is also the organising principle:

> **The server must work on every host. A bridge works where its reader does.
> So the host is not the axis — the bridge is, and each bridge declares its
> own.**

---

## Part 1 — the evidence

### The gate on macOS, measured

macOS 15.0, x86_64, Homebrew at `/usr/local`, `uv` 0.12.7, Go 1.25.14,
CPython 3.13.15. `uv run poe doctor` reports the environment sound. Then:

| Task | Result on macOS, before this spec |
|---|---|
| `poe shared` | 81 passed |
| `poe types` | 0 errors, both projects |
| `poe lint` | clean |
| `poe go` (incl. `-tags integration`) | all packages ok |
| `poe gates` | no drift |
| `poe conformance` | ok — the real Go binary against the real Python bridge |
| `poe build-addon` (now `build-bridge`) | builds `nvdaMcpBridge-0.1.0.nvda-addon` |
| **`poe bridge`** | **aborts during collection** |

So the repo is *already* almost entirely portable. The Go half was written
portable on purpose — `real_bridge_session_windows_test.go` carries
`//go:build conformance && windows`, and `pythonInterpreter` only adds the `py`
launcher to its candidate list `if runtime.GOOS == "windows"`. **Go already has
the mechanism and uses it correctly. This spec does not invent a second one for
Go.** Everything below is about the Python tooling and the tests, which have no
equivalent and assume Windows silently.

### The one real failure, and why a marker could not have caught it

```
tests/integration/test_live_nvda_pipe_e2e.py:32: from nvdaMcpBridge.adapters import named_pipe_transport
addon/globalPlugins/nvdaMcpBridge/adapters/named_pipe_transport.py:52:
    KERNEL32 = ctypes.WinDLL("kernel32", use_last_error=True)
E   AttributeError: module 'ctypes' has no attribute 'WinDLL'
```

Two modules do this: `test_live_nvda_pipe_e2e.py` and
`test_named_pipe_session_roundtrip.py`. Note what does *not* save them:
`test_live_nvda_pipe_e2e.py` is already `pytestmark = pytest.mark.live_nvda`
and the default run is `-m 'not live_nvda'`. **A marker deselects a test after
its module has been imported**, so the import runs anyway and collection dies
before any selection happens. The guard has to be at import time or it is not a
guard.

With those two modules excluded by hand the bridge suite is **588 passed, 1
skipped, 6 deselected in 3.72s**. Nothing else in the bridge is Windows-bound.

### The doctor asks Windows questions, and one of them is a question no test asks

Four findings, in increasing order of how much they mislead:

1. `pwsh` is reported `WARN  not on PATH`. Its stated reason is entirely about
   *Windows* PowerShell 5.1 having no `&&` and wrapping stderr in
   `ErrorRecord`. On macOS the warning is not merely unhelpful, it is about a
   shell the machine does not have and would not use.
2. `check_conformance_python` looks for the **Windows `py` launcher** and warns
   when there is none. But the conformance tier is Go, and
   `pythonInterpreter` probes `python`, `python3.13`, `python3` first — and
   `poe` puts the workspace venv's 3.13 on `PATH`, so the tier passes on macOS
   with no `CONFORMANCE_PYTHON` at all. **Verified: `poe conformance` is `ok`
   with the variable unset.** The doctor was warning about a requirement the
   thing it speaks for does not have.
3. `scripts/redeploy.py` enumerates processes with
   `powershell -Command "Get-CimInstance Win32_Process ..."` and kills with
   `taskkill /F /PID`. On macOS neither exists; `running_copies()` prints
   "could not enumerate processes" to stderr and returns `[]`, so a redeploy
   silently kills nothing and reports success.
4. **The repo-root `pyrightconfig.json` is broken on macOS, and loudly.** Its
   three `executionEnvironments` name `.venv/Lib/site-packages` — the *Windows*
   venv layout. On POSIX the path is `.venv/lib/python3.13/site-packages`, so
   every environment resolves to nothing. Measured at the root on macOS:
   **331 errors**, where `AGENTS.md` documents 212 files and 0. That file's
   entire purpose is to give an editor or language server the same view the
   gates have, and on macOS it gives the opposite: a page of phantom errors
   that a reader cannot tell from real ones. This is the exact failure the
   "three pyrightconfig files" gotcha was written about, on a new axis.

### `.exe` is a claim about the file, and on macOS it is false

`poe build-server` writes `server/screenreader-mcp.exe` on every platform. On
macOS that produced a **Mach-O 64-bit executable** named `.exe` — a file whose
name says "Windows PE" and whose contents say otherwise. Nothing breaks, which
is the problem: the name is the only thing a reader has to go on when a path
turns up in an MCP config, a script, or a bug report, and here it lies.

---

## Part 2 — the shape

### Decision 1: the server is unconditional — **agreed in conversation, 2026-08-28**

Every server task — build, vet, unit and integration tests, gofmt,
staticcheck, the wire-binding gate, the Linux build, and the conformance tier —
runs on **every** host, with no guard and no skip. The same is true of the
doctor's core tool checks (`uv`, `go`, `git`, `rg`) and its server-binary
check.

This is a requirement, not an observation: the server is the component an agent
on any desktop talks to, and a host where it is not built and tested is a host
where it is not supported. If a server test cannot run somewhere, that is a bug
in the test, not a reason for a platform guard.

The one place the server is already host-shaped is its named-pipe transport,
and Go's build tags handle it. Nothing here changes that.

### Decision 2: a bridge declares its own hosts, per tier — **agreed in conversation, 2026-08-28**

NVDA is Windows. JAWS is Windows. VoiceOver is macOS. TalkBack is Android with
a host SDK. Each needs different tools, and each can do *different amounts* of
its work on a given machine — the NVDA bridge's headless suite runs anywhere
because its domain is stdlib-only Python, while its live tier needs a running
NVDA.

So a bridge's requirements are declared **by the bridge, in the bridge's own
`pyproject.toml`**, split by *tier*:

```toml
[tool.screen-readers-mcp.bridge]
reader = "NVDA"

[tool.screen-readers-mcp.bridge.tiers.headless]
hosts = ["*"]

[tool.screen-readers-mcp.bridge.tiers.package]
hosts = ["*"]
tools = ["scons", "msgfmt", "xgettext"]

[tool.screen-readers-mcp.bridge.tiers.live]
hosts = ["windows"]
reason = "NVDA itself runs only on Windows"
```

Three tiers, and they are the three questions anyone actually asks of a bridge:

| Tier | The question | NVDA's answer |
|---|---|---|
| `headless` | can I run its tests here? | anywhere |
| `package` | can I build its shippable artifact here? | anywhere (scons is pure Python; verified on macOS) |
| `live` | can I drive the real reader here? | Windows only |

`reason` is not decoration. It is the text the doctor prints when it skips the
tier, so a developer on the wrong host is told *why* rather than shown a gap.

**And a tier declares its own COMMANDS**, in a `tasks` table beside its hosts:

```toml
[tool.screen-readers-mcp.bridge.tiers.headless.tasks]
test = "uv run --directory bridges/nvda --python 3.13 --with pytest python -m pytest -q"
types = "uv run --directory bridges/nvda --python 3.13 --with pytest --with pyright python -m pyright"
```

This was **not** in the first draft of this spec, which called task generation
speculative while there is one bridge. That was wrong, and the argument that
overturned it is short: `poe bridge-types` named `bridges/nvda` in its own
command string, so on a host where nobody is working the NVDA bridge it
type-checked the NVDA bridge anyway. "The NVDA bridge" and "a bridge" were the
same thing, which is the exact conflation this spec exists to remove. And the
commands can only live with the bridge, because **a bridge is not necessarily a
uv project**: NVDA's tests are pytest under uv, and a VoiceOver bridge in Go or
Swift will be neither.

### Decision 3: selection is by declaration, overridable by environment — **agreed in conversation, 2026-08-28**

`scripts/bridges.py` reads every `bridges/*/pyproject.toml`. A bridge is
**selected** when:

- `BRIDGES` is set in the environment — exactly those names, and an unknown
  name is an error rather than a silent empty set; otherwise
- it declares the current host in **any** tier.

So a Windows box selects the NVDA bridge and reports all three tiers; a macOS
box selects it and reports `live` as skipped with NVDA's own reason; and when a
VoiceOver bridge lands declaring `hosts = ["macos"]`, the same macOS box picks
it up with no configuration edited anywhere. `BRIDGES=nvda` is how you narrow
that deliberately.

Committing the selection to the root `pyproject.toml` was rejected: it is
machine state, and a Windows developer and a macOS developer want different
values in the same tracked file.

`scripts/bridge_task.py <task>` then runs that task for every selected bridge
whose declaring tier runs here, and prints `SKIP` with the bridge's own reason
for one that does not. `poe bridge`, `bridge-types`, `bridge-lint`, `sync`,
`build-bridge`, `live` and `live-slow` are all that one dispatcher.

**Doing nothing is a success for most tasks and a failure for one.** If you are
not working a bridge on this machine there is nothing of it to type-check, and
calling that a failure would make `poe types` red on a perfectly good checkout.
`poe live` is the exception — silently doing nothing there reads exactly like a
pass — so it alone passes `--require`.

### Decision 4: a skipped check reports itself — **agreed in conversation, 2026-08-28**

The doctor gains a fourth status, `SKIP`, printed like the others and counted
separately from warnings. A check that does not apply here says so, with its
reason:

```
  SKIP  pwsh                 not applicable on macos -- Windows PowerShell only
  SKIP  nvda: live           NVDA itself runs only on Windows
```

Silence was the alternative and it is worse. A doctor that simply omits what it
did not ask cannot be read as a statement about the machine, and the first
question a developer on a new host has is precisely "what is *not* being
checked here?".

`SKIP` never affects the exit code. Only `FAIL` does, as today.

### Decision 5: the binary carries its host's executable convention — **agreed in conversation, 2026-08-28**

`server/screenreader-mcp.exe` on Windows, `server/screenreader-mcp` everywhere
else. That is the whole rule: the platform's own convention for naming an
executable, and nothing more.

**This convention is already in the repo, in the one place that had to be
portable.** `buildServer` in `server/tests/conformance/python_bridge_test.go`
builds `screenreader-mcp` and appends `.exe` only `if runtime.GOOS == "windows"`.
`poe build-server` was the odd one out, not the thing being changed.

A host-and-architecture suffix (`screenreader-mcp-darwin-arm64`, matching the
release artifacts in `release-server.yml`) was considered and **rejected**. Its
one advantage is that two hosts could share a single checkout without
overwriting each other's build, which is a situation nobody in this project is
in; against that it lengthens every path a person types into an MCP config, and
it makes the dev binary's name differ from what a developer would guess. The
release artifacts keep their fully-qualified names because they are downloaded
by strangers who must be able to tell them apart; a build sitting in your own
checkout is not.

`scripts/platforms.py` owns the name, as a single `SERVER_BINARY_NAME` derived
from the host. `doctor.BINARY` is built from it, `redeploy.py` and the new
`build_server.py` import it rather than restating it, and `.gitignore` widens to
`server/screenreader-mcp*` so both spellings — and any stale one — stay ignored.

The cost is real and accepted: every document quoting
`server/screenreader-mcp.exe` gains its non-Windows spelling, and a macOS or
Linux developer who already built one has a stale `.exe` in their checkout.
It is not migrated, symlinked or deleted for them — a stale binary that keeps
working under an old name is exactly the failure `redeploy` exists to prevent,
and `.gitignore` covers it either way.

### Decision 6: a Windows-only test skips at module level, not by omission — **agreed in conversation, 2026-08-28**

`tests/support/platforms.py` gains `skip_module_unless_windows(reason)`, called
at the top of the two named-pipe modules *before* the Win32 import:

```python
skip_module_unless_windows("named pipes are a Win32 facility; the bridge's leaf is ctypes")

from nvdaMcpBridge.adapters import named_pipe_transport  # noqa: E402
```

Rejected: `collect_ignore` in a `conftest.py`. It works, and it makes the tests
*disappear* — the suite count silently drops and nothing says a transport went
untested on this machine. A module-level skip reports as a skip, which is the
honest signal, and it puts the reason at the site rather than in a list
somewhere else.

`E402` is added to `per-file-ignores` for
`test_named_pipe_session_roundtrip.py`, alongside the four modules already
there for the same structural reason.

The helper deliberately does **not** read the bridge declaration from Decision
2. These two modules are Windows-only because of the **transport** — a Win32
named pipe — not because of the reader, and coupling a test guard to the
reader's registry would state a relationship that does not exist.

### Decision 7: the root pyright view is host-independent, and the doctor proves it — **agreed in conversation, 2026-08-28**

Two changes, and the second replaces what this decision first said.

**The venv layout.** Each `executionEnvironment` lists both spellings:

```
"bridges/nvda/.venv/Lib/site-packages",
"bridges/nvda/.venv/lib/python3.13/site-packages",
```

pyright ignores an `extraPath` that does not exist, so listing both is correct on
both hosts and wrong on neither. That is also its weakness — a path that stops
existing fails silently, which is how this got to 331 errors unnoticed. So
`_check_root_pyright_config` is extended: **every execution environment whose
venv exists must have at least one `site-packages` extraPath that exists on this
machine**, and a FAIL says which one does not.

"Whose venv exists" is not a hedge, and it was learned the expensive way: the
first push of this PR turned **both** the `nvda-bridge` and `portable` jobs red,
because a CI job builds only the project environments its own task needs — so
`shared/.venv` genuinely does not exist while the bridge job runs, and the check
called that a broken config. A missing venv is `check_dev_tools`'s question;
this check owns "your paths name the wrong **layout**", which can only be asked
where there is a venv to name. Verified both ways: with `shared/.venv` moved
aside the doctor is silent and exits 0, and with a deliberately wrong
`site-packages` path it still FAILs and names it.

**The Win32 leaves.** With the layout fixed, 132 errors remained on macOS, all in
`named_pipe_transport.py` and `named_pipe_listener.py`, all about `ctypes.WinDLL`
and `ctypes.WinError`. The root config already said `"pythonPlatform": "Windows"`
inside the `bridges/nvda` execution environment, where **it does nothing**: an
execution environment's `pythonPlatform` does not drive the `sys.platform`
narrowing that typeshed gates those symbols on. Only a **top-level** one does.

Setting it at the top level takes the root run to 0 errors, and it was tried and
**rejected**: the root config covers `shared/` too, and `shared/` is not a Windows
project. A file that says "analyse this whole repo as Windows" makes a claim
about the repo that is not true, and the root view exists to mirror the gates
rather than to overrule them.

So instead the two Win32 leaves join the root config's `ignore` list, beside the
NVDA edge (`adapters/nvda_*.py`) already there for the same kind of reason: they
are the host-bound edge, and the root view is the host-independent one. **Nothing
loses coverage** — `bridges/nvda/pyrightconfig.json` still analyses them under its
own top-level `pythonPlatform: "Windows"`, which is correct there and is what
`poe bridge-types` runs. Measured on macOS: root 331 → 0, `poe bridge-types`
unchanged at 0.

That per-bridge config's `pythonPlatform` is not a statement about the
developer's machine — it is a statement about where the add-on runs, which is
Windows no matter who is typing.

### Decision 8: CI gains one matrix job, and the four required names do not move — **agreed in conversation, 2026-08-28**

`shared`, `server`, `conformance` and `nvda-bridge` keep their literal names and
their `windows-latest` runner, untouched. A **new** job is added:

```yaml
  portable:
    strategy:
      fail-fast: false
      matrix:
        os: [macos-latest]     # ubuntu-latest joins this list, and nothing else changes
    runs-on: ${{ matrix.os }}
```

whose only step is `uv run poe ci` — the same definition of green, on another
host. Adding Linux is one word in one list; that is the test of whether this
structure is worth anything.

New job names, therefore a deliberate branch-protection decision **later**, made
after the job has reported once — the same rule the `conformance` job's own
header records.

### What does NOT change

- Any shipped behaviour of the server or the add-on.
- The wire contract, the schema, or the generated Go binding.
- `pythonPlatform: "Windows"` for the add-on's type check.
- The four existing CI job names and their runner.
- The **meaning** of the task names. `poe bridge` still runs bridge tests and
  `poe types` still type-checks; what changed is that they ask which bridges this
  host is working on rather than assuming one. The single rename is
  `build-addon` → `build-bridge`, because "addon" is NVDA's word for its own
  artifact and the task builds whatever each bridge calls its deliverable.

---

## Part 3 — what ships

1. A host layer for the Python tooling: `scripts/platforms.py`.
2. A bridge registry that reads each bridge's own declaration:
   `scripts/bridges.py`, and the declaration block in
   `bridges/nvda/pyproject.toml`.
3. A doctor restructured into **core → server → per-selected-bridge**, with a
   `SKIP` status, and with the root-pyright check extended to prove its
   `extraPaths` resolve here.
4. The host's executable convention for the binary's name, and
   `scripts/build_server.py` as its one builder — imported by `redeploy.py` so
   there is a single build command.
5. A POSIX path in `redeploy.py` for finding and killing running servers.
6. Import-time guards on the two named-pipe test modules.
7. `poe bridges`, which prints the registry: every bridge, every tier, and
   whether it runs here.
8. `poe live` / `live-slow` refusing on a host whose selected bridges declare no
   live tier, instead of running pytest and collecting nothing.
9. The `portable` CI job.
10. Documentation: `CONTRIBUTING.md` prerequisites by host and by bridge plus a
    macOS setup section, `docs/dev-commands.md` on what is scoped and why,
    `AGENTS.md`, and the binary name wherever it is quoted.

## Class/file layout

Everything here is dev tooling, so the four-role vocabulary of `AGENTS.md`
("port / controller / entity / adapter") does not apply — that vocabulary
governs `server/` and `bridges/*/`, which this spec does not touch. Each file
below states the role it plays *in the tooling*.

| File | Role | Collaborators |
|---|---|---|
| `scripts/platforms.py` | **new** — host facts. `Host` (`enum.StrEnum`: `WINDOWS`, `MACOS`, `LINUX`), `current()`, `supports()`, `SERVER_BINARY_NAME`. The single place `sys.platform` is read in `scripts/`. (Amendment while implementing: the poe guard is `bridges.py --require-tier live`, not a host name here — the question `poe live` asks is about a bridge's tier, not about an OS.) | imported by `doctor.py`, `bridges.py`, `build_server.py`, `redeploy.py` |
| `scripts/bridges.py` | **new** — the bridge registry. Reads `bridges/*/pyproject.toml`, exposes `Bridge` (name, reader, tiers) and `Tier` (name, hosts, tools, reason), `discover()`, `selected()` (honouring `BRIDGES`), and `main()` printing the table for `poe bridges`. | reads the bridges; imported by `doctor.py`; run as CLI by `poe bridges` |
| `scripts/build_server.py` | **new** — the one place the server build command lives, now that the output name is computed from the host rather than literal. | imports `platforms`; imported by `redeploy.py`; run by `poe build-server` |
| `scripts/bridge_task.py` | **new** — the dispatcher. Runs one declared task for every selected bridge whose tier runs here, `SKIP`s the rest, and `--require`s a task to have run for `poe live`. | imports `bridges`, `platforms`; run by seven poe tasks |
| `scripts/doctor.py` | **changed** — split into core / server / bridge sections; `SKIP` status; binaries table gains a `hosts` field; `check_conformance_python` mirrors the Go probe; root-pyright check proves its extraPaths exist. | imports `platforms`, `bridges` |
| `scripts/redeploy.py` | **changed** — `running_copies()` and `kill_all()` gain a POSIX implementation; `build()` moves to `build_server.py`. | imports `platforms`, `build_server`, `doctor` |
| `bridges/nvda/tests/support/platforms.py` | **new** — `skip_module_unless_windows(reason)`. Test scaffolding, not a port double, so `support/` and not `fakes/` (AGENTS.md, "Testing"). | called by the two named-pipe test modules |
| `bridges/nvda/pyproject.toml` | **changed** — the `[tool.screen-readers-mcp.bridge]` declaration, including each tier's task commands; one more `per-file-ignores` entry. | read by `scripts/bridges.py` |
| `pyproject.toml` | **changed** — `build-server` calls its script; `bridges` task added; seven bridge tasks now call `bridge_task.py`; `build-addon` renamed `build-bridge`. | |
| `pyrightconfig.json` | **changed** — both venv layouts per execution environment, and the two Win32 leaves added to `ignore` (amendment made while implementing: see decision 7). | checked by `doctor.py` |
| `.github/workflows/ci.yml` | **changed** — the `portable` matrix job. | |

No new class is introduced in `server/` or in the add-on package.

## Adding Linux later — the structure test

A design that claims to be structured should be able to say what the next host
costs. Concretely, when Linux is supported:

1. `Host.LINUX` already exists in `scripts/platforms.py`; nothing to add.
2. `ubuntu-latest` joins one list in `ci.yml`.
3. The NVDA bridge's `headless` and `package` tiers already say `["*"]`; its
   `live` tier already says Windows. Nothing to edit.
4. `CONTRIBUTING.md` gains a Linux column in the prerequisites table.

That is the whole list, and it is the argument for doing this now rather than
per-host as each arrives.

## What is deliberately not built

- **A plugin or entry-point mechanism.** A bridge is a directory with a
  `pyproject.toml`; discovery is a glob, and a task is a command string.
  `bridge_task.py` knows how to select and how to report; it knows nothing about
  pytest.
- **Moving `check_shared_synced` into the bridge section.** The doctor still
  compares `shared/screenreader_wire/protocol.py` against `bridges/nvda`'s copy
  by name. It is bridge-specific and belongs with the bridge; it stays for now
  because the NVDA bridge cannot be deselected on any host today, so nothing is
  yet wrong. It is the first thing bridge #2 should move.
- **Migrating a stale `screenreader-mcp.exe`** left in a POSIX checkout by an
  earlier build. No symlink, no shim, no cleanup step.
- **Running the live tier anywhere but Windows.** Nothing here brings NVDA to
  another host, and `poe live` refusing is the whole of the change.
- **Making `scons`, `msgfmt` or `xgettext` required.** They stay warnings. The
  doctor's FAIL bar is "this makes every other result untrustworthy", and a
  missing packaging tool does not make a test lie.

## Honest limits

- **NOTHING HERE HAS BEEN RUN ON WINDOWS.** Every measurement in this spec was
  taken on macOS, and the Windows paths were edited blind: `redeploy.py`'s CIM
  filter now interpolates `BINARY.name` instead of a literal; the dispatcher
  splits each declared command with `shlex.split`, which is POSIX-quoting and
  would mangle a backslash a future declaration might contain (none does today);
  and the binary rename touches the doctor's staleness check. The `shared`,
  `server`, `conformance` and `nvda-bridge` CI jobs are what say whether that is
  true, and a Windows `poe dev` is the check a reviewer should insist on before
  this merges. It is a live-checklist item in the PR body for exactly that
  reason.
- **The macOS host is verified on x86_64 only.** Every measurement in Part 1 was
  taken on an Intel Mac. The `portable` CI job runs `macos-latest`, which is
  arm64, so the first run of that job is also the first evidence about Apple
  Silicon. If it fails, that is a finding for this entry, not a surprise.
- **Linux is planned for, not tested.** `Host.LINUX` exists and `go-linux`
  compiles the server for it, but no Linux run of `poe ci` has happened. The
  claim made here is "the structure has a slot", not "Linux works".
- **The POSIX kill path is matched by argv, not by inode.** `running_copies()`
  compares the process's argv[0] against the binary's path, which a process
  that rewrote its own argv could defeat. Windows matches on
  `ExecutablePath`, which is stronger. This is a dev tool killing dev servers,
  and the weaker match is accepted rather than papered over.
- **Listing both venv layouts in `pyrightconfig.json` hides a wrong path.** That
  is why the doctor now checks them; without that check this decision would be
  trading one silent failure for another.
- **The bridge declaration is not validated against reality.** Nothing proves
  that NVDA's `package` tier really works on macOS except that someone ran it.
  A tier that lies produces a doctor that lies.

## Open questions

- Should the `portable` job become a required status check? Deliberately not
  decided here: it must report once first, and that is a repo-settings edit
  made in a separate breath from this PR (`AGENTS.md`, the CI-job-names gotcha).
- Should a task be runnable for ONE named bridge without `BRIDGES=` in the
  environment — `poe bridge-types nvda`? Not built: with one bridge the variable
  is enough, and a per-task selector would be a second way to say the same thing.

## Not in scope

- Which language the VoiceOver bridge is written in
  ([spec 0041](0041-can-voiceover-say-what-it-said.md)); this spec only
  guarantees that whatever it is, it has a declaration slot and a doctor that
  reports it.
- Any change to the wire contract, the MCP surface, or the add-on's behaviour.
- Windows-side improvements. Every Windows path in this spec must behave
  exactly as it does today, and the `nvda-bridge` job is what proves it.
