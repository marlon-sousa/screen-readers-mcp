# Dev-environment doctor for the nvda-mcp workspace.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe doctor        report
#     uv run poe fix           report, and repair what can be repaired
#
# WHY THIS EXISTS. Every check below corresponds to something that has already
# cost real time -- an agent or a contributor chasing a symptom whose cause was
# environmental, not a bug in the code:
#
#   * pyright with no venv configured reports ~140 phantom "Import could not be
#     resolved" errors, and you cannot tell them from real ones.
#   * A stale console-script trampoline fails with "uv trampoline failed to
#     canonicalize script path", which names neither the tool nor the fix.
#   * Without ripgrep, a search falls back to `grep -r`, which does NOT honour
#     .gitignore and so reads .venv and __pycache__ -- thousands of irrelevant
#     lines, and for an agent, thousands of wasted tokens.
#   * `python` on this machine points at a Python that is not installed.
#
# A check earns its place here by having burned someone once. Add to it when
# something new does.

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tomllib
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path

from platforms import ANY_HOST, HOST, SERVER_BINARY_NAME, Host, supports

from bridges import UnknownBridge, selected, undeclared

ROOT = Path(__file__).resolve().parent.parent

#: The MCP server binary an MCP client spawns. Named once, here, because
#: redeploy.py imports the staleness check below rather than restating it. The
#: FILENAME comes from platforms.py -- `.exe` on Windows, bare elsewhere -- so
#: that the doctor, the build and the redeploy can never disagree about which
#: file they are talking about.
BINARY = ROOT / "server" / SERVER_BINARY_NAME

#: The Python projects, and the dev tools each must be able to run.
PY_PROJECTS = ("shared", "bridges/nvda")
PY_TOOLS = ("pytest", "pyright", "ruff")


def on_ci() -> bool:
	"""Is this a CI runner rather than somebody's desktop?

	Set by GitHub Actions on every runner, and by every other CI host worth the
	name. Export ``CI=1`` locally to rehearse what CI will do.
	"""
	return bool(os.environ.get("CI"))


# SKIP is a fourth outcome, and it exists because SILENCE WAS THE ALTERNATIVE.
# A doctor that simply omits the checks that do not apply to this host cannot be
# read as a statement about the machine -- and the first question anyone has on a
# new host is precisely "what is NOT being checked here?". A skip prints, with
# its reason, and never affects the exit code. Only FAIL does.
OK, WARN, FAIL, SKIP = "ok", "warn", "fail", "skip"


@dataclass
class Result:
	status: str
	check: str
	detail: str
	fix: str = ""


def _run(args: list[str], cwd: Path | None = None) -> tuple[int, str]:
	try:
		done = subprocess.run(
			args,
			cwd=cwd,
			capture_output=True,
			text=True,
			timeout=180,
		)
	except (OSError, subprocess.TimeoutExpired) as exc:
		return 1, str(exc)
	return done.returncode, (done.stdout + done.stderr).strip()


# -- checks -------------------------------------------------------------------


#: How to check one external binary, wherever it is wanted.
#:
#: The version floor and the advice live in ONE table, because the same tool can
#: be wanted by the repo itself and by a bridge's tier -- and a floor that
#: differed between the two would be a floor nobody could state. A bridge
#: declares the NAME of a tool it needs; what "new enough" means stays here.
@dataclass(frozen=True)
class Tool:
	#: None means "presence is all we can check" -- gettext's Windows builds
	#: report version strings that do not order sensibly against the GNU ones,
	#: and a comparison that gives wrong answers is worse than no comparison.
	minimum: tuple[int, ...] | None
	why: str
	fix: str


