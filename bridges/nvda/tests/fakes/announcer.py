# nvdaMcpBridge tests -- FakeAnnouncer, standing in for the Announcer port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.announcer import Announcer, SilenceNotice


class FakeAnnouncer(Announcer):
	def __init__(self, synth: str = "espeak") -> None:
		self._synth = synth
		self.announced: list[str] = []
		self.notices: list[SilenceNotice] = []

	def current_synth(self) -> str:
		return self._synth

	def announce(self, text: str) -> None:
		self.announced.append(text)

	def silence_notice(self, notice: SilenceNotice) -> None:
		self.notices.append(notice)
