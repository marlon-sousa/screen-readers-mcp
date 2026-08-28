# Run one task for every bridge that is selected and can actually do it here.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     python scripts/bridge_task.py test          # every selected bridge's tests
#     python scripts/bridge_task.py live --require # ...and FAIL if none can
#
# ROLE: the dispatcher behind `poe bridge`, `bridge-types`, `bridge-lint`,
# `sync`, `build-bridge`, `live` and `live-slow`. Each of those used to name
# `bridges/nvda` in its command string, which made "the NVDA bridge" and "a
# bridge" the same thing -- so on a host where NVDA's work cannot be done, the
# task ran anyway and reported on nothing.
#
# WHAT A TASK IS, IS THE BRIDGE'S TO SAY. The commands live in the bridge's own
# pyproject.toml, per tier, because a bridge is not necessarily a uv project: the
# NVDA bridge tests with pytest under uv, and a VoiceOver bridge written in Go or
# Swift will not. This file knows how to SELECT and how to REPORT; it knows
# nothing about pytest.
#
# WHY --require EXISTS, and why it is not the default: `poe live` must REFUSE on
# a host with no live tier, because silently doing nothing there reads exactly
# like a pass. `poe bridge-types` must NOT refuse -- if you are not working that
# bridge on this machine, there is nothing to type-check and that is a success,
# not a failure. Spec 0042.

from __future__ import annotations

import argparse
import shlex
import subprocess
import sys
from pathlib import Path

from platforms import HOST

from bridges import Bridge, Tier, UnknownBridge, selected

ROOT = Path(__file__).resolve().parent.parent


def _tier_with(bridge: Bridge, task: str) -> Tier | None:
	for tier in bridge.tiers:
		if task in tier.tasks:
			return tier
	return None


def _run(command: str) -> int:
	"""One declared command, from the repo root, with its output left alone.

	Not through a shell: these are plain argument vectors, and a shell would make
	the declaration's meaning depend on which shell the host has. `shlex` keeps
	the quoting that a pytest `-m 'live_nvda and not slow'` needs.
	"""
	print(f"  $ {command}", flush=True)
	try:
		return subprocess.call(shlex.split(command), cwd=ROOT)
	except OSError as exc:
		print(f"  could not run it: {exc}", file=sys.stderr)
		return 1


def main() -> int:
	parser = argparse.ArgumentParser(description="Run one task for each selected bridge.")
	parser.add_argument("task", help="the task name a bridge's tier declares (test, types, lint, ...)")
	parser.add_argument(
		"--require",
		action="store_true",
		help="fail when no selected bridge can do this task here, instead of doing nothing",
	)
	args = parser.parse_args()

	try:
		chosen = selected()
	except UnknownBridge as exc:
		print(exc, file=sys.stderr)
		return 1

	ran = 0
	failed = 0
	for bridge in chosen:
		tier = _tier_with(bridge, args.task)
		if tier is None:
			continue
		if not tier.runs_here():
			why = tier.reason or f"its {tier.name} tier is declared for {', '.join(tier.hosts) or 'no host'}"
			print(f"  SKIP {bridge.name}: {why}")
			continue
		for command in tier.tasks[args.task]:
			ran += 1
			if _run(command) != 0:
				failed += 1
	if failed:
		return 1
	if ran == 0:
		names = ", ".join(bridge.name for bridge in chosen) or "none"
		message = f"no bridge does '{args.task}' on {HOST} (selected: {names})"
		if args.require:
			# After the SKIP lines above, not before them: flushing first keeps the
			# summary under its own evidence when stdout and stderr are interleaved.
			sys.stdout.flush()
			print(f"{message} -- run `uv run poe bridges` to see what does", file=sys.stderr)
			return 1
		print(f"  nothing to do: {message}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