TOOLS: dict[str, Tool] = {
	"uv": Tool(
		(0, 5, 0),
		"runs every Python task; 0.5 is where dependency-groups landed",
		"https://docs.astral.sh/uv/getting-started/",
	),
	"go": Tool(
		(1, 25, 0),
		"builds and tests the MCP server; the minimum is server/go.mod's own",
		"https://go.dev/dl/",
	),
	"git": Tool((2, 30), "version control", "https://git-scm.com/downloads"),
	"rg": Tool(
		(13, 0),
		"without it a search falls back to grep -r, which does NOT honour "
		".gitignore and so reads .venv and __pycache__ -- thousands of "
		"irrelevant lines per search",
		"winget install BurntSushi.ripgrep.MSVC  |  brew install ripgrep",
	),
	"gh": Tool(
		(2, 55),
		"PR and issue work. BELOW 2.55 `gh pr edit` fails with the Projects-classic "
		"deprecation error and every body/title edit needs a REST workaround",
		"winget upgrade GitHub.cli  |  brew install gh",
	),
	"pwsh": Tool(
		(7, 0),
		"PowerShell 7. The Windows PowerShell 5.1 that box defaults to has no "
		"&& or ||, and wraps every native stderr line in a multi-line ErrorRecord "
		"-- verbose, slow to read, and it reports failure on exit code 0",
		"winget install Microsoft.PowerShell",
	),
	"scons": Tool(
		(4, 0),
		"builds a bridge's shippable artifact",
		"uv tool install scons --with markdown",
	),
	"msgfmt": Tool(
		None,
		"gettext: scons compiles a bridge's .po files into .mo with it",
		"winget install GnuWin32.GetText  |  brew install gettext",
	),
	"xgettext": Tool(None, "gettext: extracts a bridge's translatable strings", "same as msgfmt"),
}

#: (tool, required, hosts) -- what the REPO needs, whatever bridge you work on.
#:
#: "Required" means you cannot work the repo without it; everything else degrades
#: one named task and is reported as a warning.
#:
#: `hosts` is ANY_HOST unless the tool is only meaningful somewhere, and a tool
#: that is not meaningful here is SKIPPED rather than warned about: `pwsh` exists
#: to replace a shell only Windows has, so warning a macOS box about it is noise
#: -- and noise trains people to ignore the whole report.
#:
#: A BRIDGE's build tools are deliberately not here. They are declared by the
#: bridge, per tier, and checked in check_bridges(). See spec 0042, decision 2.
CORE_TOOLS: tuple[tuple[str, bool, tuple[str, ...]], ...] = (
	("uv", True, (ANY_HOST,)),
	("go", True, (ANY_HOST,)),
	("git", True, (ANY_HOST,)),
	("rg", True, (ANY_HOST,)),
	("gh", False, (ANY_HOST,)),
	("pwsh", False, (Host.WINDOWS,)),
)


def _version_of(text: str) -> tuple[int, ...] | None:
	"""First dotted-number run in a --version banner, as a comparable tuple.

	Deliberately loose: these banners have no common shape (`go version go1.26.5
	windows/amd64`, `git version 2.47.0.windows.2`, `uv 0.11.17 (hash date)`),
	and the leading number is the one that means something in all of them.
	"""
	match = re.search(r"(\d+(?:\.\d+)+)", text)
	if not match:
		return None
	return tuple(int(part) for part in match.group(1).split("."))


def _check_tool(name: str, required: bool, label: str | None = None) -> Result:
	"""Is this binary present, and new enough? Shared by the core and bridge checks."""
	spec = TOOLS[name]
	shown = label or name
	if shutil.which(name) is None:
		return Result(FAIL if required else WARN, shown, f"not on PATH -- {spec.why}", spec.fix)
	# `go` spells it `go version`, not `go --version`.
	code, banner = _run([name, "version"] if name == "go" else [name, "--version"])
	if code != 0 or not banner:
		return Result(WARN, shown, "present, but would not report a version", spec.fix)
	first = banner.splitlines()[0].strip()
	found = _version_of(banner)
	minimum = spec.minimum
	# A FLOOR, never a pin: anything at or above the minimum passes, so a newer
	# toolchain is always fine. Pad the found version to the minimum's length
	# first, or a two-part 1.25 would compare as older than a three-part 1.25.0
	# and fail a version that satisfies it.
	padded = (found + (0,) * len(minimum))[: len(minimum)] if (minimum and found) else None
	if padded and minimum and padded < minimum:
		want = ".".join(str(part) for part in minimum)
		return Result(
			FAIL if required else WARN,
			shown,
			f"{first} -- below the {want} this repo needs. {spec.why}",
			spec.fix,
		)
	return Result(OK, shown, first)


