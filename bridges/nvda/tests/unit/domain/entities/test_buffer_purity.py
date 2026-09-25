# Architecture check: the capture buffers never learn the journal exists.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# The journal position must reach a buffer as a plain integer from the capture adapter. That is not
# a behavioural property, so this checks the source's imports and names.

from __future__ import annotations

import ast
from pathlib import Path

import pytest

ENTITIES = (
	Path(__file__).resolve().parents[4] / "addon" / "globalPlugins" / "nvdaMcpBridge" / "domain" / "entities"
)

BUFFERS = ("indexed_buffer.py", "speech_buffer.py", "braille_buffer.py")

FORBIDDEN = ("log_journal", "LogJournal", "log_capture", "LogCapture")


def _imported_names(source: str) -> set[str]:
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
	tree = ast.parse((ENTITIES / filename).read_text(encoding="utf-8"))
	mentioned = {
		node.attr if isinstance(node, ast.Attribute) else node.id
		for node in ast.walk(tree)
		if isinstance(node, (ast.Attribute, ast.Name))
	}
	forbidden = mentioned & set(FORBIDDEN)
	assert not forbidden, f"{filename} references {sorted(forbidden)} in its code"


def test_the_check_would_actually_fail_on_a_violation() -> None:
	assert "log_journal" in _imported_names("from ..entities.log_journal import LogJournal")
	assert "LogJournal" in _imported_names("from ..entities.log_journal import LogJournal")
	assert "log_capture" in _imported_names("import nvdaMcpBridge.domain.ports.log_capture")
