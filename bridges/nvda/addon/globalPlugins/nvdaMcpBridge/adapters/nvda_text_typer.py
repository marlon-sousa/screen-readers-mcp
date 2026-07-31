# nvdaMcpBridge adapters -- NvdaTextTyper: inject literal text via SendInput.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the TextTyper port. On pyright's ignore list
#       (imports NVDA's winBindings.user32); validated by the E.3 live-NVDA
#       checklist.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the Session, answering typeText.
#
# NVDA has no `typeString` -- it is a screen reader, not an automation harness.
# What it DOES ship is NVDA Remote's own primitive: `_remoteClient/input.sendKey`
# drives `winBindings.user32.SendInput` with NVDA's own INPUT/KEYEVENTF
# bindings. This reuses those bindings (already on pyright's ignore list, and
# already validated by NVDA's own Remote feature) rather than a hand-rolled
# ctypes layer, looped over the string instead of one key.
#
# TYPING BYPASSES NVDA ON PURPOSE -- the opposite of a gesture. pressGesture
# goes through inputCore.manager.emulateGesture, so NVDA PROCESSES it; typeText
# must instead reach the focused APPLICATION, so it uses raw SendInput exactly
# as Remote does, never emulateGesture.
#
# Per UTF-16 code unit: a key-down then key-up INPUT with KEYEVENTF.UNICODE set
# and the code unit in wScan (wVk = 0). This is layout-independent -- the code
# unit IS the character, not a scan code to be re-mapped -- and covers
# characters outside the BMP, where a surrogate pair is two consecutive
# Unicode events (Python's utf-16-le codec already splits one that way).
#
# Injection is marshaled onto NVDA's main thread and blocks until done,
# mirroring NvdaGestureSender's wx.CallAfter + threading.Event with the same
# generous timeout, so "the call returned" means "the text reached the
# control". SendInput inserting fewer events than requested (another thread
# holds the input desktop) becomes a TypingError -- a per-command failure the
# Session reports, not a session death.

from __future__ import annotations

import ctypes
import struct
import threading

import wx
from winBindings import user32

from ..domain.ports.text_typer import TextTyper, TypingError

#: Upper bound on how long type_text() waits for the main thread to finish
#: injecting the whole string before giving up -- generous, since it only
#: trips on a wedged UI (the same value NvdaGestureSender uses for one key).
DEFAULT_TYPE_TIMEOUT: float = 10.0


class NvdaTextTyper(TextTyper):
	"""Injects literal text on NVDA's main thread via SendInput, and blocks until done."""

	def __init__(self, *, timeout: float = DEFAULT_TYPE_TIMEOUT) -> None:
		self._timeout = timeout

	def type_text(self, text: str) -> None:
		units = _utf16_code_units(text)

		done = threading.Event()
		failure: list[BaseException] = []

		def _inject() -> None:
			try:
				for unit in units:
					_send_unicode_event(unit, key_up=False)
					_send_unicode_event(unit, key_up=True)
			except Exception as exc:
				failure.append(exc)
			finally:
				done.set()

		wx.CallAfter(_inject)
		if not done.wait(self._timeout):
			raise TypingError(f"typing {len(text)} character(s) timed out after {self._timeout}s")
		if failure:
			raise TypingError(f"typing {len(text)} character(s) failed: {failure[0]}") from failure[0]


def _utf16_code_units(text: str) -> tuple[int, ...]:
	"""The UTF-16LE code units of ``text``, one SendInput event pair per unit.

	Not one event per Python character: a character outside the BMP is one
	``str`` code point but two UTF-16 code units, and Python's ``utf-16-le``
	codec already encodes it as a surrogate pair -- which is exactly the two
	consecutive Unicode events SendInput expects.
	"""
	encoded = text.encode("utf-16-le")
	return struct.unpack(f"<{len(encoded) // 2}H", encoded)


def _send_unicode_event(code_unit: int, *, key_up: bool) -> None:
	"""One KEYEVENTF.UNICODE SendInput event carrying ``code_unit`` in wScan.

	wVk is left 0: the code unit IS the character, never a virtual key to be
	resolved through the active keyboard layout, which is what makes this
	layout-independent where KeyboardInputGesture.fromName is not.
	"""
	event = user32.INPUT()
	event.type = user32.INPUT_TYPE.KEYBOARD
	event.ii.ki.wVk = 0
	event.ii.ki.wScan = code_unit
	event.ii.ki.dwFlags = user32.KEYEVENTF.UNICODE | (user32.KEYEVENTF.KEYUP if key_up else 0)
	inserted = user32.SendInput(1, ctypes.byref(event), ctypes.sizeof(user32.INPUT))
	if inserted != 1:
		raise TypingError(
			f"SendInput inserted {inserted} of 1 event for code unit {code_unit:#06x} "
			"(another process may hold the input desktop)"
		)
