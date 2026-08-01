# Architecture check: the capture buffers never learn the journal exists.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Spec 0021's item 14. The buffers gained a journal COORDINATE, and the whole
# design rests on that coordinate arriving as a plain integer: the speech and
# braille source adapters read the position at the moment of capture and hand it
# to append(). If a buffer ever reaches for the journal itself -- imports it,
# takes it as a collaborator, calls position() -- it stops being a pure entity
# and starts being a controller, and the "two records, two audiences" separation
# the spec argues for collapses into one coupled thing.
#
# That is not a behavioural property, so no behavioural test can catch it: a
# buffer that imported LogJournal and used it correctly would pass every other
# test in this directory while being architecturally wrong. Hence a check on the
# SOURCE, walking the real import graph rather than grepping for a name -- an
# indirect import through a helper module would slip past a grep.

from __future__ import annotations

import ast
from pathlib import Path

import pytest

#: The three files that make up the buffer half of the domain.
ENTITIES = (
	Path(__file__).resolve().parents[4] / "addon" / "globalPlugins" / "nvdaMcpBridge" / "domain" / "entities"
)

BUFFERS = ("indexed_buffer.py", "speech_buffer.py", "braille_buffer.py")

#: What a buffer must never reach for. The journal is the log's record; a buffer
#: is the ring's. They meet at an integer and nowhere else.
FORBIDDEN = ("log_journal", "LogJournal", "log_capture", "LogCapture")


def _imported_names(source: str) -> set[str]:
	"""Every module and symbol name the file imports, however it spells it."""
	names: set[str] = set()
	for node in ast.walk(ast.parse(source)):
		if isinstance(node, ast.Import):
			for alias in node.names:
				names.update(alias.name.split("."))
		elif isinstance(node, ast.ImportFrom):
			if node.module:
				names.update(node.module.split("."))
			for alias in node.names:
				names.add(alias.name)
	return names


@pytest.mark.parametrize("filename", BUFFERS)
def test_a_buffer_does_not_import_the_journal(filename: str) -> None:
	imported = _imported_names((ENTITIES / filename).read_text(encoding="utf-8"))
	forbidden = imported & set(FORBIDDEN)
	assert not forbidden, (
		f"{filename} imports {sorted(forbidden)}; the journal position must arrive "
		"as a value from the capture adapter (spec 0021), or the buffer has stopped "
		"being a pure entity"
	)


@pytest.mark.parametrize("filename", BUFFERS)
def test_a_buffer_does_not_name_the_journal_in_its_code(filename: str) -> None:
	# Belt and braces for the case an import never happens because the journal was
	# passed in and stashed: any ATTRIBUTE or NAME mentioning it is equally wrong.
	tree = ast.parse((ENTITIES / filename).read_text(encoding="utf-8"))
	mentioned = {
		node.attr if isinstance(node, ast.Attribute) else node.id
		for node in ast.walk(tree)
		if isinstance(node, (ast.Attribute, ast.Name))
	}
	forbidden = mentioned & set(FORBIDDEN)
	assert not forbidden, f"{filename} references {sorted(forbidden)} in its code"


def test_the_check_would_actually_fail_on_a_violation() -> None:
	# A guard that can only pass is not a guard. This proves the walker sees the
	# import shapes the buffers would realistically use to cheat.
	assert "log_journal" in _imported_names("from ..entities.log_journal import LogJournal")
	assert "LogJournal" in _imported_names("from ..entities.log_journal import LogJournal")
	assert "log_capture" in _imported_names("import nvdaMcpBridge.domain.ports.log_capture")
