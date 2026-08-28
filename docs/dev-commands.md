# Dev commands — why they are the way they are

The commands themselves are in [`AGENTS.md`](../AGENTS.md) under "Dev commands":
run the doctor, then `uv run poe dev`. This file is the reasoning behind them —
what each gate exists to catch, what it cost to learn, and the reference list of
the underlying commands `poe` wraps.

Read it when a gate surprises you, when you are changing what CI checks, or
when you are tempted to remove a check that looks like ceremony. None of it is
needed to *run* the tasks.

## Why the doctor exists

It is not ceremony. Every check in it corresponds to something that has already
cost someone hours, because the symptom pointed nowhere near the cause:

| Symptom | Real cause |
|---|---|
| ~140 phantom `Import "pytest" could not be resolved` from pyright | pyright had no venv configured, so it analysed against the wrong interpreter |
| `uv trampoline failed to canonicalize script path` | a stale console-script shim; names neither the tool nor the fix |
| A search returns thousands of `site-packages/...` lines | no ripgrep, so it fell back to `grep -r`, which ignores `.gitignore` |
| The bridge behaves like an older wire contract | `addon/…/protocol.py` is a **copy**; `sync_shared.py` had not been re-run |
| `scons` fails late in the addon build | `msgfmt`/`markdown` missing |

A red doctor makes green tests and red tests equally uninformative. Fix it
first.

## CI calls one task per job

**`.github/workflows/ci.yml` no longer spells out any commands.** Each job
installs a toolchain and calls one task — `uv run poe ci-shared`, `ci-server`,
`ci-bridge`, `ci-conformance`, one per job, named after it. So **a change to
what CI checks is a change to `pyproject.toml`**, which you can run and prove
before pushing; the workflow changes only when a job needs a different
toolchain. Keep the job↔task pairing 1:1.

That unification is not cosmetic. While the two lists were maintained by hand
they drifted, in both directions: `poe ci` grew a `lint` task the workflow never
ran, the workflow's ruff step covered `addon tests` while poe covered two more
files, and **staticcheck and the Linux build existed only in the workflow** — so
no developer could run them, and the first sign of a failure was a red PR.
`staticcheck` is also now pinned; at `@latest` an upstream release turns the
repo red with no commit of ours behind it, and the bisect begins by hunting for
a change that does not exist.

## The server is everywhere; a bridge is somewhere

**Every server task runs on every host, with no guard and no skip** — build,
vet, unit and integration tests, gofmt, staticcheck, the wire-binding gate, the
Linux cross-build and the conformance tier. That is a requirement rather than an
observation: a host where the server does not build is a host this project does
not support. The server's one host-shaped part, the named-pipe transport, is
handled by Go's own build tags and needs nothing from `poe`.

**A bridge is different, because a bridge follows its reader.** NVDA and JAWS are
Windows, VoiceOver is macOS, TalkBack is Android behind a host SDK. So each
bridge declares its own requirements, in its own `pyproject.toml`, split by
tier:

| Tier | The question it answers |
|---|---|
| `headless` | can I run its tests here? |
| `package` | can I build its shippable artifact here? |
| `live` | can I drive the real reader here? |

For the NVDA bridge the answers are: anywhere, anywhere, and Windows only. Its
domain is stdlib-only Python with NVDA behind ports, and scons is pure Python, so
only the last one is actually Windows-bound.

```sh
uv run poe bridges          # every bridge, every tier, RUNS or SKIP with its reason
BRIDGES=nvda uv run poe doctor   # narrow to one bridge deliberately
```

**And each tier declares its own commands**, so `poe bridge`, `bridge-types`,
`bridge-lint`, `sync`, `build-bridge`, `live` and `live-slow` are one dispatcher
(`scripts/bridge_task.py`) running what the selected bridges declare. They used
to name `bridges/nvda` in their own command strings, which meant `poe
bridge-types` type-checked the NVDA bridge on a machine where nobody was working
it. The commands have to live with the bridge anyway, because a bridge is not
necessarily a uv project: NVDA's tests are pytest under uv, and a VoiceOver
bridge in Go or Swift will be neither.

With `BRIDGES` unset, a bridge is selected when it can do **any** of its work
here — which is what makes a fresh macOS checkout pick up a macOS bridge with
nothing configured, and a typo in `BRIDGES` an error rather than a silent
selection of nothing.

Two consequences you will see:

- **The doctor prints `SKIP`.** A check that does not apply here says so, with
  its reason (`not applicable on macos`, `NVDA itself runs only on Windows`),
  because the first question anyone has on a new host is "what is *not* being
  checked?" — and silence cannot answer it. A skip never affects the exit code.
