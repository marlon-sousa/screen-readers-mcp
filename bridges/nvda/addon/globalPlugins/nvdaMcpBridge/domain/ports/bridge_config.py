# nvdaMcpBridge domain -- the BridgeConfig port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, the persisted bridge preferences.
# IMPLEMENTED BY: adapters/ini_bridge_config.py; tests/fakes/bridge_config.py.
# USED BY: plugin.py and views/bridge_dialog.py.

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ..entities.connection_mode import ConnectionMode


class BridgeConfig(ABC):
	"""Profile-independent: these are machine-wide and must survive an NVDA profile switch."""

	@abstractmethod
	def get_connection_mode(self) -> ConnectionMode:
		"""DEFAULT when no file exists yet."""

	@abstractmethod
	def set_connection_mode(self, mode: ConnectionMode) -> None:
		"""Creates the directory and file on first save."""

	@abstractmethod
	def get_auto_start(self) -> bool:
		"""Default ``False``."""

	@abstractmethod
	def set_auto_start(self, value: bool) -> None:
		"""Creates the directory and file on first save."""

	@abstractmethod
	def get_unattended(self) -> bool:
		"""Whether nobody is sitting at this machine, which disables the silence cap. Default ``False``.

		A machine setting, never the persona or the wire: an agent must not be able to set its own ceiling.
		"""

	@abstractmethod
	def set_unattended(self, value: bool) -> None:
		"""Creates the directory and file on first save."""

	@abstractmethod
	def get_silence_warn_seconds(self) -> float:
		"""Default 45."""

	@abstractmethod
	def set_silence_warn_seconds(self, value: float) -> None:
		"""Persist the warning threshold."""

	@abstractmethod
	def get_silence_lift_seconds(self) -> float:
		"""Default 90."""

	@abstractmethod
	def set_silence_lift_seconds(self, value: float) -> None:
		"""Persist the lift threshold."""
