# nvdaMcpBridge tests -- FakeTextTyper, standing in for the TextTyper port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from collections.abc import Sequence

from nvdaMcpBridge.domain.ports.text_typer import TextTyper, TypingError


class FakeTextTyper(TextTyper):
	def __init__(self, *, fail_on: Sequence[str] | None = None) -> None:
		self._fail_on = set(fail_on or ())
		self.typed: list[str] = []

	def type_text(self, text: str) -> None:
		if text in self._fail_on:
			raise TypingError(f"typing failed: {text!r}")
		self.typed.append(text)
