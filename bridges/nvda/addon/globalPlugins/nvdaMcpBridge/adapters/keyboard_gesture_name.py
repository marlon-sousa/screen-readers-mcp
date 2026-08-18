# nvdaMcpBridge adapters -- normalize a wire gesture id to a fromName key combo.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: the pure decision behind NvdaGestureSender. Imports NOTHING from NVDA,
#       so it is fully type-checked and unit-tested (tests/unit/adapters/).
# USED BY: adapters/nvda_gesture_sender.py, before it calls into NVDA.
#
# The wire carries NVDA inputCore gesture identifiers -- "kb:control+l",
# "kb:NVDA+f7", and (layout-qualified) "kb(laptop):NVDA+f7" (protocol.md
# says gesture ids pass through opaquely, NVDA's example being "kb:NVDA+f7").
# But keyboardHandler.KeyboardInputGesture.fromName wants only the BARE key
# combo: it splits on "+" and resolves each token against vkCodes, with no
# notion of a source prefix, so "kb:control" is looked up as a key and raises
# KeyError. The source prefix -- everything up to and including the first ":"
# -- has to come off first.

from __future__ import annotations


def bare_key_name(gesture_id: str) -> str:
	"""Return the fromName key combo for an inputCore keyboard gesture id.

	Strips the source prefix ("kb:" or "kb(layout):") so "kb:NVDA+f7" becomes
	"NVDA+f7". An id with no ":" is already bare and is returned unchanged.
	"""
	return gesture_id.split(":", 1)[1] if ":" in gesture_id else gesture_id


#: The modifier tokens, in the order a person writes them. Everything else in a
#: gesture is the key actually being pressed.
MODIFIERS: tuple[str, ...] = ("nvda", "control", "alt", "shift", "windows")


def press_order(keys: str) -> str:
	"""Reorder a bare key combo so the MAIN KEY IS LAST.

	Needed because ``inputCore.normalizeGestureIdentifier`` sorts a gesture's
	parts ALPHABETICALLY before storing them, so NVDA holds "read the whole
	window" as ``b+nvda`` -- while ``KeyboardInputGesture.fromName`` treats the
	LAST token as the key and every earlier one as a modifier::

		return cls(keys[:-1], vk, 0, ext)

	So pressing ``b+nvda`` presses NVDA with B held down, not NVDA+B. The sorting
	is harmless whenever the key happens to sort after its modifiers (``nvda+t``)
	and wrong whenever it does not (``b+nvda``, ``downarrow+nvda``,
	``numpad5+nvda``) -- which is most of them.

	THE FAILURE IS INVISIBLE WITHOUT THIS. A gesture read back out of NVDA looks
	perfectly well-formed either way; it simply does the wrong thing when pressed.
	That is why spec 0029's guidance tables, which are read out of NVDA and handed
	to an agent to paste into ``pressGesture``, pass through here first.

	A token this function does not recognise is treated as the key, not as a
	modifier: a real modifier missing from the list would otherwise be hoisted to
	the end and pressed as the key, so the list holds exactly the five that exist.
	"""
	parts = [part for part in keys.split("+") if part]
	main = [part for part in parts if part.lower() not in MODIFIERS]
	if not main:
		# All modifiers and no key. NVDA does bind a few (a double-tapped
		# modifier, for one), and there is nothing to hoist -- leave it alone
		# rather than inventing an order for it.
		return keys
	present = {part.lower() for part in parts}
	ordered = [modifier for modifier in MODIFIERS if modifier in present]
	return "+".join(ordered + main)
