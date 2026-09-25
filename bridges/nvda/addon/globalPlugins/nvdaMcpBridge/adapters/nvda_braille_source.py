# nvdaMcpBridge adapters -- NvdaBrailleSource: braille capture (both modes).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing BrailleSource from braille.pre_writeCells, in both capture modes.
# BUILT BY: adapters/nvda_adapter_factory.py.
# NVDA holds handlers weakly, so this instance must outlive its registration.

from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, Any

import braille

from ..domain.ports.braille_source import BrailleSource

if TYPE_CHECKING:
	from ..domain.entities.braille_buffer import BrailleBuffer


class NvdaBrailleSource(BrailleSource):
	def __init__(self) -> None:
		self._buffer: BrailleBuffer | None = None
		self._log_position: Callable[[], int] = lambda: 0
		self._registered = False

	def start(self, buffer: BrailleBuffer, log_position: Callable[[], int]) -> None:
		self._buffer = buffer
		self._log_position = log_position
		braille.pre_writeCells.register(self._on_write_cells)
		self._registered = True

	def stop(self) -> None:
		if self._registered:
			braille.pre_writeCells.unregister(self._on_write_cells)
			self._registered = False
		self._buffer = None

	def _on_write_cells(
		self,
		cells: Any = None,
		rawText: Any = None,
		currentCellCount: Any = None,
		**kwargs: Any,
	) -> None:
		buffer = self._buffer
		if buffer is not None and rawText:
			buffer.append(rawText, self._log_position())
