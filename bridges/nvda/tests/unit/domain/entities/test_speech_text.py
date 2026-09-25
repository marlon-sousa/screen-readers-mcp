# Unit tests for domain/entities/speech_text.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge.domain.entities.speech_text import join_speech


def test_keeps_only_the_string_parts() -> None:
	# NVDA interleaves SpeechCommand objects with the spoken strings.
	assert join_speech(["say", object(), "this", 42]) == "say this"


def test_adjacent_string_parts_are_separated_by_a_space() -> None:
	# Real NVDA parts carry no trailing spaces: a Windows menu item arrives as label, state, accelerator.
	assert join_speech(["Move", "indisponível", "m"]) == "Move indisponível m"


def test_whitespace_only_parts_do_not_produce_double_spaces() -> None:
	assert join_speech(["Google Chrome", " ", "17 de 37"]) == "Google Chrome 17 de 37"


def test_an_empty_sequence_is_an_empty_string() -> None:
	assert join_speech([]) == ""


def test_a_sequence_of_only_commands_is_an_empty_string() -> None:
	assert join_speech([object(), object()]) == ""


def test_a_non_sequence_is_an_empty_string() -> None:
	assert join_speech(None) == ""
	assert join_speech("not a sequence") == ""
