# Unit tests for adapters/keyboard_gesture_name.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from nvdaMcpBridge.adapters.keyboard_gesture_name import bare_key_name, press_order


@pytest.mark.parametrize(
	("gesture_id", "expected"),
	[
		# The prefix comes off so fromName sees a combo it can resolve. Before
		# the fix these all reached fromName with "kb:" attached and raised
		# KeyError on the first token -- pressGesture never worked over the wire.
		("kb:control+l", "control+l"),
		("kb:NVDA+f7", "NVDA+f7"),  # the modifier NVDA's own protocol.md example uses
		("kb:windows+d", "windows+d"),  # fromName maps "windows" to VK_WIN
		("kb:escape", "escape"),
		("kb(laptop):NVDA+f7", "NVDA+f7"),  # layout-qualified source prefix
	],
)
def test_strips_the_inputcore_source_prefix(gesture_id: str, expected: str) -> None:
	assert bare_key_name(gesture_id) == expected


def test_leaves_a_bare_combo_untouched() -> None:
	# Defensive: an id with no source prefix is already what fromName wants.
	assert bare_key_name("control+l") == "control+l"


# -- press_order: the main key must come LAST (spec 0029) ---------------------
#
# NVDA stores gesture identifiers with their parts sorted alphabetically, and
# KeyboardInputGesture.fromName reads the LAST token as the key. Every case below
# is a real binding read out of a live NVDA while building the guidance tables.


def test_hoists_the_main_key_past_a_sorted_modifier() -> None:
	# "read the whole window" -- NVDA+B, stored as b+nvda. Unfixed, this presses
	# NVDA with B held, which is a different thing entirely and fails silently.
	assert press_order("b+nvda") == "nvda+b"
	assert press_order("downarrow+nvda") == "nvda+downarrow"
	assert press_order("numpad5+nvda") == "nvda+numpad5"
	assert press_order("7+nvda") == "nvda+7"


def test_leaves_an_already_correct_combo_alone() -> None:
	# The cases that made the bug hard to see: these were right by luck, because
	# the key sorts after its modifiers.
	assert press_order("nvda+tab") == "nvda+tab"
	assert press_order("nvda+t") == "nvda+t"


def test_orders_several_modifiers_consistently() -> None:
	assert press_order("nvda+numpadminus+shift") == "nvda+shift+numpadminus"
	assert press_order("alt+home+nvda") == "nvda+alt+home"
	assert press_order("f+nvda+shift") == "nvda+shift+f"


def test_a_gesture_of_only_modifiers_is_left_exactly_as_bound() -> None:
	# There is no main key to hoist, so inventing an order for one would be
	# making something up about a binding we do not understand.
	assert press_order("nvda+shift") == "nvda+shift"


def test_an_unknown_token_is_treated_as_the_key_not_a_modifier() -> None:
	# The safe default: a modifier missing from the list would be hoisted to the
	# end and pressed AS the key, so unknown tokens must land in the key slot
	# where a wrong answer is obvious rather than silent.
	assert press_order("nvda+someNewKey") == "nvda+someNewKey"


def test_a_bare_key_survives_untouched() -> None:
	assert press_order("numpad8") == "numpad8"
	assert press_order("escape") == "escape"