def check_core_tools() -> list[Result]:
	"""Everything the workspace shells out to, whatever bridge you are working on."""
	out: list[Result] = []
	for name, required, hosts in CORE_TOOLS:
		if not supports(hosts):
			where = ", ".join(str(host) for host in hosts)
			out.append(Result(SKIP, name, f"not applicable on {HOST} -- wanted only on {where}"))
			continue
		out.append(_check_tool(name, required))
	return out


def _scons_interpreter() -> Path | None:
	"""The Python that owns `scons`, which is NOT the one running this script.

	scons is invoked as a standalone tool from whichever interpreter it was
	installed into, so its imports must be checked there. Checking them against
	`sys.executable` -- the poe devtools venv -- reports a missing `markdown`
	on a machine that builds addons perfectly well, which is a false alarm, and
	a false alarm trains people to ignore the whole report.
	"""
	found = shutil.which("scons")
	if not found:
		return None
	# Both a venv and a CPython install put console scripts in Scripts/ (or
	# bin/) with the interpreter one level up.
	scripts = Path(found).resolve().parent
	for candidate in (
		scripts.parent / "python.exe",
		scripts.parent / "bin" / "python",
		scripts.parent / "python",
	):
		if candidate.is_file():
			return candidate
	return None


def check_addon_build_deps() -> list[Result]:
	"""scons imports these from ITS interpreter, not from a project venv."""
	interpreter = _scons_interpreter()
	if interpreter is None:
		return [
			Result(
				WARN,
				"scons interpreter",
				"could not locate the Python that owns scons; skipping its import checks",
			)
		]
	out = [Result(OK, "scons interpreter", str(interpreter))]
	for module, why in (
		("SCons", "the build tool itself"),
		("markdown", "scons renders the addon's docs to HTML"),
	):
		code, _ = _run([str(interpreter), "-c", f"import {module}"])
		if code == 0:
			out.append(Result(OK, f"scons python: {module}", "importable"))
		else:
			out.append(
				Result(
					WARN,
					f"scons python: {module}",
					f"not importable -- {why}",
					f'"{interpreter}" -m pip install {module}',
				)
			)
	return out


