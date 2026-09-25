# nvdaMcpBridge adapters -- NvdaTextTyper: inject literal text via SendInput.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing TextTyper with winBindings.user32.SendInput, as NVDA Remote does.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the Session, answering typeText.
# Typing bypasses NVDA on purpose: SendInput reaches the focused application, where emulateGesture would
# be processed by NVDA. Each UTF-16 code unit goes as a KEYEVENTF.UNICODE event in wScan, which is
# layout-independent. Injection runs on NVDA's main thread and blocks until done; SendInput inserting fewer
# events than requested is a TypingError.

from __future__ import annotations

import ctypes
import struct
import threading

import wx
from winBindings import user32

from ..domain.ports.text_typer import TextTyper, TypingError

DEFAULT_TYPE_TIMEOUT: float = 10.0


class NvdaTextTyper(TextTyper):
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
	"""A character outside the BMP is two code units, sent as two consecutive events."""
	encoded = text.encode("utf-16-le")
	return struct.unpack(f"<{len(encoded) // 2}H", encoded)


def _send_unicode_event(code_unit: int, *, key_up: bool) -> None:
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
