# The bridge registry: what each bridge needs, and which of it can be done here.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe bridges                      what runs where, on this machine
#     BRIDGES=nvda uv run poe doctor          narrow to one bridge deliberately
#
# ROLE: reads the declaration each bridge writes in its OWN pyproject.toml and
# answers two questions -- which bridges are in play on this machine, and which
# of their tiers can actually run here. It is consulted by doctor.py, and run as
# a CLI by the `bridges` task and by the guards on `live` / `live-slow`.
#
# WHY THE DECLARATION LIVES WITH THE BRIDGE. NVDA is Windows, JAWS is Windows,
# VoiceOver is macOS, TalkBack is Android behind a host SDK: what a bridge needs
# is a fact about that reader, and the bridge is the only place that fact is not
# a guess. A central list here would have to be edited by every bridge that
# lands, which is how such a list goes stale.
#
# WHAT THIS IS NOT. It says nothing about the SERVER. The server is built and
# tested on every host, unconditionally, and no bridge has an opinion about it
# (spec 0042, decision 1). It is also not a dispatcher: no task is generated
# from these declarations while there is exactly one bridge to design against.

from __future__ import annotations

import argparse
import os
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

from platforms import HOST, supports

ROOT = Path(__file__).resolve().parent.parent
BRIDGES_DIR = ROOT / "bridges"

#: Where a bridge writes its declaration, inside its own pyproject.toml.
DECLARATION = ("tool", "screen-readers-mcp", "bridge")

#: The three tiers, in the order a report should show them, each with the
#: question it answers. A bridge declares the ones it has; anything else it
#: writes is reported as declared but unknown, rather than silently ignored.
TIERS: dict[str, str] = {
	"headless": "run its tests",
	"package": "build its shippable artifact",
	"live": "drive the real reader",
}


@dataclass(frozen=True)
class Tier:
	"""One kind of work on one bridge, and where it can be done."""

	name: str
	hosts: tuple[str, ...]
	tools: tuple[str, ...]
	#: Why the hosts are limited, in the bridge's own words. Printed verbatim
	#: when the tier is skipped, so a developer on the wrong host is told the
	#: reason rather than shown a gap.
	reason: str
	#: task name -> the commands that ARE that task for this bridge. Declared by
	#: the bridge because a bridge is not necessarily a uv project: an NVDA
	#: bridge tests with pytest, and a VoiceOver bridge in Go or Swift will not.
	#: Run by scripts/bridge_task.py.
	tasks: dict[str, tuple[str, ...]]

	def runs_here(self) -> bool:
		return supports(self.hosts)

	@property
	def question(self) -> str:
		return TIERS.get(self.name, "an undeclared kind of work")


@dataclass(frozen=True)
class Bridge:
	"""One reader's bridge, as it describes itself."""

	#: The directory name under bridges/, which is how it is named everywhere.
	name: str
	#: The reader it drives, as a person would say it ("NVDA").
	reader: str
	tiers: tuple[Tier, ...]
	path: Path

	def tier(self, name: str) -> Tier | None:
		for tier in self.tiers:
			if tier.name == name:
				return tier
		return None

	def runs_here(self) -> bool:
		"""Is there anything at all to do with this bridge on this machine?"""
		return any(tier.runs_here() for tier in self.tiers)


def _tasks_of(raw: object) -> dict[str, tuple[str, ...]]:
	"""A tier's `tasks` table, each value normalised to a tuple of commands.

	A task is one command or several -- linting is two, check and format-check --
	so a bare string and a list mean the same thing and the caller never has to
	ask which it got.
	"""
	if not isinstance(raw, dict):
		return {}
	out: dict[str, tuple[str, ...]] = {}
	for name, command in raw.items():
		if isinstance(command, str):
			out[str(name)] = (command,)
		elif isinstance(command, list):
			out[str(name)] = tuple(str(part) for part in command)
	return out


def _tiers_of(declared: dict[str, object]) -> tuple[Tier, ...]:
	raw = declared.get("tiers")
	if not isinstance(raw, dict):
		return ()
	out: list[Tier] = []
	for name, body in raw.items():
		if not isinstance(body, dict):
			continue
		hosts = body.get("hosts", ())
		tools = body.get("tools", ())
		reason = body.get("reason", "")
		out.append(
			Tier(
				name=str(name),
				hosts=tuple(str(host) for host in hosts) if isinstance(hosts, list) else (),
				tools=tuple(str(tool) for tool in tools) if isinstance(tools, list) else (),
				reason=str(reason),
				tasks=_tasks_of(body.get("tasks")),
			)
		)
	# Canonical order for anything known, declaration order for the rest, so two
	# bridges always print their tiers in the same sequence.
	order = list(TIERS)
	return tuple(sorted(out, key=lambda tier: order.index(tier.name) if tier.name in order else len(order)))