def check_bridges() -> list[Result]:
	"""Each selected bridge: which of its tiers run here, and what those tiers need.

	The SERVER is deliberately absent from this section and always will be. It is
	built and tested on every host with no guard, and no bridge has an opinion
	about it (spec 0042, decision 1). What genuinely varies per machine is what you
	can do with a BRIDGE, because that follows the reader: NVDA and JAWS are
	Windows, VoiceOver is macOS, TalkBack is Android behind a host SDK.

	A tier's tools are checked as WARNINGS even when the tier runs here. The FAIL
	bar in this file is "believing any other result would be a mistake", and a
	missing packaging tool does not make a test lie -- it stops you packaging.
	"""
	out: list[Result] = []
	for name in undeclared():
		out.append(
			Result(
				FAIL,
				f"bridges/{name}",
				"no [tool.screen-readers-mcp.bridge] declaration -- nothing about it is checked",
				f"add the block to bridges/{name}/pyproject.toml, as bridges/nvda does",
			)
		)
	try:
		chosen = selected()
	except UnknownBridge as exc:
		out.append(Result(FAIL, "BRIDGES", str(exc), "unset BRIDGES, or name a directory under bridges/"))
		return out
	if not chosen:
		out.append(
			Result(
				WARN,
				"bridges",
				f"no bridge declares any work on {HOST}; the server half is still fully checked",
				"uv run poe bridges  (what each bridge declares, and where it runs)",
			)
		)
		return out

	#: tool -> the first tier that asked for it, so one missing binary is reported
	#: once with a name that says who wanted it.
	wanted: dict[str, str] = {}
	for bridge in chosen:
		for tier in bridge.tiers:
			label = f"{bridge.name}: {tier.name}"
			if not tier.runs_here():
				why = tier.reason or f"declared for {', '.join(tier.hosts) or 'no host'}"
				out.append(Result(SKIP, label, why))
				continue
			out.append(Result(OK, label, f"can {tier.question} here"))
			for tool in tier.tools:
				wanted.setdefault(tool, label)
	for tool, wanted_by in sorted(wanted.items()):
		if tool not in TOOLS:
			out.append(
				Result(
					FAIL,
					tool,
					f"{wanted_by} declares a tool this doctor has no check for",
					"add it to TOOLS in scripts/doctor.py, with its floor and its fix",
				)
			)
			continue
		out.append(_check_tool(tool, required=False, label=f"{wanted_by}: {tool}"))
	# The scons INTERPRETER's imports are only a question once something wants
	# scons at all, so the check rides along rather than being asked everywhere.
	if "scons" in wanted:
		out += check_addon_build_deps()
	return out


def check_bare_python() -> Result:
	"""`python` is documented as broken here; confirm, so the doc stays true.

	This is a WARN, never a FAIL: nothing in the task list calls bare `python`
	from a shell. It is here so that if someone fixes their launcher, the
	AGENTS.md warning can be retired instead of being cargo-culted forever.
	"""
	if shutil.which("python") is None:
		return Result(WARN, "bare python", "not on PATH (fine -- tasks use uv)")
	code, out = _run(["python", "--version"])
	if code != 0:
		return Result(
			WARN,
			"bare python",
			f"present but broken: {out.splitlines()[0] if out else code}",
			"expected on this machine; use `uv run` or `py -3.13`, never bare `python`",
		)
	return Result(OK, "bare python", out.splitlines()[0] if out else "works")


def check_pyright_venv_config() -> list[Result]:
	"""pyright must be told which venv to analyse against, or it lies.

	With no ``venvPath``/``venv``, pyright resolves imports against whatever
	environment it inherits. Run one way it is correct; run another it reports
	every test import as unresolved and buries the real diagnostics.

	Each project's settings live in its own ``pyrightconfig.json``, never in a
	``[tool.pyright]`` section. Pyright walks UP the tree for a
	``pyrightconfig.json``, and an ancestor one outranks a local
	``[tool.pyright]`` -- so the repo-root config written for editors and LSP
	clients would silently retype these projects if they relied on pyproject.toml.
	A local ``pyrightconfig.json`` does outrank the ancestor, which is why each
	project carries one.
	"""
	out: list[Result] = []
	for project in PY_PROJECTS:
		path = ROOT / project / "pyrightconfig.json"
		if not path.is_file():
			out.append(
				Result(
					FAIL,
					f"{project}: pyright config",
					"no pyrightconfig.json -- the repo-root config would take over",
					f"create {project}/pyrightconfig.json with venvPath and venv",
				)
			)
			continue
		try:
			config = json.loads(path.read_text(encoding="utf-8"))
		except ValueError as exc:
			out.append(Result(FAIL, f"{project}: pyright config", f"unparseable -- {exc}"))
			continue
		if config.get("venvPath") and config.get("venv"):
			out.append(Result(OK, f"{project}: pyright venv", "configured"))
		else:
			out.append(
				Result(
					FAIL,
					f"{project}: pyright venv",
					"no venvPath/venv -- pyright will report phantom import errors",
					f'add "venvPath": "." and "venv": ".venv" to {project}/pyrightconfig.json',
				)
			)

		# A [tool.pyright] section here is DEAD config: pyrightconfig.json wins.
		# Left in place it drifts, and the drift is invisible.
		pyproject = ROOT / project / "pyproject.toml"
		if pyproject.is_file():
			with pyproject.open("rb") as handle:
				if tomllib.load(handle).get("tool", {}).get("pyright"):
					out.append(
						Result(
							FAIL,
							f"{project}: dead pyright config",
							"[tool.pyright] in pyproject.toml is ignored -- pyrightconfig.json wins",
							f"delete [tool.pyright] from {project}/pyproject.toml",
						)
					)
	return out + _check_root_pyright_config()


