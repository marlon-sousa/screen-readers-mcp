# nvdaMcpBridge adapters -- NvdaGestureSender: inject a keypress the way NVDA sees one.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing GestureSender.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the Session, answering pressGesture.
# A gesture must be emulated on NVDA's main thread. In NVDA 2026.1 emulateGesture waits for the
# injection to finish, so once _emulate has run the keypress has reached NVDA.
# An unknown key or an emulation failure is a GestureError, which fails the command, not the session.

from __future__ import annotations

import threading

import inputCore
import wx
from keyboardHandler import KeyboardInputGesture

from ..domain.ports.gesture_sender import GestureError, GestureSender
from .keyboard_gesture_name import bare_key_name

DEFAULT_GESTURE_TIMEOUT: float = 10.0


class NvdaGestureSender(GestureSender):
	def __init__(self, *, timeout: float = DEFAULT_GESTURE_TIMEOUT) -> None:
		self._timeout = timeout

	def press(self, gesture_id: str) -> None:
		try:
			gesture = KeyboardInputGesture.fromName(bare_key_name(gesture_id))
		except Exception as exc:
			raise GestureError(f"unknown gesture id {gesture_id!r}: {exc}") from exc

		done = threading.Event()
		failure: list[BaseException] = []

		def _emulate() -> None:
			try:
				inputCore.manager.emulateGesture(gesture)
			except Exception as exc:
				failure.append(exc)
			finally:
				done.set()

		wx.CallAfter(_emulate)
		if not done.wait(self._timeout):
			raise GestureError(f"gesture {gesture_id!r} timed out after {self._timeout}s")
		if failure:
			raise GestureError(f"gesture {gesture_id!r} failed: {failure[0]}") from failure[0]
