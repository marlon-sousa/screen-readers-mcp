# Dev-environment doctor for the nvda-mcp workspace.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe doctor        report
#     uv run poe fix           report, and repair what can be repaired
#
# ROLE: checks that this machine and checkout can work the repo; every task runs its `--quick` subset first.

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

#: redeploy.py imports this and the staleness check rather than restating them.
BINARY = ROOT / "server" / SERVER_BINARY_NAME

PY_PROJECTS = ("shared", "bridges/nvda")
PY_TOOLS = ("pytest", "pyright", "ruff")


def on_ci() -> bool:
	"""Export ``CI=1`` locally to rehearse what CI will do."""
	return bool(os.environ.get("CI"))


# A skip prints with its reason and never affects the exit code; only FAIL does.
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


#: One floor per tool, whether the repo or a bridge's tier wants it; a bridge declares only the name.
@dataclass(frozen=True)
class Tool:
	#: None: the banner does not order sensibly (gettext's Windows builds), so only presence is checked.
	minimum: tuple[int, ...] | None
	why: str
	fix: str
	#: None means the tool cannot be asked its version at all, unlike `minimum = None`.
	version_argv: tuple[str, ...] | None = ("--version",)


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
		version_argv=("version",),
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
	"swift": Tool(
		# The VoiceOver bridge's manifest uses swift-testing and `swiftLanguageModes`, both new in 6.0.
		(6, 0),
		"builds and tests a Swift bridge; `swift --version` reports the toolchain",
		"install Xcode 16 or later, then `xcode-select --install`",
	),
	"codesign": Tool(
		None,
		"signs a bridge's bundle; a speech provider that is not signed and "
		"sandboxed is not rejected -- it registers and never appears",
		"comes with the macOS command line tools",
		# `codesign --version` is an unrecognised option: it exits 2 and prints usage.
		version_argv=None,
	),
}

#: (tool, required, hosts): a tool not required only warns, and one not meant for this host is skipped.
CORE_TOOLS: tuple[tuple[str, bool, tuple[str, ...]], ...] = (
	("uv", True, (ANY_HOST,)),
	("go", True, (ANY_HOST,)),
	("git", True, (ANY_HOST,)),
	("rg", True, (ANY_HOST,)),
	("gh", False, (ANY_HOST,)),
	("pwsh", False, (Host.WINDOWS,)),
)


def _version_of(text: str) -> tuple[int, ...] | None:
	"""The first dotted-number run, since the banners share no other shape."""
	match = re.search(r"(\d+(?:\.\d+)+)", text)
	if not match:
		return None
	return tuple(int(part) for part in match.group(1).split("."))


def _check_tool(name: str, required: bool, label: str | None = None) -> Result:
	spec = TOOLS[name]
	shown = label or name
	if shutil.which(name) is None:
		return Result(FAIL if required else WARN, shown, f"not on PATH -- {spec.why}", spec.fix)
	if spec.version_argv is None:
		return Result(OK, shown, f"present at {shutil.which(name)}")
	code, banner = _run([name, *spec.version_argv])
	if code != 0 or not banner:
		return Result(WARN, shown, "present, but would not report a version", spec.fix)
	first = banner.splitlines()[0].strip()
	found = _version_of(banner)
	minimum = spec.minimum
	# A floor, not a pin; padded so 1.25 is not older than 1.25.0.
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
	out: list[Result] = []
	for name, required, hosts in CORE_TOOLS:
		if not supports(hosts):
			where = ", ".join(str(host) for host in hosts)
			out.append(Result(SKIP, name, f"not applicable on {HOST} -- wanted only on {where}"))
			continue
		out.append(_check_tool(name, required))
	return out


def _scons_interpreter() -> Path | None:
	"""The Python that owns `scons`, whose imports are what the build uses, not `sys.executable`'s."""
	found = shutil.which("scons")
	if not found:
		return None
	# Both a venv and a CPython install put the interpreter one level above Scripts/ or bin/.
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
	"""A tier's tools only warn: a missing packaging tool stops packaging but makes no other result lie."""
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
	if "scons" in wanted:
		out += check_addon_build_deps()
	return out