def _check_root_pyright_config() -> list[Result]:
	"""The repo-root pyrightconfig.json is what an LSP at the root reads.

	It exists so an editor or agent launched at the repo root sees what the gates
	see. It is NOT what the gates read -- each project's own pyrightconfig.json is.
	If a Python project is missing an execution environment here, files under it
	resolve against the wrong interpreter and the root view goes back to lying.
	"""
	path = ROOT / "pyrightconfig.json"
	if not path.is_file():
		return [
			Result(
				FAIL,
				"root pyright config",
				"missing -- an LSP at the repo root will report phantom imports",
				"restore pyrightconfig.json at the repo root",
			)
		]
	try:
		config = json.loads(path.read_text(encoding="utf-8"))
	except ValueError as exc:
		return [Result(FAIL, "root pyright config", f"unparseable -- {exc}")]
	environments = config.get("executionEnvironments", [])
	roots = {env.get("root") for env in environments}
	missing = [project for project in PY_PROJECTS if project not in roots]
	if missing:
		return [
			Result(
				FAIL,
				"root pyright config",
				f"no executionEnvironment for {', '.join(missing)}",
				"add one with that root, its pythonVersion, and its .venv site-packages",
			)
		]

	# An execution environment cannot carry its own `venv`, only `extraPaths`, so
	# each one names a venv's site-packages BY PATH -- and that path is
	# host-shaped: `.venv/Lib/site-packages` on Windows,
	# `.venv/lib/python3.13/site-packages` on POSIX. Both are listed, since
	# pyright ignores an extraPath that does not exist.
	#
	# WHICH IS EXACTLY WHY THIS CHECK EXISTS. "Ignores what is missing" means a
	# wrong path costs nothing at parse time and everything at analysis time: on
	# macOS, before spec 0042, all three environments named only the Windows
	# layout and a root run reported 331 errors where the gates report none. A
	# silent extraPath needs a loud check, or the config drifts again the next
	# time a layout does.
	blind: list[str] = []
	for env in environments:
		listed = [path for path in env.get("extraPaths", []) if "site-packages" in path]
		if listed and not any((ROOT / path).is_dir() for path in listed):
			blind.append(f"{env.get('root')} ({', '.join(listed)})")
	if blind:
		return [
			Result(
				FAIL,
				"root pyright config",
				f"no site-packages path resolves on this host for: {'; '.join(blind)}",
				"add this host's venv layout to that executionEnvironment's extraPaths",
			)
		]
	return [Result(OK, "root pyright config", "covers every Python project, and resolves here")]


def check_dev_tools() -> list[Result]:
	"""Each Python project must be able to actually run its declared tooling."""
	out: list[Result] = []
	for project in PY_PROJECTS:
		directory = ROOT / project
		if not (directory / ".venv").is_dir():
			out.append(Result(FAIL, f"{project}: venv", "missing", "uv run poe fix"))
			continue
		for tool in PY_TOOLS:
			code, detail = _run(
				[
					"uv",
					"run",
					"--directory",
					str(directory),
					"--with",
					tool,
					"python",
					"-m",
					tool,
					"--version",
				],
			)
			if code == 0:
				out.append(Result(OK, f"{project}: {tool}", detail.splitlines()[0] if detail else "ok"))
			else:
				out.append(
					Result(
						FAIL,
						f"{project}: {tool}",
						(detail.splitlines()[-1] if detail else f"exit {code}"),
						"uv run poe fix",
					)
				)
	return out


