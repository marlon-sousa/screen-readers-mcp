# nvdaMcpBridge domain ports -- the Log port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, the logging seam that keeps adapters testable without NVDA's ``logHandler``.
# IMPLEMENTED BY: adapters/nvda_log.py; tests/fakes/log.py.
# USED BY: adapters/ini_bridge_config.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class Log(ABC):
	@abstractmethod
	def info(self, msg: str) -> None: ...

	@abstractmethod
	def warning(self, msg: str) -> None: ...

	@abstractmethod
	def error(self, msg: str, exc_info: bool = False) -> None: ...
