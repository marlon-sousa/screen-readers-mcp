# nvdaMcpBridge test doubles -- FakeLog: the Log port in memory.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: fake; records every message.

from __future__ import annotations

from nvdaMcpBridge.domain.ports.log import Log


class FakeLog(Log):
	def __init__(self) -> None:
		self.infos: list[str] = []
		self.warnings: list[str] = []
		self.errors: list[str] = []

	def info(self, msg: str) -> None:
		self.infos.append(msg)

	def warning(self, msg: str) -> None:
		self.warnings.append(msg)

	def error(self, msg: str, exc_info: bool = False) -> None:
		self.errors.append(msg)
