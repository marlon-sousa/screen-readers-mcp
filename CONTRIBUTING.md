# Contributing to screen-readers-mcp

This is the **onboarding** document: how to set up an environment that can build,
test, and drive every part of the system. Follow it once, and you are ready to
run the headless suites and — with a real NVDA — the live checklists that pull
requests carry.

It deliberately does **not** list test scenarios. Those are decided per change
and live in the **pull request body** as a checklist (see "Opening a pull
request" below). This file gets you to the point where you can run them.

For anything scoped to one part of the system, its own document is the authority
and this file points at it rather than repeating it:

- **Architecture, the ports-and-adapters rules, hard invariants, testing
  conventions** — [`AGENTS.md`](AGENTS.md), the developer manual. Detail belonging
  to one project lives beside it, in [`shared/AGENTS.md`](shared/AGENTS.md),
  [`server/AGENTS.md`](server/AGENTS.md) and
  [`bridges/nvda/AGENTS.md`](bridges/nvda/AGENTS.md); the reasoning behind the
  task list is in [`docs/dev-commands.md`](docs/dev-commands.md).
- **What is done, in review, and next** — [`ROADMAP.md`](ROADMAP.md), the status
  board.
- **What the thing is and what its tools do** — [`README.md`](README.md).

## This project is developed with an agent

Development here is **agentic-first**. The system is built and reviewed largely
by an AI agent working in this repository, and the setup below assumes that.
This is not a curiosity: a project whose purpose is letting an agent drive a
screen reader is a reasonable place to let an agent do the driving.

That has one concrete consequence for your machine — **a checkout of NVDA's own
source is required**, described in the next section. An agent cannot rely on
recalled API knowledge for a codebase that moves every release; it reads the
real source to confirm what a function actually does before writing an adapter
against it, and so should you.

None of which stops you working by hand. Every command in this file is one you
can type yourself, and nothing in the build, the tests, or the type check
requires an agent. If you prefer to write the code, write the code — just keep
the NVDA source where the tooling and the next reviewer expect to find it.

## Prerequisites

The list splits in two, and the split is the point: **the server is developed and
tested on every host, unconditionally** — a machine where it does not build is a
machine this project does not support. A **bridge** works where its reader does,
and each bridge declares that for itself. See
[spec 0042](specs/0042-the-server-is-everywhere-a-bridge-is-somewhere.md).

Run `uv run poe bridges` at any time to see what your machine can actually do.

### Every host — Windows, macOS, Linux

| Requirement | Version | Why |
|---|---|---|
| **Go** | **1.25.x** (matches `server/go.mod`) | Builds the server. Static binary — `CGO_ENABLED=0`, no C toolchain needed. **Pin 1.25, do not take "or newer":** the pinned `staticcheck@2025.1.1` cannot read Go 1.27's export data and `poe go-staticcheck` fails with `internal error in importing ... export data version 4`. CI pins 1.25 too. |
| **[uv](https://docs.astral.sh/uv/)** | current (0.5+) | Runs and isolates every Python part (shared wire, bridge tests, schema generation). On macOS use the [standalone installer](https://docs.astral.sh/uv/getting-started/) rather than Homebrew, whose `uv` formula has no bottle for every macOS and will build llvm and rust from source. |
| **Python** | 3.13 | Matches NVDA's embedded interpreter. `uv python install 3.13` is enough; you do not need it on `PATH`, because `uv run` provisions it. Prefer `uv run` over a bare `python`, whose meaning varies per machine — `uv run poe doctor` reports what yours resolves to. |
| **ripgrep** | 13+ | Searches honour `.gitignore`; `grep -r` does not, and `.venv` is enormous. |
| **git** | 2.30+ | Version control. |
| **[GitHub CLI](https://cli.github.com/)** | 2.55+ | Optional. PR and issue work; below 2.55 `gh pr edit` fails on the Projects-classic deprecation. |

### Per bridge

A bridge's requirements are declared in its own `pyproject.toml`, under
`[tool.screen-readers-mcp.bridge]`, so these tables follow from those files
rather than duplicating them. Today there are two bridges, and **you only need
the row for the one you are working on** — `uv run poe bridges` says which of
them your machine can do anything with.

| For the **NVDA** bridge | Version | Needed for |
|---|---|---|
| **scons + python-markdown** | scons 4+ | Building the `.nvda-addon`. `uv tool install scons --with markdown` installs both into one interpreter. Works on any host. |
| **gettext** (`msgfmt`, `xgettext`) | any | Same — scons compiles the add-on's translations with it. `brew install gettext` on macOS. |
| **Windows** | 10/11 | **Only** for the `live` tier: installing the add-on and driving a real NVDA. Its headless tests and its `.nvda-addon` build run on macOS and Linux too. |
| **NVDA (installed)** | **2026.1.0** or later | The minimum supported version (`bridges/nvda/buildVars.py`, `addon_minimumNVDAVersion`). A live test needs a running copy. |
| **NVDA source checkout** | tag `release-2026.1` | The reference for reading real NVDA APIs. See below. |
| **PowerShell 7** (`pwsh`) | 7+ | Optional, Windows only. Windows PowerShell 5.1 has no `&&`/`||` and reports failure on exit code 0. |

| For the **VoiceOver** bridge | Version | Needed for |
|---|---|---|
| **macOS** | 14+ (measured on 15.0) | Every tier. VoiceOver is macOS, and the bridge is Swift against macOS frameworks — there is no tier that could run elsewhere even in principle. |
| **Swift toolchain** (`swift`) | **6.0+** | Its headless tests and its build. 6.0 is where swift-testing ships with the toolchain and where `swiftLanguageModes` exists in a package manifest, so an older one fails while *parsing* `Package.swift` rather than at a line you could read. It comes with Xcode 16 (`xcode-select -p` should name an Xcode, not just the command line tools). |
| **`codesign`** | any | Building the bundle. It ships with the OS; the doctor checks only that it is there, because `codesign --version` is an unrecognised option. |
| **VoiceOver (running)** | the one in your macOS | **Only** for the `live` tier. Its headless tests need no reader, no audio device and no registration. |

**The Swift package fetches nothing.** `Package.swift` has no external
dependencies, so `swift test` works offline and adds no third-party code to a
component that is dlopened into the user's screen reader — the same argument
that keeps the shared wire module stdlib-only, reached from the other direction.

### Setting up on macOS

Verified on macOS 15, x86_64, with Homebrew at `/usr/local`:

```sh
brew install go@1.25 ripgrep gh gettext
echo 'export PATH="/usr/local/opt/go@1.25/bin:$PATH"' >> ~/.bash_profile
curl -LsSf https://astral.sh/uv/install.sh | sh          # NOT brew install uv
uv python install 3.13
uv tool install scons --with markdown                    # only to build the .nvda-addon
uv run poe fix && uv run poe doctor
```

For the **VoiceOver** bridge, add Xcode 16 or later from the App Store and point
the toolchain at it — nothing else, and nothing from Homebrew:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
swift --version                                          # must report 6.0 or later
```

A healthy macOS doctor reports **0 warnings and 2 skips** — `pwsh`, and the NVDA
bridge's `live` tier — each naming its own reason. `poe live` refuses here rather
than running pytest and matching nothing.

## The NVDA source checkout

Clone NVDA **beside this repo**, in a directory named exactly `nvda`, so that
`../nvda/source` resolves from the repo root:

```sh
# from the PARENT of this repo
git clone https://github.com/nvaccess/nvda.git nvda
git -C nvda checkout release-2026.1
```

The tag matters. `release-2026.1` is the version this project targets; reading a
`master` that has moved on tells you about APIs your users do not have yet.

The layout matters too, because it is the path everything assumes:

```
C:\projects\
  screen-readers-mcp\    <- this repo
  nvda\                  <- NVDA source, at release-2026.1
```

What this checkout is **not** is a dependency. The build does not read it, the
headless tests do not import it, and the NVDA edge of the bridge is exempt from
the type check precisely so that it need not. It is documentation with the
authority of being the actual code — you consult it, the agent consults it, and
neither of you guesses at a signature that changed two releases ago. The
`nvda-headless-testing` approach in [`AGENTS.md`](AGENTS.md) describes how to
exercise add-on logic against it without launching NVDA at all.

## Repository layout

| Path | What |
|---|---|
| [`shared/`](shared/) | The **stdlib-only** Python binding of the wire protocol (`screenreader-wire`), copied verbatim into the add-on and unit-tested once. |
| [`specs/wire/v1/`](specs/wire/v1/) | The published wire contract: JSON Schema plus prose. What the two halves actually share. |
| [`server/`](server/) | The MCP server (`screenreader-mcp`), in Go: MCP tool call → bridge command → result. |
| [`bridges/nvda/`](bridges/nvda/) | The NVDA add-on (`nvdaMcpBridge`), built with scons. Its build copies `shared/`'s protocol module in, so bridge and server can never drift. |
| [`specs/`](specs/) | Numbered design specs, RFC-style. |
| [`scripts/`](scripts/) | Developer tooling, including the live-NVDA driver and the [live-test pages](scripts/live_pages/) its checklists drive. |

The server and the bridge **share no code**. They meet only at a local endpoint
speaking the contract in [`specs/wire/v1/`](specs/wire/v1/), and each side binds
it in its own language. What must match between them is the **wire protocol
version**, never their own version numbers: `hello` compares `PROTOCOL_VERSION`
and rejects a mismatch with a clear error, so each half releases on its own
cadence.

Inside the server, the same four roles as the bridge (the rules are in
[`AGENTS.md`](AGENTS.md), and the Go half's own in
[`server/AGENTS.md`](server/AGENTS.md)):

```
server/
  domain/         # PURE core: no wire types, no MCP SDK, no sockets
    ports/        #   one interface per file
    entities/     #   the pure model, including the capability gate
    controllers/  #   the connection lifecycle, and one controller per tool
  adapters/       # the only place the OS, the SDK and the wire binding live
    wire/         #   GENERATED from specs/wire/v1/schema.json; do not edit
    mcp/          #   the go-sdk stdio server, tool binding, the resources
    bridge/       #   the JSON-lines client, the handshake, the transport leaves
    discovery/    #   the pipe scan
    ports/        #   seams BETWEEN adapters (the domain never sees these)
  version/        # the single version source the server-v* tag is checked against
  config/         # the embedded defaults and their layered loader
  wiring/         # the composition root: read it top to bottom
  cmd/            # the entry point
  tools/wiregen/  # the wire binding generator (a dev tool, not shipped)
  fakes/          # one hand-written fake per port
  testsupport/    # builders and the fake bridge
  tests/          # architecture gate; integration and conformance behind tags
```

## How work happens here

Every change is **specced first** — a numbered document in [`specs/`](specs/),
agreed in conversation before any code — and the spec rides in the pull request
that implements it. New features add a new spec alongside the existing ones
rather than editing history.

[`ROADMAP.md`](ROADMAP.md) is the status board and the single source of truth for
what is done, in review, and next. Each implementing pull request keeps it
current.

## Running the headless suites

These need no NVDA. **From the repo root** — every task names its own
subproject, so the directory you run from is always the same one:

```sh
uv run poe doctor    # is this machine able to work the repo? run this first
uv run poe dev       # the doctor, then everything CI runs (~1 min)
uv run poe bridge    # just the bridge suite, for a fast inner loop (~5s)
uv run poe           # list every task
```

`poe dev` is what to run before opening a pull request. Every task first runs a
fast environment check and **refuses to run if it fails** — a broken toolchain
makes passing and failing tests equally uninformative, so it is better to stop
than to hand you a result you cannot trust. `uv run poe fix` repairs the common
causes.

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
go -C server test -tags integration ./...    # real transports, fake bridge
go -C server generate ./adapters/wire        # regenerate the wire binding

# Bridge add-on: sync the shared wire module in, then headless tests + type check
uv run poe sync
uv run --directory bridges/nvda pytest
uv run --directory bridges/nvda pyright
```
</details>

## The conformance tier

One tier is Windows-only and opts in explicitly — the cross-language
**conformance** run: the built server binary against the *real* Python bridge,
over a real named pipe and real loopback TCP.

```sh
go -C server test -tags conformance -count=1 ./tests/conformance/
```

It **fails rather than skips** if it cannot reach the real bridge — that is the
whole point of the tier. It still fakes NVDA at the bridge's own factory port,
because what it proves is the wire, not NVDA.

It is the only tier where nothing below MCP is faked, and that is why it exists.
Every other test drives a Go fake bridge that encodes frames with the same
generated binding the server decodes them with, so a bug in the binding itself
would have both sides wrong together, in agreement. The conformance run puts the
real Python bridge on the other end instead — which is also why nothing in that
package is allowed to mention the fake bridge (`tests/architecture` enforces it).
It replaced the same-bytes guarantee the two halves had while both were Python.

The wire binding itself is generated and committed, and CI regenerates and diffs
it, so it can never drift from the published contract.

## Setting up to test against a live NVDA

*(The macOS equivalent, for VoiceOver, is the section after this one.)*

The headless and conformance tiers fake NVDA. The one thing they cannot do is
prove the whole stack with a **real NVDA and a human who can hear the speech** —
which is how every live-NVDA checklist in a pull request is run. Get the
environment ready once:

**If your checklist needs a page to drive, it belongs in the repo.**
[`scripts/live_pages/`](scripts/live_pages/) holds the fixtures the existing
checklists use — a structural page, a growing page, and a generator for a long
one — each with a comment saying which check it serves. Add yours there in the
same PR as the checklist rather than building one in a temp directory: a
measurement quoted against a page nobody else has is not reproducible evidence.
The rule, and what it cost to learn, is in [`AGENTS.md`](AGENTS.md).

### 1. Build the server binary

```sh
uv run poe build-server
```

No arguments are ever needed to reach a local NVDA: the binary ships knowing the
default endpoints (`--print-default-config` shows them).

### 2. Build and install the add-on

```sh
uv run poe build-bridge   # syncs the shared wire module in, then packages
```

Open the built `nvdaMcpBridge-<version>.nvda-addon` with NVDA and restart when
prompted. Reinstalling a newer build is always just "install, restart NVDA".

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
py -3.13 scripts/live_test.py ./server/screenreader-mcp.exe smoke   # Windows; NVDA is the only live reader today
```

If you hear the announcement, the whole chain is wired up. Which scenarios to run
for a given change — and what each should show — is in that change's pull
request.

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

On macOS or Linux the command is `"./server/screenreader-mcp"` — the binary
carries the host's own convention for naming an executable, and nothing more
(spec 0042).

The command is **relative**, so it resolves to whatever binary you built in your
own checkout — no per-machine path to edit. This file is **git-ignored on
purpose**: it is yours, not the repo's, so it never clobbers a `.mcp.json` you
already keep. If you already have one, **add the `screen-reader-testing` entry to
your existing `mcpServers`** rather than replacing the file.

Two things must be true before the tools appear:

- You have **built the server binary** (step 1 above); the relative command only
  resolves if `./server/screenreader-mcp.exe` exists in your checkout (on macOS
  or Linux, `./server/screenreader-mcp` — the binary carries the host's own
  executable convention, spec 0042).
- Claude Code loads project MCP servers at **startup** and asks you to **approve**
  them, so **restart it**, then approve `screen-reader-testing` when prompted —
  only then do the `mcp__screen-reader-testing__*` tools appear.

From that session, ask the agent to list readers, connect, and drive NVDA; the
tools are the same ones the driver calls, so a pull request's checklist reads the
same either way.

## Setting up to test against a live VoiceOver

The macOS equivalent of the section above, and the shape is the same — build,
install, confirm it is listening, then drive it — but three of the four steps are
genuinely different, because a screen reader that ships with the operating system
is installed differently from one you download.

**Everything here needs macOS.** The server is built and tested on every host;
a bridge works where its reader does (`uv run poe bridges` says which tiers run
on this machine, and why not, if not).

### 1. Build the server binary

```sh
uv run poe build-server
```

No arguments are ever needed to reach a local VoiceOver bridge: since board entry
13.11 the binary ships knowing `local:voiceoverMcpBridge`
(`--print-default-config` shows them).

### 2. Build the bundle, and register the capture voice

```sh
uv run poe build-bridge     # assembles build/VoiceOverCaptureSpike.app
```

The bridge captures speech by publishing a **speech synthesis provider** that
macOS hands every utterance to. It ships as an app extension inside an app,
because a macOS app extension cannot be installed on its own. Register it, and
confirm the system published it:

```sh
cd bridges/voiceover
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/VoiceOverCaptureSpike.app
pluginkit -a                # the extension should be listed and enabled
./build/probe               # "FOUND ours: ..." among the system's voices
```

**Registering is not publishing, and the difference costs a reader restart.**
`pluginkit` will list the extension while `probe` still cannot see the voice: the
system publishes a newly registered provider only after VoiceOver restarts. That
cost is real, it is paid **every time the provider changes**, and it is scripted
rather than manual — it needs only the AppleEvents grant, never Accessibility:

```sh
osascript -e 'tell application "VoiceOver" to quit'
sleep 3
osascript -e 'tell application "VoiceOver" to activate'
sleep 14                    # measured: about 14 s before it answers again
./build/probe               # now it should be found
```

If it still does not appear, re-register and restart once more before concluding
anything — that is a known state, recorded as board entry 13.13a, and improvising
past it is how an evening goes missing.

You do **not** need to select the voice in VoiceOver Utility. The bridge selects
it at the handshake and puts your own voice back on every teardown path.

### 3. Switch on AppleScript control of VoiceOver

VoiceOver Utility → **General** → *Allow VoiceOver to be controlled with
AppleScript*. **No API sets this and the bridge cannot**: without it every
gesture, every liveness check and the VoiceOver-cursor route of `get_focus_info`
fail with `-1743`. The launcher prints whether it is on before anything is
pressed.

macOS will also ask for **Automation** permission the first time the bridge sends
the reader an event, and for **Accessibility** the first time a session calls
`type_text` — and only then, which is the design. A session that presses commands
and reads speech asks for neither.

> **If you are working over SSH, the consent dialog names something that looks
> unrelated.** macOS attributes an event to the process it holds *responsible*,
> which for anything launched from an SSH session is
> `/usr/libexec/sshd-keygen-wrapper` rather than the app — and granting it grants
> every SSH session on the machine, which is worth deciding deliberately. The
> chain is walked all the way up, so an editor launched over SSH passes its
> identity to everything it starts.

### 4. Start the bridge listening

There is no control dialog yet — it is board entry 13.14, deliberately held back
until the bridge can drive VoiceOver over its own window. Until then:

```sh
cd bridges/voiceover
swift build --product BridgeListener
.build/debug/BridgeListener              # add --unattended if nobody is there
```

It prints where it is listening, where it reads captured speech from, and what
the machine can do before anything is pressed: the capture voice's state, whether
AppleScript control is on, and which permissions are held. Reading those costs
nothing and asks nobody for anything.

**Redirect it to a file if you like; do NOT wrap it in `script(1)`.** Running the
bridge under a pty breaks the accessibility reads — every `get_focus_info`
answers `-25204` — and the failure looks exactly like a broken bridge. Its stdout
is unbuffered, so a plain `> run.log` shows everything as it happens.

Confirm the endpoint exists:

```sh
ls ~/.screenreader-mcp/voiceoverMcpBridge.sock
```

### 5. Drive it

`scripts/voiceover_announce.sh` is the guided instrument, and it is what
`uv run poe live` runs on this host. It opens a **silent** session, presses one
harmless command to show the reader is inaudible, then announces through the
bridge's own synthesizer to show the bridge is not — the two halves only mean
something together — and finally asks you a question and collects your answer.

```sh
bash scripts/voiceover_announce.sh
```

**It makes the machine speak, and that is the thing being tested.** Its read-only
siblings (`voiceover_focus.sh`, `voiceover_cursors.sh`, `voiceover_modifiers.sh`,
`voiceover_keyboard.sh`) are safe by default; this one cannot be, because a
channel cannot be tested without using it.

To drive the whole stack as an agent instead, register the built binary as a
project MCP server exactly as the NVDA section describes — the `.mcp.json` is
identical, and `./server/screenreader-mcp` carries the host's own executable
convention. Then `list_readers` names `voiceover`, and `connect_reader` reaches
it with no flags.

### What to expect, so you do not misread it

- **VoiceOver renders in your own language.** Nothing in this repo compares the
  reader's words, and neither should a check you write: compare structure —
  roles, counts, order, whether something was announced at all.
- **VoiceOver crashes.** The reader restarting underneath a session is normal
  weather on macOS rather than an edge case, which is why every check in lane 3
  is independently re-runnable from a cold start. Its own crash reports are in
  `~/Library/Logs/DiagnosticReports/` (and `Retired/` beneath it), and the reader
  keeps a count of its unplanned shutdowns in
  `com.apple.VoiceOver4.local.plist`.
- **A wedged application under test looks exactly like a dead reader.** Every
  cursor read answers `missing value` and dispatches appear to do nothing, while
  VoiceOver is entirely healthy and saying so out loud. Check what is in front
  before blaming the reader.

## Opening a pull request

- Branch off `main`. One component plus its ports and tests per pull request;
  nothing lands untested. See the workflow section of [`AGENTS.md`](AGENTS.md).
- A live-NVDA checklist goes in the **pull request body as checkboxes**, one item
  per check. Record findings inline on the item (NVDA version, expected vs
  observed); findings that need a change become iteration entries in
  `ROADMAP.md`. A CI job keeps a pull request from merging while any checkbox is
  unticked.
- All prose stays screen-reader friendly: no ASCII-art diagrams. Use Mermaid
  where it renders (not in the add-on's own `README.tpl.md`/`doc/`). The full
  rule, including the required `accTitle`/`accDescr`, is in `AGENTS.md`.

## License

By contributing you agree your contributions are licensed under **GPL v2**, the
project's license. See [`LICENSE`](LICENSE) / `COPYING.txt`.