def _declaration_in(pyproject: Path) -> dict[str, object] | None:
	try:
		data: object = tomllib.loads(pyproject.read_text(encoding="utf-8"))
	except (OSError, tomllib.TOMLDecodeError):
		return None
	for key in DECLARATION:
		if not isinstance(data, dict) or key not in data:
			return None
		data = data[key]
	return data if isinstance(data, dict) else None


def discover() -> list[Bridge]:
	"""Every bridge under bridges/ that declares itself, by directory name."""
	found: list[Bridge] = []
	for directory in sorted(p for p in BRIDGES_DIR.glob("*") if p.is_dir()):
		declared = _declaration_in(directory / "pyproject.toml")
		if declared is None:
			continue
		reader = declared.get("reader")
		found.append(
			Bridge(
				name=directory.name,
				reader=str(reader) if reader else directory.name,
				tiers=_tiers_of(declared),
				path=directory,
			)
		)
	return found


def undeclared() -> list[str]:
	"""Directories under bridges/ with no declaration -- invisible to every check.

	Reported by the doctor rather than ignored: a bridge nobody declared is a
	bridge whose tools are never checked and whose tiers are never skipped with
	a reason, which looks exactly like a bridge that needs nothing.
	"""
	declared = {bridge.name for bridge in discover()}
	return sorted(
		p.name
		for p in BRIDGES_DIR.glob("*")
		if p.is_dir() and p.name not in declared and not p.name.startswith((".", "_"))
	)


class UnknownBridge(Exception):
	"""BRIDGES named something that is not in bridges/."""


def selected() -> list[Bridge]:
	"""The bridges this run is about.

	`BRIDGES=nvda,voiceover` selects exactly those and RAISES on a name that
	does not exist -- a typo that silently selected nothing would report a clean
	machine while checking none of it. With the variable unset, a bridge is
	selected when it can do ANY of its work here, which is what makes a fresh
	macOS checkout pick up a macOS bridge with nothing configured.
	"""
	every = discover()
	wanted = os.environ.get("BRIDGES", "").strip()
	if not wanted:
		return [bridge for bridge in every if bridge.runs_here()]
	by_name = {bridge.name: bridge for bridge in every}
	chosen: list[Bridge] = []
	for name in (part.strip() for part in wanted.split(",")):
		if not name:
			continue
		if name not in by_name:
			known = ", ".join(sorted(by_name)) or "none"
			raise UnknownBridge(f"BRIDGES names {name!r}, which is not a bridge in this repo (have: {known})")
		chosen.append(by_name[name])
	return chosen


# -- CLI ----------------------------------------------------------------------


def _print_table() -> None:
	print(f"host: {HOST}")
	bridges = discover()
	if not bridges:
		print("  no bridges declare themselves under bridges/")
		return
	chosen = {bridge.name for bridge in selected()}
	for bridge in bridges:
		mark = "selected" if bridge.name in chosen else "not selected here"
		print(f"\n  {bridge.name}  ({bridge.reader}) -- {mark}")
		for tier in bridge.tiers:
			hosts = ", ".join(tier.hosts) or "none declared"
			if tier.runs_here():
				tools = f"; needs {', '.join(tier.tools)}" if tier.tools else ""
				tasks = f"  -> poe {', '.join(sorted(tier.tasks))}" if tier.tasks else ""
				print(f"    RUNS  {tier.name:<9} {tier.question} [{hosts}{tools}]{tasks}")
			else:
				why = tier.reason or f"declared for {hosts}"
				print(f"    SKIP  {tier.name:<9} {tier.question} -- {why}")
	for name in undeclared():
		print(f"\n  {name}  -- NO DECLARATION; nothing about it is checked")


def main() -> int:
	argparse.ArgumentParser(description="What each bridge needs, and what runs on this host.").parse_args()
	try:
		_print_table()
	except UnknownBridge as exc:
		print(f"{exc}", file=sys.stderr)
		return 1
	return 0


if __name__ == "__main__":
	sys.exit(main())