- **`poe live` refuses** on a host where no selected bridge declares a live
  tier, instead of running pytest, matching no tests and printing a green
  "0 selected" that reads exactly like a pass. It is the only bridge task that
  refuses: for `test`, `types` and `lint`, having nothing to do because you are
  not working that bridge here is a success, and reporting it as a failure would
  turn `poe types` red on a perfectly good checkout.

The reasoning, the evidence and what adding Linux would cost are in
[spec 0042](../specs/0042-the-server-is-everywhere-a-bridge-is-somewhere.md).

## Rebuild the server binary after touching `server/`

**Rebuild the server binary after touching `server/`.** `.mcp.json` spawns
`server/screenreader-mcp` (`.exe` on Windows), so an agent that edits Go code and then drives
the MCP tools is testing the OLD server against the NEW bridge. The symptom is
a field simply missing from a result, which reads as "the bridge did not send
it" rather than "your binary predates it" -- that is exactly how `bridgeVersion`
went unnoticed through an entire live checklist. `poe doctor` fails when the
binary is older than any `server/*.go`, and **a rebuild alone is not enough**:
the MCP client spawned the old process at startup, so the connection has to be
restarted too.

**`poe dev` repairs this rather than reporting it.** Its first step is
`redeploy --if-stale`, a no-op when the binary is current and a full
kill-delete-rebuild when it is not. The staleness question is answerable by
comparing two mtimes, so asking it at the *end* of a minute-long doctor run —
and thereby costing two full runs per Go change — was pure waste. One definition
of "stale" serves both: `doctor.stale_server_binary()`, which `redeploy.py`
imports rather than restating, so dev and the doctor cannot drift into
disagreeing about the same tree.

## `poe live` is quarantined for safety, not speed

**`poe live` is quarantined for safety, not speed.** The live-NVDA tests press
gestures, open the Run dialog, type into whatever currently has focus, and
change the reader's configuration -- on the machine you are sitting at. They
were previously harmless only by accident: they skip when nothing is listening
on the pipe, so nobody noticed until a developer ran the suite with their own
NVDA and bridge up and had their screen reader commandeered mid-task. For a
blind developer that is not a nuisance, it is losing control of the machine.
They are now marked `live_nvda` and excluded by `addopts`; running them is an
explicit act. Never add them to `ci`.

`poe dev` is the one to run before saying something works: the full doctor, then
exactly what CI runs.

## What `dev` assumes that `ci` does not

**`dev` and `ci` differ only in what they assume about the machine.** `dev` asks
first whether *this workstation* is fit to work the repo — Go and ripgrep
present, venvs intact, the MCP server binary not stale — because a desktop
drifts, and the failures that follow name everything except their cause. A
runner is rebuilt from `ci.yml` every time and cannot have drifted, so `ci`
skips those questions and does the work. Under `CI` (set by GitHub Actions, and
by anything else worth the name) the doctor drops the machine checks by itself;
export `CI=1` locally to rehearse a runner. This is what kept `poe` out of the
workflow for so long: the `shared` job installs uv and nothing else, so the
*required* `go` and `rg` aborted it before a single test ran.

The checks that survive under `CI` are the ones about the *checkout* rather than
the machine: pyright's venv configuration, and the addon's copy of the wire
module matching `shared/`.

## Every task is gated on `check`

Every task except `doctor`, `fix`, `check` and the remediations is gated on
`check` (the fast doctor subset, ~1s, silent when it passes). The diagnostics
are exempt on purpose: gating the tool that reports a broken environment on that
same environment would make the breakage unreportable. The remediations —
`build-server`, `redeploy`, `sync` — are exempt by the same rule, since each one
*repairs* a condition the doctor fails on, and gating it would deadlock.

## Tool minimums are floors, never pins

**Tool minimums are floors, never pins.** The doctor fails a tool that is *below*
the version this repo needs and is silent about anything newer, so upgrading is
always safe and nothing here ever has to be revisited because a tool moved
forward. Each minimum exists for a stated reason -- `gh` below 2.55 cannot edit
a PR body, `go` tracks `server/go.mod` -- and gettext is presence-only, because
its Windows builds report versions that do not order against the GNU ones and a
comparison that gives wrong answers is worse than none.

## The `VIRTUAL_ENV` warning is expected noise