def check_bare_python() -> Result:
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
	"""An ancestor pyrightconfig.json outranks a local ``[tool.pyright]``, so each project has its own."""
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


def _venv_root(path: str) -> Path | None:
	parts = Path(path).parts
	if ".venv" not in parts:
		return None
	return ROOT.joinpath(*parts[: parts.index(".venv") + 1])


def _check_root_pyright_config() -> list[Result]:
	"""The root config is what an editor or LSP at the root reads; the gates read each project's own."""
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

	# Pyright silently ignores an extraPath that does not exist, and the venv layout differs per host.
	blind: list[str] = []
	for env in environments:
		listed = [path for path in env.get("extraPaths", []) if "site-packages" in path]
		venvs = {venv for venv in (_venv_root(path) for path in listed) if venv is not None}
		if not any(venv.is_dir() for venv in venvs):
			# An uncreated venv is check_dev_tools' finding; CI jobs build only the venvs they need.
			continue
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
	"""Only a warning: every poe task uses `python -m`, but CI invokes the console scripts."""
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
	"""Must mirror `pythonInterpreter` and `probePython` in server/tests/conformance/python_bridge_test.go."""
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
	"""Why the MCP server binary is out of date, or None if it is current; redeploy.py asks it too."""
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
	"""Every file whose contents end up inside the server binary.

	``//go:embed`` documents count, since an edited one changes nothing until a rebuild; test files do not,
	since a false stale prescribes a redeploy that drops every attached agent.
	"""
	yield from (path for path in (ROOT / "server").rglob("*.go") if not path.name.endswith("_test.go"))
	yield from (ROOT / "server").rglob("documents/*.md")


def check_server_binary() -> Result:
	"""An agent driving a stale binary sees a missing result field, which reads as the bridge's fault.

	The client keeps the process it spawned, so the MCP connection must be restarted after a rebuild.
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
	"""Compares newline-normalised text, because the copy carries a generated header."""
	source = ROOT / "shared" / "screenreader_wire" / "protocol.py"
	copy = ROOT / "bridges" / "nvda" / "addon" / "globalPlugins" / "nvdaMcpBridge" / "protocol.py"
	if not source.is_file() or not copy.is_file():
		return Result(WARN, "shared module synced", "one of the two copies is missing")

	def _norm(text: str) -> str:
		return text.replace("\r\n", "\n").strip()

	# sync_shared.py writes exactly `_HEADER + SOURCE`, so the copy must end with the source.
	if _norm(copy.read_text(encoding="utf-8")).endswith(_norm(source.read_text(encoding="utf-8"))):
		return Result(OK, "shared module synced", "addon copy matches shared/")
	return Result(
		FAIL,
		"shared module synced",
		"the addon's protocol.py differs from shared/ -- the bridge is on an old contract",
		"py -3.13 bridges/nvda/sync_shared.py",
	)


def repair() -> None:
	print("Repairing project environments...\n")
	for project in PY_PROJECTS:
		directory = ROOT / project
		print(f"  uv sync --reinstall  ({project})")
		code, out = _run(["uv", "sync", "--reinstall", "--directory", str(directory)])
		if code != 0:
			print(f"    FAILED: {out.splitlines()[-1] if out else code}")
	print()


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
	# Machine checks are skipped on CI, whose environment is declared in ci.yml; repo checks run everywhere.
	if not on_ci():
		results += check_core_tools()
		results.append(check_bare_python())
		results += check_bridges()
		results.append(check_server_binary())
	results += check_pyright_venv_config()
	results.append(check_shared_synced())
	if not args.quick and not on_ci():
		# Each spawns a uv environment per tool per project: too slow for the pre-task gate.
		results += check_dev_tools()
		results += check_trampolines()
		results.append(check_conformance_python())

	failures = [r for r in results if r.status == FAIL]
	if args.quick and not failures:
		return 0

	marks = {OK: "PASS", WARN: "WARN", FAIL: "FAIL", SKIP: "SKIP"}
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
