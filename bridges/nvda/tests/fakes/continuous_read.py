# nvdaMcpBridge tests -- FakeContinuousRead, standing in for the ContinuousRead port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/continuous_read.py
#
# A read that a test starts and stops by hand, because the interesting state is
# the one no real timing can hold still: a continuous read that is RUNNING while
# nothing is arriving. That is the state the settle used to misread, and against
# a real reader it lasts only as long as a chunk of audio.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.continuous_read import ContinuousRead


class FakeContinuousRead(ContinuousRead):
	"""A continuous read whose progress the test controls directly."""

	def __init__(self, *, running: bool = False) -> None:
		self.running = running
		#: How many times the settle asked, so a test can prove it kept asking
		#: rather than caching the first answer.
		self.asked = 0

	def in_progress(self) -> bool:
		self.asked += 1
		return self.running
