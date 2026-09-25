# nvdaMcpBridge adapters -- normalize a wire gesture id to a fromName key combo.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: the pure gesture-id normalisation behind NvdaGestureSender.
# USED BY: adapters/nvda_gesture_sender.py.

from __future__ import annotations


def bare_key_name(gesture_id: str) -> str:
	"""KeyboardInputGesture.fromName in NVDA 2026.1 raises KeyError on a source prefix such as "kb:"."""
	return gesture_id.split(":", 1)[1] if ":" in gesture_id else gesture_id


MODIFIERS: tuple[str, ...] = ("nvda", "control", "alt", "shift", "windows")


def press_order(keys: str) -> str:
	"""Move the main key last.

	NVDA 2026.1 stores a gesture's parts sorted alphabetically (``b+nvda``), but fromName presses the
	last token as the key and every earlier one as a modifier, so an unsorted gesture presses the wrong key.
	"""
	parts = [part for part in keys.split("+") if part]
	main = [part for part in parts if part.lower() not in MODIFIERS]
	if not main:
		return keys
	present = {part.lower() for part in parts}
	ordered = [modifier for modifier in MODIFIERS if modifier in present]
	return "+".join(ordered + main)
