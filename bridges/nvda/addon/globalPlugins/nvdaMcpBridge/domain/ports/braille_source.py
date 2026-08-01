# nvdaMcpBridge domain -- the BrailleSource port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Feeds the braille buffer with what NVDA wrote to the display.
# USED BY: the Session controller (starts it at hello, stops it at teardown).
# IMPLEMENTED BY: adapters/nvda_*.py in session C (braille.pre_writeCells, both
#                 modes); tests/fakes/braille_source.py FakeBrailleSource.
#
# The braille counterpart of SpeechSource: same start/stop shape over a
# BrailleBuffer, and captured in both modes (there is no "silent" braille).

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Callable
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ..entities.braille_buffer import BrailleBuffer


class BrailleSource(ABC):
	"""Feeds captured braille updates into a :class:`BrailleBuffer`."""

	@abstractmethod
	def start(self, buffer: BrailleBuffer, log_position: Callable[[], int]) -> None:
		"""Begin capturing into ``buffer`` (register the braille hook).

		``log_position`` returns the journal's current append position; each
		capture calls it at the moment of capture and passes the result to
		``buffer.append`` (spec 0021), so a ring entry can later be placed on the
		log's timeline. The buffer itself never learns the journal exists.
		"""

	@abstractmethod
	def stop(self) -> None:
		"""Stop capturing. Idempotent and never raises -- teardown calls it in a guard."""
