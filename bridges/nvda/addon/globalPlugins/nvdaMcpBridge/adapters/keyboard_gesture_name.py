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
