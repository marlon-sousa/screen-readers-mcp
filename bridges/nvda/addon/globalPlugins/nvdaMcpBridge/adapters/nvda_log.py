# nvdaMcpBridge adapters -- NvdaLog: the Log port backed by NVDA's logHandler.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing Log over NVDA's logHandler.log.
# BUILT BY: plugin.py.
# USED BY: adapters/ini_bridge_config.py.

from __future__ import annotations

from logHandler import log

from ..domain.ports.log import Log


class NvdaLog(Log):
	def info(self, msg: str) -> None:
		log.info(msg)

	def warning(self, msg: str) -> None:
		log.warning(msg)

	def error(self, msg: str, exc_info: bool = False) -> None:
		log.error(msg, exc_info=exc_info)
