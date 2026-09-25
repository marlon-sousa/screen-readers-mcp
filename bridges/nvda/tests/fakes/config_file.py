# nvdaMcpBridge test doubles -- FakeConfigFile: the ConfigFile port in memory.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: fake; an in-memory ConfigFile for IniBridgeConfig tests.

from __future__ import annotations

from nvdaMcpBridge.adapters.ports.config_file import ConfigFile


class FakeConfigFile(ConfigFile):
	"""None means the file does not exist."""

	def __init__(self, content: str | None = None) -> None:
		self._content = content

	def read(self) -> str | None:
		return self._content

	def write(self, content: str) -> None:
		self._content = content
