# nvdaMcpBridge domain -- the ContinuousRead port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, reporting whether the reader is part-way through a self-advancing read.
# USED BY: the SpeechBuffer, deciding whether speech has finished.
# IMPLEMENTED BY: adapters/nvda_continuous_read.py; tests/fakes/continuous_read.py.
# NVDA 2026.1 produces say all one chunk at a time, pausing on audio between chunks, which the quiet heuristic
# cannot tell from the end of speech. A reader that cannot see such a read implements this as False.

from __future__ import annotations

from abc import ABC, abstractmethod


class ContinuousRead(ABC):
	@abstractmethod
	def in_progress(self) -> bool:
		"""Including between chunks."""
