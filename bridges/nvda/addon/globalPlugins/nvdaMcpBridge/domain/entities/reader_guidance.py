# nvdaMcpBridge domain -- ReaderGuidance: what NVDA says about holding a stance.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity, composing the `getGuidance` document from NVDA's common and persona sections,
# with gesture tables resolved from the reader.
# READ BY: domain/controllers/commands/get_guidance.py.
# The documents must be listed in buildVars.bundledDataSources, or scons ships a stale copy of an edited one.

from __future__ import annotations

import re
from pathlib import Path
from typing import TYPE_CHECKING

from ..ports.gesture_resolver import ALL_GROUPS

if TYPE_CHECKING:
	from ..ports.gesture_resolver import GestureResolver, ResolvedCommand

# Public so a test can check every marker in the documents names a known group.
DOCUMENTS = Path(__file__).parent / "documents"

_COMMON = "common.md"

_SECTIONS = {
	"user": "user.md",
	"validator": "validator.md",
	"expert": "expert.md",
}

_UNKNOWN = "unknown.md"

_MARKER = re.compile(r"\{\{gestures:([a-z-]+)\}\}")

KNOWN_GROUPS = ALL_GROUPS


def guidance_for(persona: str, resolver: GestureResolver) -> tuple[str, bool]:
	"""``recognised`` is False for a persona with no section, an ordinary outcome that still gets the
	common section and an explanation. An empty persona takes the same path.
	"""
	section = _SECTIONS.get(persona)
	recognised = section is not None
	return _compose(section or _UNKNOWN, resolver), recognised


def _compose(section: str, resolver: GestureResolver) -> str:
	document = f"{_read(_COMMON)}\n{_read(section)}"
	return _fill_tables(document, resolver)


def _fill_tables(document: str, resolver: GestureResolver) -> str:
	"""Asks the resolver once per document, so two halves cannot straddle a configuration change."""
	if not _MARKER.search(document):
		return document
	resolved = resolver.resolve()
	return _MARKER.sub(lambda match: _table(resolved.get(match.group(1), [])), document)


def _table(commands: list[ResolvedCommand]) -> str:
	if not commands:
		# Never blank: an empty table would claim the group has nothing in it.
		return (
			"*This reader could not be asked what is bound here. Do not fall back on "
			"the published defaults -- treat every command in this group as though it "
			"were bound, and say in your report that you could not confirm it.*"
		)

	rows = ["| What it does | Command | Press |", "|---|---|---|"]
	for command in commands:
		if command.gestures:
			keys = ", ".join(f"`{gesture}`" for gesture in command.gestures)
		else:
			keys = "*nothing is bound to it on this machine*"
		rows.append(f"| {command.name} | `{command.script}` | {keys} |")
	return "\n".join(rows)


def _read(name: str) -> str:
	if name not in _cache:
		path = DOCUMENTS / name
		try:
			_cache[name] = path.read_text(encoding="utf-8")
		except OSError as exc:
			# A packaging fault; an empty document would read as "this reader has nothing to say".
			raise RuntimeError(f"the bridge's guidance document {name!r} is missing from {path}") from exc
	return _cache[name]


# Only the files are cached: the tables depend on bindings, which a configuration profile can change.
_cache: dict[str, str] = {}
