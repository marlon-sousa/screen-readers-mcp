# nvdaMcpBridge tests -- FakeBridgeConfig, standing in for the BridgeConfig port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/bridge_config.py

from __future__ import annotations

from nvdaMcpBridge.domain.entities.connection_mode import DEFAULT, ConnectionMode
from nvdaMcpBridge.domain.entities.silence_cap import DEFAULT_LIFT_AFTER, DEFAULT_WARN_AFTER
from nvdaMcpBridge.domain.ports.bridge_config import BridgeConfig


class FakeBridgeConfig(BridgeConfig):
	"""An in-memory :class:`BridgeConfig` backed by a plain dict.

	Initialised with defaults so a test that does not care about config can
	construct it with no arguments; any test that needs a specific mode or
	auto-start preference passes them as keyword arguments.
	"""

	def __init__(
		self,
		*,
		mode: ConnectionMode = DEFAULT,
		auto_start: bool = False,
		unattended: bool = False,
		warn_seconds: float = DEFAULT_WARN_AFTER,
		lift_seconds: float = DEFAULT_LIFT_AFTER,
	) -> None:
		self._mode = mode
		self._auto_start = auto_start
		self._unattended = unattended
		self._warn_seconds = warn_seconds
		self._lift_seconds = lift_seconds

	def get_connection_mode(self) -> ConnectionMode:
		return self._mode

	def set_connection_mode(self, mode: ConnectionMode) -> None:
		self._mode = mode

	def get_auto_start(self) -> bool:
		return self._auto_start

	def set_auto_start(self, value: bool) -> None:
		self._auto_start = value

	def get_unattended(self) -> bool:
		return self._unattended

	def set_unattended(self, value: bool) -> None:
		self._unattended = value

	def get_silence_warn_seconds(self) -> float:
		return self._warn_seconds

	def set_silence_warn_seconds(self, value: float) -> None:
		self._warn_seconds = value

	def get_silence_lift_seconds(self) -> float:
		return self._lift_seconds

	def set_silence_lift_seconds(self, value: float) -> None:
		self._lift_seconds = value