**The `VIRTUAL_ENV ... does not match the project environment path` warning is
expected noise, once per task.** It is nested `uv run`: `uv run poe <task>`
activates the ROOT env by exporting `VIRTUAL_ENV` into poe, and every suite task
is a second `uv run --directory <subproject>` whose own env is
`<subproject>/.venv`. The inner uv reports that it is ignoring the inherited
variable and then resolves the subproject's env correctly — verified: `sys.prefix`
inside `poe bridge` is `bridges/nvda/.venv`. Two things follow. **Do not pass
`--active`**, which the warning itself suggests: that forces the root env, which
has neither pytest nor pyright for the subprojects, and is the one way to turn
this cosmetic message into a real failure. And do not try to silence it from
`pyproject.toml` — `[tool.poe.env]` cannot clear `VIRTUAL_ENV` (a plain variable
set there does land; that one does not), and `executor.type = "simple"` does not
either, because the value is inherited rather than set by poe. Silencing it means
either dropping `uv run` in front of `poe` (which reintroduces the Windows
console-script trampoline the doctor's symptom table above warns about) or turning every `cmd`
task into a `shell` task. Both cost more than the warning does.

## Lint is a real gate, and it lints directories

**`poe lint` is now a real gate, and the format check is half of it.** The
backlog that once justified leaving ruff out is cleared: every Python file in
the repo — 179 of them, across `shared/`, `bridges/nvda/` and `scripts/` — is
clean and formatted, and `ci` fails on a new violation. Specs that list "ruff
green" in their definition of done now describe something that actually runs.

Two things that gate had to fix, worth knowing because both were invisible:

- **`ruff check` says nothing about indentation.** Only `ruff format --check`
  does, and nothing ran it, so a file could arrive space-indented in a tab repo
  and pass every gate — which is exactly how PR #46 added a dozen of them.
- **`scripts/` was linted by nothing.** `shared/` and `bridges/nvda/` each carry
  their own ruff config, and everything between them — the dev scripts,
  `sync_shared.py`, `buildVars.py` — fell through the gap. The root
  `pyproject.toml` now covers it with the same rule set.
- **Go formatting was checked by nothing either.** Neither `go vet` nor
  staticcheck has an opinion about layout, so the Go half had the same hole the
  Python half just closed — and it was holding two files, a struct field and a
  map entry added without realigning the block around them. `poe go-fmt` runs in
  `ci-server` now. It is a script rather than one command because `gofmt -l`
  prints the offenders and then **exits 0**, so the obvious one-liner is a gate
  that can never fail.

**Every gate lints a DIRECTORY, never a list of files — deny-list, not
allow-list.** Both holes above were allow-list holes: a gate that named paths,
so a file at a path nobody had thought of was ungated and looked fine. Naming
paths only covers files that already exist, which is the wrong set; the risk is
the file that does not exist yet — the one a contributor or a model is about to
add. Verified by planting space-indented files in nine locations, two of them in
directories that did not previously exist: with file lists, three slipped
through silently; with `.`, none do.

So if something must not be linted, **exclude it, and say why at the exclusion**
— adding a path to an exclude list should feel like a decision, where adding one
to an allow-list feels like nothing at all. Two things are excluded today, both
vendored from the NVDA AddonTemplate scaffold, because reformatting upstream's
code only makes the next scaffold sync noisy: `bridges/nvda/site_scons/` and
`bridges/nvda/sconstruct`.

The rule set is **chosen, not inherited**: `select` is listed explicitly in all
three configs, because ruff's defaults have widened across releases and a
project with no `select` enforces whatever version happens to be installed.
Changing what this repo enforces should be a deliberate edit, not a version
bump.

## The underlying commands

`poe` is a thin wrapper; these are what it runs, if you need one directly:

```sh
# shared wire contract (no NVDA needed)
uv run --directory shared pytest
uv run --directory shared pyright

# MCP server (no NVDA needed; tests use a fake bridge). Go, not Python.
go -C server build ./...
go -C server test ./...                       # unit tests
go -C server test -tags integration ./...     # whole server, real transports
go -C server vet ./...
go -C server generate ./adapters/wire         # regenerate the binding from the schema

# Cross-language conformance: the built binary against the REAL Python bridge,
# over real loopback TCP -- and, on Windows only, a real named pipe as well (that
# scenario is //go:build conformance && windows, since both transports' leaves
# are). Needs a Python 3.13 on PATH, or CONFORMANCE_PYTHON set to one; `poe` puts
# the workspace venv's 3.13 on PATH, so usually neither is anything you do. It
# FAILS rather than skips if it cannot reach the real bridge -- that is the whole
# point of the tier.
go -C server test -tags conformance -count=1 ./tests/conformance/

# NVDA addon: copy the shared module in, then run headless tests + pyright.
# No NVDA checkout needed — the domain is pure; the NVDA edge is in pyright's
# ignore list (no stubs, no source dependency).
py -3.13 bridges/nvda/sync_shared.py
uv run --directory bridges/nvda pytest       # headless domain tests
uv run --directory bridges/nvda pyright
# builds: prefer `uv run poe build-server` / `build-bridge` (same commands, one entry point)
cd bridges/nvda && scons        # build the .nvda-addon (needs the NVDA build deps)
```
