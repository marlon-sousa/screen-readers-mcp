# Unit tests for adapters/keyboard_gesture_name.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest

from nvdaMcpBridge.adapters.keyboard_gesture_name import bare_key_name


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