def check_trampolines() -> list[Result]:
	"""Console scripts are what CI uses; a stale one is a confusing failure.

	WARN, not FAIL: every poe task uses `python -m`, so a broken trampoline
	cannot break the task list. It still matters, because CI invokes the console
	scripts, and because the error message it produces names nothing useful.
	"""
	out: list[Result] = []
	for project in PY_PROJECTS:
		code, detail = _run(
			["uv", "run", "--directory", str(ROOT / project), "--with", "pytest", "pytest", "--version"],
		)
		if code == 0:
			out.append(Result(OK, f"{project}: console scripts", "resolve"))
		else:
			out.append(
				Result(
					WARN,
					f"{project}: console scripts",
					(detail.splitlines()[-1] if detail else f"exit {code}"),
					"uv run poe fix  (tasks still work -- they use `python -m`)",
				)
			)
	return out


def check_conformance_python() -> Result:
	"""The conformance tier spawns a real Python 3.13 to host the bridge.

	This MIRRORS the Go test's own search -- `pythonInterpreter` and `probePython`
	in server/tests/conformance/python_bridge_test.go: CONFORMANCE_PYTHON first as
	a space-separated command, then `python`, `python3.13`, `python3`, and the `py`
	launcher only on Windows; the floor is `sys.version_info >= (3, 13)`.

	It has to mirror it, because it speaks FOR it. This check used to look for the
	Windows `py` launcher and nothing else, so on macOS it warned that the tier
	would fail while the tier itself passed -- `poe` puts the workspace venv's 3.13
	on PATH and the Go probe finds it. A doctor that is wrong about a passing tier
	is worse than one that says nothing about it.
	"""
	probe = "import sys; sys.exit(0 if sys.version_info >= (3, 13) else 1)"
	override = os.environ.get("CONFORMANCE_PYTHON")
	if override and override.strip():
		command = override.split()
		if _run([*command, "-c", probe])[0] == 0:
			version = _run([*command, "--version"])[1].splitlines()
			shown = version[0] if version else override
			return Result(OK, "conformance python", f"CONFORMANCE_PYTHON={shown}")
		return Result(
			FAIL,
			"conformance python",
			f"CONFORMANCE_PYTHON={override} is not a Python 3.13 that runs",
			"unset it and let the tier find one, or point it at a real 3.13",
		)
	candidates = [["python"], ["python3.13"], ["python3"]]
	if HOST is Host.WINDOWS:
		candidates.append(["py", "-3.13"])
	for candidate in candidates:
		if shutil.which(candidate[0]) is None:
			continue
		if _run([*candidate, "-c", probe])[0] == 0:
			shown = _run([*candidate, "--version"])[1].splitlines()
			return Result(OK, "conformance python", f"{' '.join(candidate)} -- {shown[0] if shown else 'ok'}")
	return Result(
		WARN,
		"conformance python",
		"no Python 3.13 on PATH; the conformance tier will fail rather than skip",
		"py -3.13" if HOST is Host.WINDOWS else "uv python install 3.13, or set CONFORMANCE_PYTHON",
	)


def stale_server_binary() -> str | None:
	"""Why the MCP server binary is out of date, or None if it is current.

	Factored out of the check below because `scripts/redeploy.py --if-stale` asks
	the same question, and two implementations of "is this binary stale" is one
	more than the number of answers the repo can afford: they would drift, and the
	symptom would be `poe dev` disagreeing with `poe doctor` about a binary.
	"""
	if not BINARY.is_file():
		return "not built"
	built = BINARY.stat().st_mtime
	newest, newest_name = 0.0, ""
	for path in _server_build_inputs():
		stamp = path.stat().st_mtime
		if stamp > newest:
			newest, newest_name = stamp, path.name
	if newest <= built:
		return None
	return f"{newest_name} is newer than the binary the MCP client runs"


