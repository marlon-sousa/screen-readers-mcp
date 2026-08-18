# Unit tests for domain/controllers/commands/get_guidance.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Spec 0029 Part 4. Three things are worth testing about a handler that returns
# prose, and none of them is the prose:
#
#   * every persona gets the common section, INCLUDING one this bridge has never
#     heard of, which must degrade rather than error;
#   * the answer is for the SESSION's persona and no other;
#   * the gesture tables come FROM THE READER. That last one is the point of the
#     whole design, so the fake resolver answers with obviously synthetic keys --
#     a document that hard-coded NVDA's real defaults would pass an assertion
#     looking for "nvda+numpad6" while never having asked the reader at all.

from __future__ import annotations

import re

import pytest
from fakes.clock import FakeClock
from fakes.gesture_resolver import EmptyGestureResolver, FakeGestureResolver
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_guidance import GetGuidanceHandler
from nvdaMcpBridge.domain.entities import reader_guidance
from support.context import make_context, request

#: A phrase from common.md that no persona section repeats. Asserting on a
#: heading rather than a sentence, so rewording the document does not fail this
#: while deleting the section does.
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
	# The set the SERVER can currently declare (spec 0029 Part 2). A persona
	# added upstream without a section here does not break anything -- see the
	# unknown-persona test below -- but it does mean this bridge is silently
	# giving general advice, so the list is checked rather than assumed.
	for persona in ("user", "validator", "expert"):
		result = _guidance(clock, persona)
		assert result.recognised is True, persona
		assert f"`{persona}` stance" in result.text


def test_the_common_section_is_present_for_every_persona(clock: FakeClock) -> None:
	# The larger half of the document does not vary by stance, and it is what
	# makes an unrecognised persona a usable answer rather than a stub.
	for persona in ("user", "validator", "expert", "auditor", ""):
		assert COMMON_MARKER in _guidance(clock, persona).text, persona


def test_an_unrecognised_persona_degrades_rather_than_erroring(clock: FakeClock) -> None:
	# A newer server's fourth persona meeting this bridge. Refusing would make
	# adding a persona a synchronised release across every bridge in the field
	# (protocol.md §4), so this must be an ordinary answer.
	result = _guidance(clock, "auditor")

	assert result.recognised is False
	# Echoed AS RECEIVED, not normalised: the field says what was asked.
	assert result.persona == "auditor"
	assert COMMON_MARKER in result.text
	# And it says so, because silence would leave the agent believing it had
	# been instructed for its stance when it had not.
	assert "No section for the persona you declared" in result.text


def test_an_absent_persona_takes_the_same_path(clock: FakeClock) -> None:
	# A server predating spec 0029 declares nothing. From this side "I do not
	# know that stance" and "you named no stance" call for the same document.
	result = _guidance(clock, "")

	assert result.recognised is False
	assert result.persona == ""
	assert COMMON_MARKER in result.text


# -- the gesture tables come from the reader (the point of the design) ---------


def test_the_tables_are_filled_in_from_the_reader(clock: FakeClock) -> None:
	# The synthetic bindings could only have come through the port. If this ever
	# fails while the document still names plausible NVDA keys, somebody has
	# hard-coded the defaults again.
	text = _guidance(clock, "user").text

	for gesture in ("fake+next", "fake+review", "fake+click", "fake+focus"):
		assert f"`{gesture}`" in text, gesture


def test_no_marker_survives_into_the_served_document(clock: FakeClock) -> None:
	# A marker that reached an agent would be an unsubstituted placeholder read
	# as instruction, which is worse than an empty table.
	for persona in ("user", "validator", "expert", "auditor"):
		assert "{{gestures:" not in _guidance(clock, persona).text, persona


def test_every_marker_in_every_document_names_a_known_group() -> None:
	# The documents and the port cannot drift: a typo'd marker would silently
	# render the "could not be asked" fallback forever.
	markers: set[str] = set()
	for path in reader_guidance.DOCUMENTS.glob("*.md"):
		markers |= set(re.findall(r"\{\{gestures:([a-z-]+)\}\}", path.read_text(encoding="utf-8")))
	assert markers, "no document asks for a gesture table; the resolver is unused"
	assert markers <= set(reader_guidance.KNOWN_GROUPS), markers


def test_the_reader_is_asked_once_per_document(clock: FakeClock) -> None:
	# Several markers, one snapshot. Two calls could straddle a configuration
	# profile change and print two mutually inconsistent halves of one page.
	resolver = FakeGestureResolver()
	_guidance(clock, "user", resolver)
	assert resolver.calls == 1


def test_a_command_with_nothing_bound_is_reported_as_such(clock: FakeClock) -> None:
	# A real state, and a useful answer: the command exists and cannot be
	# reached on this machine. Dropping the row would imply it is not there.
	text = _guidance(clock, "user").text
	assert "nothing is bound to it on this machine" in text


def test_a_reader_that_cannot_be_asked_says_so_loudly(clock: FakeClock) -> None:
	# Silence where a table belongs reads as "this group is empty", which is a
	# much stronger and quite possibly false claim -- and for `user` it is the
	# dangerous direction, since an empty boundary looks like no boundary.
	text = _guidance(clock, "user", EmptyGestureResolver()).text

	assert "could not be asked what is bound here" in text
	assert "treat every command in this group as though it were bound" in text


def test_does_not_mark_a_log_window() -> None:
	# It reads a file the addon shipped and asks NVDA one question, touching
	# nothing NVDA logs, so a window for it would be empty and would push a real
	# one out of the last fifty (spec 0020).
	assert GetGuidanceHandler().marks_log is False


def test_a_missing_document_is_loud_rather_than_empty(monkeypatch: pytest.MonkeyPatch) -> None:
	# An empty document would read to the agent as "this reader has nothing to
	# say" -- a very different answer from "the addon was packaged wrong".
	monkeypatch.setattr(reader_guidance, "_cache", {})
	monkeypatch.setattr(reader_guidance, "_COMMON", "no-such-document.md")
	with pytest.raises(RuntimeError, match="missing"):
		reader_guidance.guidance_for("user", FakeGestureResolver())
