# Unit tests for domain/controllers/commands/get_guidance.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Spec 0029 Part 4. Two things are worth testing about a handler that returns
# prose, and neither is the prose: that EVERY persona gets the common section --
# including one this bridge has never heard of, which must degrade rather than
# error -- and that the answer is for the SESSION's persona and no other.

from __future__ import annotations

from fakes.clock import FakeClock
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.controllers.commands.get_guidance import GetGuidanceHandler
from support.context import make_context, request

#: A phrase from common.md that no persona section repeats. Asserting on a
#: heading rather than a sentence, so rewording the document does not fail this
#: while deleting the section does.
COMMON_MARKER = "The ordinary vocabulary on this reader"


def _guidance(clock: FakeClock, persona: str) -> p.GetGuidanceResult:
	ctx = make_context(clock)
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


def test_names_the_gestures_a_restricted_stance_must_not_reach_for(clock: FakeClock) -> None:
	# The point of this document's existing at all: the server states the RULE
	# and cannot state the instances, because they are keystrokes on NVDA and
	# touch gestures elsewhere. If the boundary stops being named in gestures,
	# a `user` session has no way to recognise what it must not press.
	text = _guidance(clock, "user").text

	for gesture in ("NVDA+numpad6", "NVDA+shift+rightArrow", "numpadDivide"):
		assert gesture in text, gesture


def test_does_not_mark_a_log_window(clock: FakeClock) -> None:
	# It reads a file the addon shipped and touches nothing NVDA logs, so a
	# window for it would be empty and would push a real one out of the last
	# fifty (spec 0020).
	assert GetGuidanceHandler().marks_log is False
