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
import os
import re
import shutil
import subprocess
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

#: The Python projects, and the dev tools each must be able to run.
PY_PROJECTS = ("shared", "bridges/nvda")
PY_TOOLS = ("pytest", "pyright", "ruff")

OK, WARN, FAIL = "ok", "warn", "fail"


@dataclass
class Result:
	status: str
	check: str
	detail: str
	fix: str = ""


def _run(args: list[str], cwd: Path | None = None) -> tuple[int, str]:
	try:
		done = subprocess.run(
			args, cwd=cwd, capture_output=True, text=True, timeout=180,
		)
	except (OSError, subprocess.TimeoutExpired) as exc:
		return 1, str(exc)
	return done.returncode, (done.stdout + done.stderr).strip()


# -- checks -------------------------------------------------------------------


#: (binary, required, minimum, why it matters, how to get it).
#:
#: "Required" means you cannot work the repo without it; everything else
#: degrades one named task and is reported as a warning.
#:
#: A minimum of None means "presence is all we can check" -- gettext's Windows
#: builds report version strings that do not order sensibly against the GNU
#: ones, and a comparison that gives wrong answers is worse than no comparison.
BINARIES = (
	(
		"uv", True, (0, 5, 0),
		"runs every Python task; 0.5 is where dependency-groups landed",
		"https://docs.astral.sh/uv/getting-started/",
	),
	(
		"go", True, (1, 25, 0),
		"builds and tests the MCP server; the minimum is server/go.mod's own",
		"https://go.dev/dl/",
	),
	("git", True, (2, 30), "version control", "https://git-scm.com/downloads"),
	(
		"rg", True, (13, 0),
		"without it a search falls back to grep -r, which does NOT honour "
		".gitignore and so reads .venv and __pycache__ -- thousands of "
		"irrelevant lines per search",
		"winget install BurntSushi.ripgrep.MSVC",
	),
	(
		"scons", False, (4, 0),
		"builds the .nvda-addon",
		"pip install scons  (into the interpreter you build addons with)",
	),
	(
		"msgfmt", False, None,
		"gettext: scons compiles the addon's .po files into .mo with it",
		"winget install GnuWin32.GetText  (or the gettext-tools MSYS2 package)",
	),
	("xgettext", False, None, "gettext: extracts the addon's translatable strings", "same as msgfmt"),
	(
		"gh", False, (2, 55),
		"PR and issue work. BELOW 2.55 `gh pr edit` fails with the Projects-classic "
		"deprecation error and every body/title edit needs a REST workaround",
		"winget upgrade GitHub.cli",
	),
	(
		"pwsh", False, (7, 0),
		"PowerShell 7. The Windows PowerShell 5.1 this box defaults to has no "
		"&& or ||, and wraps every native stderr line in a multi-line ErrorRecord "
		"-- verbose, slow to read, and it reports failure on exit code 0",
		"winget install Microsoft.PowerShell",
	),
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


def check_binaries() -> list[Result]:
	"""Everything the workspace shells out to, required or not."""
	out: list[Result] = []
	for name, required, minimum, why, fix in BINARIES:
		if shutil.which(name) is None:
			out.append(Result(FAIL if required else WARN, name, f"not on PATH -- {why}", fix))
			continue
		# `go` spells it `go version`, not `go --version`.
		code, banner = _run([name, "version"] if name == "go" else [name, "--version"])
		if code != 0 or not banner:
			out.append(Result(WARN, name, "present, but would not report a version", fix))
			continue
		shown = banner.splitlines()[0].strip()
		found = _version_of(banner)
		# A FLOOR, never a pin: anything at or above the minimum passes, so a
		# newer toolchain is always fine. Pad the found version to the
		# minimum's length first, or a two-part 1.25 would compare as older
		# than a three-part 1.25.0 and fail a version that satisfies it.
		padded = (found + (0,) * len(minimum))[: len(minimum)] if (minimum and found) else None
		if padded and padded < minimum:
			want = ".".join(str(part) for part in minimum)
			out.append(
				Result(
					FAIL if required else WARN,
					name,
					f"{shown} -- below the {want} this repo needs. {why}",
					fix,
				)
			)
		else:
			out.append(Result(OK, name, shown))
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
	for candidate in (scripts.parent / "python.exe", scripts.parent / "bin" / "python", scripts.parent / "python"):
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
	"""
	out: list[Result] = []
	for project in PY_PROJECTS:
		path = ROOT / project / "pyproject.toml"
		if not path.is_file():
			out.append(Result(FAIL, f"{project}: pyproject", "missing"))
			continue
		with path.open("rb") as handle:
			config = tomllib.load(handle)
		pyright = config.get("tool", {}).get("pyright", {})
		if pyright.get("venvPath") and pyright.get("venv"):
			out.append(Result(OK, f"{project}: pyright venv", "configured"))
		else:
			out.append(
				Result(
					FAIL,
					f"{project}: pyright venv",
					"no venvPath/venv -- pyright will report phantom import errors",
					'add venvPath = "." and venv = ".venv" under [tool.pyright]',
				)
			)
	return out


def check_dev_tools() -> list[Result]:
	"""Each Python project must be able to actually run its declared tooling."""
	out: list[Result] = []
	for project in PY_PROJECTS:
		directory = ROOT / project
		if not (directory / ".venv").is_dir():
			out.append(
				Result(FAIL, f"{project}: venv", "missing", "uv run poe fix")
			)
			continue
		for tool in PY_TOOLS:
			code, detail = _run(
				["uv", "run", "--directory", str(directory), "--with", tool,
				 "python", "-m", tool, "--version"],
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
			["uv", "run", "--directory", str(ROOT / project), "--with", "pytest",
			 "pytest", "--version"],
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
	"""The conformance tier spawns a real Python 3.13 to host the bridge."""
	override = os.environ.get("CONFORMANCE_PYTHON")
	if override:
		code, out = _run([override, "--version"])
		if code == 0:
			return Result(OK, "conformance python", f"CONFORMANCE_PYTHON={out}")
		return Result(FAIL, "conformance python", f"CONFORMANCE_PYTHON={override} does not run", "")
	if shutil.which("py"):
		code, out = _run(["py", "-3.13", "--version"])
		if code == 0:
			return Result(OK, "conformance python", out or "py -3.13")
	return Result(
		WARN,
		"conformance python",
		"no py -3.13 found; the conformance tier will fail rather than skip",
		"install Python 3.13, or set CONFORMANCE_PYTHON to one",
	)


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
	"""
	binary = ROOT / "server" / "screenreader-mcp.exe"
	if not binary.is_file():
		return Result(
			WARN,
			"server binary",
			"not built -- the MCP tools cannot run",
			"uv run poe build-server",
		)
	built = binary.stat().st_mtime
	newest, newest_name = 0.0, ""
	for path in (ROOT / "server").rglob("*.go"):
		stamp = path.stat().st_mtime
		if stamp > newest:
			newest, newest_name = stamp, path.name
	if newest <= built:
		return Result(OK, "server binary", "newer than server/*.go")
	return Result(
		FAIL,
		"server binary",
		f"STALE -- {newest_name} is newer than the binary the MCP client runs",
		"uv run poe build-server, then restart the MCP connection",
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
	results += check_binaries()
	results.append(check_bare_python())
	results += check_addon_build_deps()
	results += check_pyright_venv_config()
	results.append(check_shared_synced())
	results.append(check_server_binary())
	if not args.quick:
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

	marks = {OK: "PASS", WARN: "WARN", FAIL: "FAIL"}
	width = max(len(r.check) for r in results)
	for result in results:
		print(f"  {marks[result.status]}  {result.check.ljust(width)}  {result.detail}")
		if result.fix and result.status != OK:
			print(f"        {' ' * width}  -> {result.fix}")

	warnings = [r for r in results if r.status == WARN]
	print()
	if failures:
		print(f"{len(failures)} check(s) FAILED. Fix these before trusting any other result --")
		print("a failure here makes green tests and red tests equally uninformative.")
		if not args.fix:
			print("Many are repaired by:  uv run poe fix")
		return 1
	print(f"Environment is sound ({len(warnings)} warning(s)). Safe to work.")
	return 0


if __name__ == "__main__":
	sys.exit(main())
