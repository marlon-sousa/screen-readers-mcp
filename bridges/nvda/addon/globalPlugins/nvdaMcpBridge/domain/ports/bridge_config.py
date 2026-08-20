# nvdaMcpBridge domain -- the BridgeConfig port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. The contract the dialog (and plugin.py) read/write persisted
#       preferences through -- without knowing they're an .ini file.
# IMPLEMENTED BY: adapters/ini_bridge_config.py (production, configparser-backed,
#                 profile-independent .ini file under <configPath>\nvdaMcpBridge\config\),
#                 tests/fakes/bridge_config.py (in-memory dict for tests).
# USED BY: plugin.py (reads mode on load, reads auto_start; exposes rebuild_server),
#          views/bridge_dialog.py (reads/writes both values, injected via constructor).

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from ..entities.connection_mode import ConnectionMode


class BridgeConfig(ABC):
	"""Persisted bridge preferences: connection mode, auto-start, silence cap.

	Profile-independent on purpose -- NVDA's config.conf is profile-aware, and
	switching profiles resets it to the active profile's values. The bridge's
	connection mode and auto-start preference are machine-wide settings; they
	should survive a profile switch unchanged.
	"""

	@abstractmethod
	def get_connection_mode(self) -> ConnectionMode:
		"""The persisted connection mode, or DEFAULT when no file exists yet."""

	@abstractmethod
	def set_connection_mode(self, mode: ConnectionMode) -> None:
		"""Persist *mode*; creates the directory and file on first save."""

	@abstractmethod
	def get_auto_start(self) -> bool:
		"""Whether to auto-start the bridge on NVDA load. Default ``False``."""

	@abstractmethod
	def set_auto_start(self, value: bool) -> None:
		"""Persist *value*; creates the directory and file on first save."""

	@abstractmethod
	def get_unattended(self) -> bool:
		"""Whether nobody is sitting at this machine. Default ``False``.

		The silence cap's on/off switch, and the one setting here that is about the
		ROOM rather than about the bridge (spec 0032 Part 4). True means no session
		on this machine is capped: an accessibility run on a CI box at 3am has no
		human to protect, so un-muting it would be damage rather than a safeguard.

		It lives on the MACHINE and not on the wire, and it is not the persona.
		The agent declares the persona, so a persona that decided this would hand
		the session its own ceiling -- and it would do it silently, because the
		symptom of a missing cap is that nothing happens. "Is a human in this room"
		is a fact about the deployment: a CI runner is empty at 3am and empty at
		3pm, whatever connects to it.

		Defaults to attended because the costs are not symmetric. A machine nobody
		has configured is not a machine we may assume is empty.
		"""

	@abstractmethod
	def set_unattended(self, value: bool) -> None:
		"""Persist *value*; creates the directory and file on first save."""

	@abstractmethod
	def get_silence_warn_seconds(self) -> float:
		"""Seconds of silence after which the reader warns its human. Default 45."""

	@abstractmethod
	def set_silence_warn_seconds(self, value: float) -> None:
		"""Persist the warning threshold."""

	@abstractmethod
	def get_silence_lift_seconds(self) -> float:
		"""Seconds of silence after which suppression ends. Default 90."""

	@abstractmethod
	def set_silence_lift_seconds(self, value: float) -> None:
		"""Persist the lift threshold."""
