# nvdaMcpBridge domain -- the TextTyper port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Injects literal text into whatever holds system focus and
# blocks until NVDA's main thread has finished.
# USED BY: the Session controller (answering typeText).
# IMPLEMENTED BY: adapters/nvda_text_typer.py in E.3 (per-code-unit
#                 KEYEVENTF.UNICODE injection via winBindings.user32.SendInput,
#                 the same bindings _remoteClient/input.sendKey uses);
#                 tests/fakes/text_typer.py FakeTextTyper.
#
# TypingError is part of this port's contract, so it lives here: SendInput
# inserting fewer events than requested (another thread holds the input
# desktop) is a normal, per-command failure the Session reports and recovers
# from, not a session-ending fault -- the same shape as GestureError.

from __future__ import annotations

from abc import ABC, abstractmethod


class TypingError(Exception):
	"""Text could not be typed (e.g. SendInput did not accept every event)."""


class TextTyper(ABC):
	"""Injects literal text into the focused control, bypassing NVDA."""

	@abstractmethod
	def type_text(self, text: str) -> None:
		"""Insert ``text`` at the focused control and block until processed.

		Layout-independent Unicode injection, not a gesture -- ``text`` reaches
		the focused APPLICATION, never NVDA's own command processing. Raises
		:class:`TypingError` if the injection did not complete.
		"""
