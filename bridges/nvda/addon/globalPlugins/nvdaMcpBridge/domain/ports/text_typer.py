# nvdaMcpBridge domain -- the TextTyper port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port; injects literal text into the focused control and blocks until NVDA's main
# thread has finished.
# USED BY: the Session controller.
# IMPLEMENTED BY: adapters/nvda_text_typer.py and tests/fakes/text_typer.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class TypingError(Exception):
	"""Text could not be typed; a per-command failure, not a session-ending fault."""


class TextTyper(ABC):
	@abstractmethod
	def type_text(self, text: str) -> None:
		pass
