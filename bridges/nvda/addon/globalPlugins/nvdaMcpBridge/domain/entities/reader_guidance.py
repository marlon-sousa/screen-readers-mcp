# nvdaMcpBridge domain -- ReaderGuidance: what NVDA says about holding a stance.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. Composes the document `getGuidance` returns: NVDA's common
#       section, plus the section for the session's persona, as one markdown
#       text -- with the gesture tables filled in FROM THE READER.
# READ BY: domain/controllers/commands/get_guidance.py, and nothing else.
# DEPENDS ON: the .md files in documents/, the GestureResolver port, and the
#             standard library. No NVDA.
#
# Spec 0029 Part 4. THE SERVER STATES THE RULE AND THIS STATES THE INSTANCES,
# and that split is the whole design: the rule ("a command that re-reads what is
# already there is in; a command that reaches what focus cannot is out") survives
# every platform, and the list ("object navigation is whatever this machine has
# it bound to") does not survive even one -- TalkBack has neither the keyboard
# nor the operating system such a list assumes. So the concrete half ships with
# the reader it describes, where it cannot rot in the one place nobody checks.
#
# THE PROSE IS WRITTEN AND THE TABLES ARE RESOLVED. Each document may carry
# `{{gestures:<group>}}` markers; each is replaced with a table of what is bound
# to that group's commands on this machine, right now, read from the reader
# itself. The first version of this file hard-coded NVDA's DEFAULTS, transcribed
# from its source, and that was wrong in the unsafe direction -- see
# ports/gesture_resolver.py, which states the argument in full. In one line: a
# remapped gesture does not fail, it quietly does something else, so a document
# that assumes the defaults tells a `user` session to avoid a key that is now
# harmless and says nothing about the key that now reaches past focus.
#
# THE DOCUMENTS ARE .md FILES READ AT RUN TIME, which is the same rule the server
# follows (AGENTS.md invariant 9) reaching the opposite mechanism: Go embeds them
# into the binary at compile time, and Python has no compile step to embed
# anything into, so they ship inside the .nvda-addon and are read from disk on
# first use. Two consequences worth knowing:
#
#   * They must be in buildVars.bundledDataSources, or scons will not treat an
#     edited document as a reason to rebuild the addon and the packaged text goes
#     stale silently. That is this mechanism's version of the trap //go:embed has
#     on the other side.
#   * A missing file is a RUNTIME failure here where it is a compile error there.
#     _read below turns it into a clear one rather than an empty document, and
#     the unit tests read every document through this module.
#
# The FILES are cached for the process; the TABLES are not, because the bindings
# they report can change under a configuration profile.

from __future__ import annotations

import re
from pathlib import Path
from typing import TYPE_CHECKING

from ..ports.gesture_resolver import ALL_GROUPS

if TYPE_CHECKING:
	from ..ports.gesture_resolver import GestureResolver, ResolvedCommand

#: Where the documents live, beside this module. PUBLIC, because a test reads
#: the documents themselves through it -- checking that every gesture marker they
#: carry names a group the port actually answers for.
DOCUMENTS = Path(__file__).parent / "documents"

#: The section every persona gets: NVDA's vocabulary, the desktop's keys, its
#: reading commands, and where the boundary falls on this reader.
_COMMON = "common.md"

#: One file per persona the SERVER can currently declare. A value absent from
#: this map is not an error -- see guidance_for.
_SECTIONS = {
	"user": "user.md",
	"validator": "validator.md",
	"expert": "expert.md",
}

#: What an unrecognised persona gets instead of a section: an explanation, so the
#: agent knows what it is missing rather than silently believing it was
#: instructed.
_UNKNOWN = "unknown.md"

#: `{{gestures:object-navigation}}` -- a table to be filled in from the reader.
_MARKER = re.compile(r"\{\{gestures:([a-z-]+)\}\}")

#: Re-exported so a document's markers and the port's groups cannot drift: a
#: test asserts every marker in every document names one of these.
KNOWN_GROUPS = ALL_GROUPS


def guidance_for(persona: str, resolver: GestureResolver) -> tuple[str, bool]:
	"""Return ``(text, recognised)`` -- NVDA's guidance for *persona*.

	``recognised`` is False for a persona this bridge has no section for, which
	is an ORDINARY OUTCOME and never an error: the set of personas belongs to the
	server and can grow, and a bridge that refused an unfamiliar one would make
	adding a persona a synchronised release across every bridge in the field
	(``specs/wire/v1/protocol.md`` §4). Such a caller still gets the common
	section, which is the larger half of what it needed, plus a paragraph saying
	what is missing.

	An empty ``persona`` -- a server predating spec 0029 -- takes the same path,
	deliberately: from this side "I do not know that stance" and "you named no
	stance" call for the same document.
	"""
	section = _SECTIONS.get(persona)
	recognised = section is not None
	return _compose(section or _UNKNOWN, resolver), recognised


def _compose(section: str, resolver: GestureResolver) -> str:
	"""The common half, then the persona's half, with the tables filled in."""
	document = f"{_read(_COMMON)}\n{_read(section)}"
	return _fill_tables(document, resolver)


def _fill_tables(document: str, resolver: GestureResolver) -> str:
	"""Replace every ``{{gestures:<group>}}`` marker with what the reader reports.

	The resolver is asked ONCE per document even when several markers appear: the
	answer describes one instant, so two calls could straddle a configuration
	change and print two mutually inconsistent halves of the same page.
	"""
	if not _MARKER.search(document):
		return document
	resolved = resolver.resolve()
	return _MARKER.sub(lambda match: _table(resolved.get(match.group(1), [])), document)


def _table(commands: list[ResolvedCommand]) -> str:
	"""Render one group as a markdown table of command against gesture."""
	if not commands:
		# Said out loud rather than left blank. An empty space where a table
		# belongs reads as "there is nothing in this group", which is a much
		# stronger claim, and quite possibly a false one.
		return (
			"*This reader could not be asked what is bound here. Do not fall back on "
			"the published defaults -- treat every command in this group as though it "
			"were bound, and say in your report that you could not confirm it.*"
		)

	# THREE COLUMNS, and the middle one earns its place. The description is the
	# reader's own string and is therefore in the reader's language; the command
	# id is stable across languages AND across machines, so it is the thing a
	# finding should name. "Object navigation reached it" is portable; "numpad6
	# reached it" is a fact about one keyboard.
	rows = ["| What it does | Command | Press |", "|---|---|---|"]
	for command in commands:
		if command.gestures:
			keys = ", ".join(f"`{gesture}`" for gesture in command.gestures)
		else:
			# Nothing bound is a REAL answer, and a useful one: the command
			# exists, and on this machine it cannot be reached at all.
			keys = "*nothing is bound to it on this machine*"
		rows.append(f"| {command.name} | `{command.script}` | {keys} |")
	return "\n".join(rows)


def _read(name: str) -> str:
	"""Read one document, cached for the process's lifetime."""
	if name not in _cache:
		path = DOCUMENTS / name
		try:
			_cache[name] = path.read_text(encoding="utf-8")
		except OSError as exc:
			# Loud rather than empty. This means the addon was packaged without
			# its documents -- a build fault, not a session fault -- and an empty
			# document would read to the agent as "this reader has nothing to
			# say", which is a very different and much worse answer.
			raise RuntimeError(f"the bridge's guidance document {name!r} is missing from {path}") from exc
	return _cache[name]


#: Filled by _read on first use. Module level rather than a class attribute
#: because the DOCUMENTS are process-wide constants; the tables composed into
#: them are not, which is why nothing caches the composed result.
_cache: dict[str, str] = {}