def _server_build_inputs() -> Iterator[Path]:
	"""Every file whose contents end up INSIDE the server binary.

	The .go sources, and the markdown documents they pull in with ``//go:embed``.

	THE DOCUMENTS ARE NOT OPTIONAL HERE, and leaving them out is a trap that hides
	perfectly: ``//go:embed`` copies a file's bytes at COMPILE time, so editing
	``guidance-preamble.md`` changes nothing at all until the binary is rebuilt.
	Without this, the doctor would rglob only ``*.go``, see nothing newer than the
	binary, and pronounce it current -- while the running server served the
	previous wording of a document to every agent that read it. Nothing would say
	so, in the one check whose whole job is to say so.

	Scoped to ``documents/`` rather than every .md under server/, so that editing
	``server/README.md`` -- which no build consumes -- does not manufacture a
	rebuild.
	"""
	yield from (ROOT / "server").rglob("*.go")
	yield from (ROOT / "server").rglob("documents/*.md")


def check_server_binary() -> Result:
	"""The MCP server BINARY must be newer than the Go source it was built from.

	This is the one staleness that hides best. The binary in .mcp.json is what
	the MCP client actually spawns, so an agent editing server/ and then driving
	the tools is testing the OLD server against the NEW bridge -- and the
	symptom is a field that is simply absent from a result, which reads as "the
	bridge did not send it" rather than "your server predates it". That happened:
	`bridgeVersion` was added, the bridge sent it, the whole live checklist ran,
	and nobody noticed the server could not carry it because the binary was four
	days old.

	Rebuilding is not enough on its own -- the client spawned the old process at
	startup and keeps it, so the MCP connection has to be restarted too. The fix
	text says so, because a rebuild that appears to change nothing is its own
	rabbit hole.

	`poe dev` no longer reaches this failure: it redeploys first when the binary
	is stale (see redeploy.py --if-stale), so the check is satisfied by the time
	the doctor runs. The check stays because dev is not the only way in -- a bare
	`poe doctor`, `poe bridge` or `poe live` still gets told, and those are
	exactly the runs where an agent is about to drive the MCP tools.
	"""
	if not BINARY.is_file():
		return Result(
			WARN,
			"server binary",
			"not built -- the MCP tools cannot run",
			"uv run poe build-server",
		)
	reason = stale_server_binary()
	if reason is None:
		return Result(OK, "server binary", "newer than server/*.go and its embedded documents")
	return Result(
		FAIL,
		"server binary",
		f"STALE -- {reason}",
		"uv run poe redeploy, then restart the MCP connection",
	)


def check_shared_synced() -> Result:
	"""The addon carries a COPY of the wire module; a stale copy is invisible.

	The comparison mirrors what sync_shared.py actually writes -- the source
	with a generated header prepended -- rather than comparing raw bytes. It
	also normalises newlines, because the two files are checked out through
	different .gitattributes rules and a CRLF/LF difference is invisible to
	every consumer. Getting either wrong turns this check into a false alarm,
	which is worse than no check: it trains people to ignore it.
	"""
	source = ROOT / "shared" / "nvda_mcp_wire" / "protocol.py"
	copy = ROOT / "bridges" / "nvda" / "addon" / "globalPlugins" / "nvdaMcpBridge" / "protocol.py"
	if not source.is_file() or not copy.is_file():
		return Result(WARN, "shared module synced", "one of the two copies is missing")

	def _norm(text: str) -> str:
		return text.replace("\r\n", "\n").strip()

	# sync_shared.py writes exactly `_HEADER + SOURCE`, so the copy must END
	# WITH the source. Testing the suffix rather than stripping a guessed number
	# of header lines means the check cannot over-strip and mask a real change.
	if _norm(copy.read_text(encoding="utf-8")).endswith(_norm(source.read_text(encoding="utf-8"))):
		return Result(OK, "shared module synced", "addon copy matches shared/")
	return Result(
		FAIL,
		"shared module synced",
		"the addon's protocol.py differs from shared/ -- the bridge is on an old contract",
		"py -3.13 bridges/nvda/sync_shared.py",
	)


