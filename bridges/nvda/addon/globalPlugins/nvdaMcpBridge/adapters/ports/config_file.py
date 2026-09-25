# nvdaMcpBridge adapters -- the ConfigFile seam.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter seam that reads and writes a whole config file.
# USED BY: adapters/ini_bridge_config.py.
# IMPLEMENTED BY: adapters/text_config_file.py and tests/fakes/config_file.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class ConfigFile(ABC):
	@abstractmethod
	def read(self) -> str | None:
		"""None when the file does not exist."""

	@abstractmethod
	def write(self, content: str) -> None:
		"""Creates parent directories as needed."""
