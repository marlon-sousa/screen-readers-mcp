# nvdaMcpBridge tests -- FakeBrailleSource, standing in for the BrailleSource port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING

from nvdaMcpBridge.domain.ports.braille_source import BrailleSource

if TYPE_CHECKING:
	from nvdaMcpBridge.domain.entities.braille_buffer import BrailleBuffer


class FakeBrailleSource(BrailleSource):
	def __init__(self) -> None:
		self.buffer: BrailleBuffer | None = None
		self.log_position: Callable[[], int] = lambda: 0
		self.started = 0
		self.stopped = 0
		#: Braille already on the display when capture starts; emitted at start().
		self.initial: list[str] = []

	def start(self, buffer: BrailleBuffer, log_position: Callable[[], int]) -> None:
		self.buffer = buffer
		self.log_position = log_position
		self.started += 1
		for cells in self.initial:
			buffer.append(cells, log_position())

	def stop(self) -> None:
		self.stopped += 1

	def emit(self, cells: str) -> None:
		assert self.buffer is not None, "emit before the source was started"
		# Reads the position at capture, as NvdaBrailleSource does.
		self.buffer.append(cells, self.log_position())
