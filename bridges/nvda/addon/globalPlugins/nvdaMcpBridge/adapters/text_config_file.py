# nvdaMcpBridge adapters -- TextConfigFile: the ConfigFile leaf.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: leaf adapter implementing ConfigFile with real file IO.
# BUILT BY: plugin.py.
# USED BY: adapters/ini_bridge_config.py, through the ConfigFile seam.

from __future__ import annotations

import os
from pathlib import Path

from .ports.config_file import ConfigFile


class TextConfigFile(ConfigFile):
	def __init__(self, path: str | os.PathLike[str]) -> None:
		self._path = Path(path)

	def read(self) -> str | None:
		try:
			return self._path.read_text(encoding="utf-8")
		except FileNotFoundError:
			return None

	def write(self, content: str) -> None:
		self._path.parent.mkdir(parents=True, exist_ok=True)
		self._path.write_text(content, encoding="utf-8")
