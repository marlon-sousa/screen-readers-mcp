# The bridge registry: what each bridge needs, and which of it can be done here.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe bridges                      what runs where, on this machine
#     BRIDGES=nvda uv run poe doctor          narrow to one bridge deliberately
#
# ROLE: reads the declaration each bridge writes in its own pyproject.toml and says which bridges
# and tiers can run on this machine.
# USED BY: doctor.py, bridge_task.py, and the `bridges` task as a CLI.

from __future__ import annotations

import argparse
import os
import shutil
import sys
import tomllib
from dataclasses import dataclass
from pathlib import Path

from platforms import HOST, supports

ROOT = Path(__file__).resolve().parent.parent
BRIDGES_DIR = ROOT / "bridges"

DECLARATION = ("tool", "screen-readers-mcp", "bridge")

TIERS: dict[str, str] = {
	"headless": "run its tests",
	"package": "build its shippable artifact",
	"live": "drive the real reader",
}


@dataclass(frozen=True)
class Tier:
	name: str
	hosts: tuple[str, ...]
	tools: tuple[str, ...]
	#: Printed verbatim when the tier is skipped.
	reason: str
	tasks: dict[str, tuple[str, ...]]

	def runs_here(self) -> bool:
		return supports(self.hosts)

	def missing_tools(self) -> tuple[str, ...]:
		return tuple(tool for tool in self.tools if shutil.which(tool) is None)

	@property
	def question(self) -> str:
		return TIERS.get(self.name, "an undeclared kind of work")


@dataclass(frozen=True)
class Bridge:
	name: str
	reader: str
	tiers: tuple[Tier, ...]
	path: Path

	def tier(self, name: str) -> Tier | None:
		for tier in self.tiers:
			if tier.name == name:
				return tier
		return None

	def runs_here(self) -> bool:
		return any(tier.runs_here() for tier in self.tiers)


def _tasks_of(raw: object) -> dict[str, tuple[str, ...]]:
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
	declared = {bridge.name for bridge in discover()}
	return sorted(
		p.name
		for p in BRIDGES_DIR.glob("*")
		if p.is_dir() and p.name not in declared and not p.name.startswith((".", "_"))
	)


class UnknownBridge(Exception):
	"""BRIDGES named something that is not in bridges/."""


def selected() -> list[Bridge]:
	"""Raises on an unknown name in BRIDGES; with it unset, every bridge with a tier that runs here."""
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
