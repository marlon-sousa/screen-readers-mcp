# Unit tests for domain/controllers/commands/get_guidance.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import re

import pytest
from fakes.clock import FakeClock
from fakes.gesture_resolver import EmptyGestureResolver, FakeGestureResolver
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_guidance import GetGuidanceHandler
from nvdaMcpBridge.domain.entities import reader_guidance
from support.context import make_context, request

#: A heading from common.md that no persona section repeats.
COMMON_MARKER = "The ordinary vocabulary on this reader"


def _guidance(
	clock: FakeClock,
	persona: str,
	resolver: FakeGestureResolver | EmptyGestureResolver | None = None,
) -> p.GetGuidanceResult:
	ctx = make_context(clock, gesture_resolver=resolver)  # type: ignore[arg-type]
	ctx.persona = persona
	result = GetGuidanceHandler().execute(ctx, request("getGuidance"))
	assert isinstance(result, p.GetGuidanceResult)
	return result


def test_answers_for_the_sessions_own_persona(clock: FakeClock) -> None:
	result = _guidance(clock, "validator")
	assert result.persona == "validator"
	assert result.recognised is True
	assert "`validator` stance" in result.text


def test_every_known_persona_gets_its_own_section(clock: FakeClock) -> None:
	for persona in ("user", "validator", "expert"):
		result = _guidance(clock, persona)
		assert result.recognised is True, persona
		assert f"`{persona}` stance" in result.text


def test_the_common_section_is_present_for_every_persona(clock: FakeClock) -> None:
	for persona in ("user", "validator", "expert", "auditor", ""):
		assert COMMON_MARKER in _guidance(clock, persona).text, persona


def test_an_unrecognised_persona_degrades_rather_than_erroring(clock: FakeClock) -> None:
	result = _guidance(clock, "auditor")

	assert result.recognised is False
	assert result.persona == "auditor"
	assert COMMON_MARKER in result.text
	assert "No section for the persona you declared" in result.text


def test_an_absent_persona_takes_the_same_path(clock: FakeClock) -> None:
	result = _guidance(clock, "")

	assert result.recognised is False
	assert result.persona == ""
	assert COMMON_MARKER in result.text


def test_the_tables_are_filled_in_from_the_reader(clock: FakeClock) -> None:
	# Synthetic bindings, so a document that hard-coded NVDA's real defaults would fail here.
	text = _guidance(clock, "user").text

	for gesture in ("fake+next", "fake+review", "fake+click", "fake+focus"):
		assert f"`{gesture}`" in text, gesture


def test_no_marker_survives_into_the_served_document(clock: FakeClock) -> None:
	for persona in ("user", "validator", "expert", "auditor"):
		assert "{{gestures:" not in _guidance(clock, persona).text, persona


def test_every_marker_in_every_document_names_a_known_group() -> None:
	markers: set[str] = set()
	for path in reader_guidance.DOCUMENTS.glob("*.md"):
		markers |= set(re.findall(r"\{\{gestures:([a-z-]+)\}\}", path.read_text(encoding="utf-8")))
	assert markers, "no document asks for a gesture table; the resolver is unused"
	assert markers <= set(reader_guidance.KNOWN_GROUPS), markers


def test_the_reader_is_asked_once_per_document(clock: FakeClock) -> None:
	# Two calls could straddle a configuration profile change and print inconsistent halves.
	resolver = FakeGestureResolver()
	_guidance(clock, "user", resolver)
	assert resolver.calls == 1


def test_a_command_with_nothing_bound_is_reported_as_such(clock: FakeClock) -> None:
	text = _guidance(clock, "user").text
	assert "nothing is bound to it on this machine" in text


def test_a_reader_that_cannot_be_asked_says_so_loudly(clock: FakeClock) -> None:
	text = _guidance(clock, "user", EmptyGestureResolver()).text

	assert "could not be asked what is bound here" in text
	assert "treat every command in this group as though it were bound" in text


def test_does_not_mark_a_log_window() -> None:
	assert GetGuidanceHandler().marks_log is False


def test_a_missing_document_is_loud_rather_than_empty(monkeypatch: pytest.MonkeyPatch) -> None:
	monkeypatch.setattr(reader_guidance, "_cache", {})
	monkeypatch.setattr(reader_guidance, "_COMMON", "no-such-document.md")
	with pytest.raises(RuntimeError, match="missing"):
		reader_guidance.guidance_for("user", FakeGestureResolver())
