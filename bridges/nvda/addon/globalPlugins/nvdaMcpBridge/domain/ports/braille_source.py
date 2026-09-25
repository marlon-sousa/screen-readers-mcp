# nvdaMcpBridge domain -- the BrailleSource port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, feeding the BrailleBuffer with what NVDA wrote to the display, in both capture modes.
# USED BY: the hello handler starts it; the Session stops it at teardown.
# IMPLEMENTED BY: adapters/nvda_braille_source.py; tests/fakes/braille_source.py.

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ..entities.braille_buffer import BrailleBuffer


class BrailleSource(ABC):
	@abstractmethod
	def start(self, buffer: BrailleBuffer, log_position: Callable[[], int]) -> None:
		"""``log_position`` is called at each capture and its result passed to ``buffer.append``."""

	@abstractmethod
	def stop(self) -> None:
		"""Idempotent and never raises."""
