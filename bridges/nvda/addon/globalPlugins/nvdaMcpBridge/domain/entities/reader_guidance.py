# nvdaMcpBridge domain -- ReaderGuidance: what NVDA says about holding a stance.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: entity. Composes the document `getGuidance` returns: NVDA's common
#       section, plus the section for the session's persona, as one markdown text.
# READ BY: domain/controllers/commands/get_guidance.py, and nothing else.
# DEPENDS ON: the .md files in documents/, and the standard library. No NVDA.
#
# Spec 0029 Part 4. THE SERVER STATES THE RULE AND THIS STATES THE INSTANCES, and
# that split is the whole design: the rule ("a command that re-reads what is
# already there is in; a command that reaches what focus cannot is out") survives
# every platform, and the list ("object navigation is NVDA+numpad6, or
# NVDA+shift+rightArrow on the laptop layout") does not survive even one --
# TalkBack has neither the keyboard nor the operating system such a list assumes.
# So the concrete half ships with the reader it describes, where it cannot rot in
# the one place nobody checks.
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
# Composed ONCE per process and cached: the text never changes while the addon is
# loaded, and NVDA's disk is not the place to go twice for the same bytes.

from __future__ import annotations

from pathlib import Path

#: Where the documents live, beside this module.
_DOCUMENTS = Path(__file__).parent / "documents"

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


def guidance_for(persona: str) -> tuple[str, bool]:
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
	if section is None:
		return _compose(_UNKNOWN), False
	return _compose(section), True


def _compose(section: str) -> str:
	"""The common half, then the persona's half, as one markdown document."""
	return f"{_read(_COMMON)}\n{_read(section)}"


def _read(name: str) -> str:
	"""Read one document, cached for the process's lifetime."""
	if name not in _cache:
		path = _DOCUMENTS / name
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
#: because the documents are process-wide constants, exactly like the text they
#: hold: nothing here is per session.
_cache: dict[str, str] = {}
