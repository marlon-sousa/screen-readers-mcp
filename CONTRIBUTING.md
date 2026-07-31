# Contributing to nvda-mcp

This is the **onboarding** document: how to set up an environment that can build,
test, and drive every part of the system. Follow it once, and you are ready to
run the headless suites and — with a real NVDA — the live checklists that PRs
carry.

It deliberately does **not** list test scenarios. Those are decided per change
and live in the **pull request body** as a checklist (see "Opening a pull
request" below). This file gets you to the point where you can run them.

For anything scoped to one half of the system, its own document is the
authority and this file points at it rather than repeating it:

- **Architecture, the ports-and-adapters rules, hard invariants, testing
  conventions** — [`AGENTS.md`](AGENTS.md), the developer manual.
- **What is done, in review, and next** — [`ROADMAP.md`](ROADMAP.md), the status
  board. Every change is specced first (`specs/NNNN-*.md`) and agreed in
  conversation before code; the spec rides in the implementing PR.
- **Component-local notes** — [`server/README.md`](server/README.md) and
  [`bridges/nvda/`](bridges/nvda/).

## The three halves

The chain is an **MCP client** (Claude Code, or the driver script) → the
**server** (`screenreader-mcp`, a Go binary) → the **bridge** (`nvdaMcpBridge`,
an NVDA add-on) → **NVDA**. The server and the bridge share no code; they meet
only at a local endpoint speaking the wire contract in
[`specs/wire/v1/`](specs/wire/v1/). See [`README.md`](README.md) for the fuller
picture.

## Prerequisites

| Requirement | Version | Why |
|---|---|---|
| **Windows** | 10/11 | The add-on and any live test need it. The server and the shared wire binding are cross-platform, but the full system is driven on Windows. |
| **Go** | 1.25+ (matches `server/go.mod`) | Builds the server. Static binary — `CGO_ENABLED=0`, no C toolchain needed. |
| **[uv](https://docs.astral.sh/uv/)** | current | Runs and isolates every Python part (shared wire, bridge tests, schema generation). |
| **Python** | 3.13 (`py -3.13`) | Matches NVDA's embedded interpreter. Prefer `uv run` or `py -3.13` over a bare `python`, whose meaning varies per machine — `uv run poe doctor` reports what yours actually resolves to. |
| **NVDA (installed)** | **2026.1.0** or later | The minimum supported version (`bridges/nvda/buildVars.py`, `addon_minimumNVDAVersion`). A live test needs a running copy. |
| **NVDA source checkout** | the version you target (≥ 2026.1.0) | A **reference for reading real NVDA APIs**, checked out as a sibling of this repo at [`../nvda`](../nvda). There is no NVDA source *dependency* in the build or the headless tests — the NVDA edge is exempt from the type check — but developing or reviewing an adapter means verifying API contracts against real code (see the `nvda-headless-testing` approach in `AGENTS.md`). |
| **scons + add-on build deps** | per `bridges/nvda/` | Builds the `.nvda-addon`. |

Clone the NVDA source beside this repo so `../nvda/source` resolves:

```sh
# from the parent of this repo
git clone --branch release-2026.1 https://github.com/nvaccess/nvda.git nvda
```

## Running the headless suites

These need no NVDA. **From the repo root** — every task names its own
subproject, so the directory you run from is always the same one:

```sh
uv run poe doctor    # is this machine able to work the repo? run this first
uv run poe dev       # the doctor, then everything CI runs (~1 min)
uv run poe bridge    # just the bridge suite, for a fast inner loop (~5s)
uv run poe           # list every task
```

`poe dev` is what to run before opening a PR. Every task first runs a fast
environment check and **refuses to run if it fails** — a broken toolchain makes
passing and failing tests equally uninformative, so it is better to stop than to
hand you a result you cannot trust. `uv run poe fix` repairs the common causes.

CI runs the same tasks, one per job (`poe ci-shared`, `ci-server`, `ci-bridge`,
`ci-conformance`); `poe ci` is all four. The only difference from `dev` is that
CI skips the questions about your machine — a fresh runner cannot have drifted,
and its toolchain is declared in the workflow. So **if you want to change what
CI checks, change `pyproject.toml`**, not `.github/workflows/ci.yml`: that way
you can prove it locally instead of discovering it after a push.

Live-NVDA tests are **excluded by default** and are not part of `ci`. They drive
the real NVDA on your machine — pressing gestures, opening dialogs, typing into
whatever has focus, changing reader settings. Run them only deliberately, and
only when you are ready for your screen reader to be taken over:

```sh
uv run poe live
```

<details>
<summary>The underlying commands, if you need one directly</summary>

```sh
# Shared wire contract
uv run --directory shared pytest
uv run --directory shared pyright

# Server (Go; tests use a fake bridge)
go -C server test ./...
go -C server vet ./...

# Bridge add-on: sync the shared wire module in, then headless tests + type check
py -3.13 bridges/nvda/sync_shared.py
uv run --directory bridges/nvda pytest
uv run --directory bridges/nvda pyright
```
</details>

One tier is Windows-only and opts in explicitly — the cross-language
**conformance** run, the built server binary against the *real* Python bridge
over a real pipe and real loopback TCP:

```sh
go -C server test -tags conformance -count=1 ./tests/conformance/
```

It **fails rather than skips** if it cannot reach the real bridge — that is the
whole point of the tier. It still fakes NVDA at the bridge's own factory port,
because what it proves is the wire, not NVDA.

## Setting up to test against a live NVDA

The headless and conformance tiers fake NVDA. The one thing they cannot do is
prove the whole stack with a **real NVDA and a human who can hear the speech** —
which is how every live-NVDA checklist in a PR is run. Get the environment ready
once:

### 1. Build the server binary

```sh
uv run poe build-server
```

No arguments are ever needed to reach a local NVDA: the binary ships knowing the
default endpoints (`--print-default-config` shows them).

### 2. Build and install the add-on

```sh
py -3.13 bridges/nvda/sync_shared.py     # copy the shared wire module in
uv run poe build-addon                   # produces nvdaMcpBridge-<version>.nvda-addon
```

Open the built `.nvda-addon` with NVDA and restart when prompted. Reinstalling a
newer build is always just "install, restart NVDA".

**Enable auto-start** so the bridge is listening the moment NVDA comes back:
NVDA menu (`NVDA+n`) → **Tools** → **NVDA MCP &Bridge…**, tick **auto-start**,
then **Start**. With it on, every NVDA restart — including the one after a
reinstall — brings the bridge back up on its own. The connection mode (named
pipe by default, or loopback TCP) is chosen in that same dialog; the server
tries both, so you need not tell it which.

### 3. Confirm the bridge is listening

It listens on a named pipe called `nvdaMcpBridge`:

```sh
py -3.13 -c "import glob; print([p for p in glob.glob(r'\\\\.\\pipe\\*') if 'McpBridge' in p])"
```

An empty list means it is not started — revisit step 2.

### 4. The driver

[`scripts/live_test.py`](scripts/live_test.py) stands in for the MCP client. You
do not assemble commands or reason about indices — each **named scenario** is
self-contained: it connects, walks its steps, checks what it can on its own (tool
gating, index arithmetic, error shapes), tells you when to focus a window, asks
you to confirm what you heard, and prints `PASS` / `FAIL` / `EAR` (needs your
ear) per check with a summary. Run it in a terminal for the guided experience;
run it with no scenario to list them all.

A quick connectivity check, which also proves `announce` is audible, is:

```sh
py -3.13 scripts/live_test.py ./server/screenreader-mcp.exe smoke
```

If you hear the announcement, the whole chain is wired up. Which scenarios to run
for a given change — and what each should show — is in that change's PR.

### Driving it as Claude Code itself (the most faithful client)

The driver stands in for an MCP client; the **real** client is an agent. To have
Claude Code drive NVDA directly, register the built binary as a project MCP
server by creating a **`.mcp.json`** at the repo root:

```json
{
  "mcpServers": {
    "screen-reader-testing": {
      "command": "./server/screenreader-mcp.exe",
      "args": []
    }
  }
}
```

The command is **relative**, so it resolves to whatever binary you built in your
own checkout — no per-machine path to edit. This file is **git-ignored on
purpose**: it is yours, not the repo's, so it never clobbers a `.mcp.json` you
already keep. If you already have one, **add the `screen-reader-testing` entry to
your existing `mcpServers`** rather than replacing the file.

Two things must be true before the tools appear:

- You have **built the server binary** (step 1 above); the relative command only
  resolves if `./server/screenreader-mcp.exe` exists in your checkout.
- Claude Code loads project MCP servers at **startup** and asks you to **approve**
  them, so **restart it**, then approve `screen-reader-testing` when prompted —
  only then do the `mcp__screen-reader-testing__*` tools appear.

From that session, ask the agent to list readers, connect, and drive NVDA; the
tools are the same ones the driver calls, so a PR's checklist reads the same
either way.

## Opening a pull request

- Branch off `main`. One component plus its ports and tests per PR; nothing lands
  untested. See the workflow section of [`AGENTS.md`](AGENTS.md).
- A live-NVDA checklist goes in the **PR body as checkboxes**, one item per
  check. Record findings inline on the item (NVDA version, expected vs observed);
  findings that need a change become iteration entries in `ROADMAP.md`. A CI job
  keeps a PR from merging while any checkbox is unticked.
- All prose stays screen-reader friendly: no ASCII-art diagrams. Use Mermaid
  where it renders (not in the add-on's own `README.tpl.md`/`doc/`). The full
  rule, including the required `accTitle`/`accDescr`, is in `AGENTS.md`.

## License

By contributing you agree your contributions are licensed under **GPL v2**, the
project's license. See [`LICENSE`](LICENSE) / `COPYING.txt`.
