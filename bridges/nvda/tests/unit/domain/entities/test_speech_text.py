# Unit tests for domain/entities/speech_text.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# These moved here from test_speech_buffer.py when spec 0026 extracted the join
# out of the buffer, because the document snapshot needs the identical rule. They
# used to exercise it THROUGH the buffer -- one test module covering its
# neighbour, which the root AGENTS.md warns about -- and the join now has a
# module of its own, so its contract is asserted directly.

from __future__ import annotations

from nvdaMcpBridge.domain.entities.speech_text import join_speech


def test_keeps_only_the_string_parts() -> None:
	# NVDA interleaves SpeechCommand objects with the spoken strings (stand-ins
	# here); only the strings are words.
	assert join_speech(["say", object(), "this", 42]) == "say this"


def test_adjacent_string_parts_are_separated_by_a_space() -> None:
	# The parts carry NO trailing spaces, because real NVDA sequences do not:
	# a Windows menu item arrives as ("Move", "indisponível", "m") -- the label,
	# its state, its accelerator. Concatenating gave "Moveindisponívelm", which
	# no reader can segment. The boundary is known only here, so it is kept here.
	assert join_speech(["Move", "indisponível", "m"]) == "Move indisponível m"


def test_whitespace_only_parts_do_not_produce_double_spaces() -> None:
	assert join_speech(["Google Chrome", " ", "17 de 37"]) == "Google Chrome 17 de 37"


def test_an_empty_sequence_is_an_empty_string() -> None:
	assert join_speech([]) == ""


def test_a_sequence_of_only_commands_is_an_empty_string() -> None:
	# A real case, not a hypothetical: a sequence carrying nothing but an index
	# or a callback says no words at all, and a document line rendered from one
	# must come back empty rather than as stringified command objects.
	assert join_speech([object(), object()]) == ""


def test_a_non_sequence_is_an_empty_string() -> None:
	# Defensive: this is fed by an NVDA edge that is not type-checked, so the
	# entity refuses to guess rather than raising inside a capture hook.
	assert join_speech(None) == ""
	assert join_speech("not a sequence") == ""
