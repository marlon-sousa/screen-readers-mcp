# nvdaMcpBridge tests -- FakeTextTyper, standing in for the TextTyper port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/text_typer.py
#
# Records the strings it was asked to type, in order. ``fail_on`` names a
# string that raises TypingError instead of being recorded, to drive
# TypeTextHandler's error path exactly as FakeGestureSender's ``reject`` drives
# PressGestureHandler's.

from __future__ import annotations

from typing import Sequence

from nvdaMcpBridge.domain.ports.text_typer import TextTyper, TypingError


class FakeTextTyper(TextTyper):
	"""Records typed strings; optionally rejects a configured input."""

	def __init__(self, *, fail_on: Sequence[str] | None = None) -> None:
		self._fail_on = set(fail_on or ())
		self.typed: list[str] = []

	def type_text(self, text: str) -> None:
		if text in self._fail_on:
			raise TypingError(f"typing failed: {text!r}")
		self.typed.append(text)