# -- repair -------------------------------------------------------------------


def repair() -> None:
	print("Repairing project environments...\n")
	for project in PY_PROJECTS:
		directory = ROOT / project
		print(f"  uv sync --reinstall  ({project})")
		code, out = _run(["uv", "sync", "--reinstall", "--directory", str(directory)])
		if code != 0:
			print(f"    FAILED: {out.splitlines()[-1] if out else code}")
	print()


# -- main ---------------------------------------------------------------------


def main() -> int:
	parser = argparse.ArgumentParser(description="Check the nvda-mcp dev environment.")
	parser.add_argument("--fix", action="store_true", help="repair what can be repaired first")
	parser.add_argument(
		"--quick",
		action="store_true",
		help="skip the checks that spawn a uv env per tool; for use as a pre-task gate",
	)
	args = parser.parse_args()

	if args.fix:
		repair()

	results: list[Result] = []
	# The MACHINE checks -- "is this workstation set up to work the repo". On CI
	# they are the wrong question, and asking it is what kept `poe` out of the
	# workflow: the `shared` job installs uv and nothing else, so the required
	# `go`/`rg` would abort it before a single test ran. CI does not need them.
	# Its environment is DECLARED, in ci.yml's setup steps, and when something is
	# missing the step that wanted it fails immediately naming the tool -- there
	# is no mystery for a doctor to diagnose. The doctor's value is on a desktop
	# that drifted, which a fresh runner cannot have done.
	#
	# The REPO checks below the guard are asked everywhere, because they are
	# facts about the checkout rather than about the machine.
	if not on_ci():
		results += check_core_tools()
		results.append(check_bare_python())
		results += check_bridges()
		results.append(check_server_binary())
	results += check_pyright_venv_config()
	results.append(check_shared_synced())
	if not args.quick and not on_ci():
		# These spawn a uv environment per tool per project -- a few seconds,
		# which is fine for `poe doctor` and far too slow to sit in front of
		# every `poe bridge`. The quick set still catches the failures that
		# make OTHER results untrustworthy: a missing tool, an unconfigured
		# pyright, an addon on a stale wire contract.
		results += check_dev_tools()
		results += check_trampolines()
		results.append(check_conformance_python())

	failures = [r for r in results if r.status == FAIL]
	if args.quick and not failures:
		# Nothing to say: the gate passed and the real task is what matters.
		return 0

	marks = {OK: "PASS", WARN: "WARN", FAIL: "FAIL", SKIP: "SKIP"}
	# The host is printed even when nothing is wrong, because every SKIP below
	# is only readable against it: "not applicable on macos" means nothing if
	# you cannot see which machine answered.
	print(f"host: {HOST}\n")
	width = max(len(r.check) for r in results)
	for result in results:
		print(f"  {marks[result.status]}  {result.check.ljust(width)}  {result.detail}")
		if result.fix and result.status != OK:
			print(f"        {' ' * width}  -> {result.fix}")

	warnings = [r for r in results if r.status == WARN]
	skipped = [r for r in results if r.status == SKIP]
	print()
	if failures:
		print(f"{len(failures)} check(s) FAILED. Fix these before trusting any other result --")
		print("a failure here makes green tests and red tests equally uninformative.")
		if not args.fix:
			print("Many are repaired by:  uv run poe fix")
		return 1
	tail = f", {len(skipped)} not applicable here" if skipped else ""
	print(f"Environment is sound ({len(warnings)} warning(s){tail}). Safe to work.")
	return 0


if __name__ == "__main__":
	sys.exit(main())
