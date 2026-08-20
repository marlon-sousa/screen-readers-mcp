# nvdaMcpBridge adapters -- IniBridgeConfig: the BridgeConfig port backed by a
# profile-independent config.ini.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter (implements the BridgeConfig domain port). Holds every decision
#       (defaults, validation, configparser vocabulary) and delegates raw file IO
#       to a ConfigFile seam -- so it is fully unit-testable against a fake.
# IMPLEMENTS: domain/ports/bridge_config.py BridgeConfig.
# BUILT BY: plugin.py (the composition root), handing it a TextConfigFile.
# USED BY: plugin.py (reads mode on load, reads auto_start; exposes start_server),
#          views/bridge_dialog.py (via the port, injected by plugin.py).
#
# Does NOT import NVDA -- the config path comes from the TextConfigFile leaf
# built by plugin.py. Strict-checked by pyright.

from __future__ import annotations

import configparser
import io

from ..domain.entities.connection_mode import DEFAULT, ConnectionMode
from ..domain.entities.silence_cap import DEFAULT_LIFT_AFTER, DEFAULT_WARN_AFTER
from ..domain.ports.bridge_config import BridgeConfig
from ..domain.ports.log import Log
from .ports.config_file import ConfigFile

#: The section name in config.ini.
_SECTION = "nvdaMcpBridge"

#: Key names in config.ini for the persisted values.
_KEY_MODE = "connectionMode"
_KEY_AUTO_START = "autoStart"
#: The silence cap (spec 0032). Three keys, all machine-wide like the two above.
_KEY_UNATTENDED = "unattended"
_KEY_WARN_SECONDS = "silenceWarnSeconds"
_KEY_LIFT_SECONDS = "silenceLiftSeconds"


class IniBridgeConfig(BridgeConfig):
	"""Bridge preferences backed by a profile-independent config.ini.

	Reads return sensible defaults (``DEFAULT`` / ``False``) when no file
	exists yet or a key is missing; writes create the file on first save.
	Raw IO is delegated to the injected ConfigFile seam so the configparser
	decisions here are unit-testable.
	"""

	def __init__(self, file: ConfigFile, log: Log) -> None:
		self._file = file
		self._log = log

	# -- BridgeConfig implementation --------------------------------------------

	def get_connection_mode(self) -> ConnectionMode:
		parser = self._read()
		raw = parser.get(_SECTION, _KEY_MODE, fallback=DEFAULT.value)
		try:
			return ConnectionMode(raw)
		except ValueError:
			self._log.warning(
				f"nvdaMcpBridge: unrecognised connection mode {raw!r}; using default ({DEFAULT.value})"
			)
			return DEFAULT

	def set_connection_mode(self, mode: ConnectionMode) -> None:
		parser = self._read()
		self._ensure_section(parser)
		parser.set(_SECTION, _KEY_MODE, mode.value)
		self._write(parser)

	def get_auto_start(self) -> bool:
		parser = self._read()
		return parser.getboolean(_SECTION, _KEY_AUTO_START, fallback=False)

	def set_auto_start(self, value: bool) -> None:
		self._put(_KEY_AUTO_START, "true" if value else "false")

	# -- the silence cap (spec 0032) --------------------------------------------
	#
	# Every read here falls to the SAFE side of the setting it is reading: absent,
	# unparseable or nonsensical all mean "assume somebody is sitting there, on the
	# shipped thresholds". That is the same posture the corrupt-file path above
	# already takes, and it matters more here than anywhere else in this file --
	# the failure mode of getting it wrong is a blind person unable to hear their
	# own computer, with nothing to stop it.

	def get_unattended(self) -> bool:
		parser = self._read()
		try:
			return parser.getboolean(_SECTION, _KEY_UNATTENDED, fallback=False)
		except ValueError:
			# A value configparser cannot read as a boolean. "Attended" is the safe
			# answer, and it is worth a line in the log because the human who typed
			# it believes they turned the cap off.
			self._log.warning(
				f"nvdaMcpBridge: unreadable {_KEY_UNATTENDED} in config.ini; "
				f"assuming this machine is attended"
			)
			return False

	def set_unattended(self, value: bool) -> None:
		self._put(_KEY_UNATTENDED, "true" if value else "false")

	def get_silence_warn_seconds(self) -> float:
		return self._positive_float(_KEY_WARN_SECONDS, DEFAULT_WARN_AFTER)

	def set_silence_warn_seconds(self, value: float) -> None:
		self._put(_KEY_WARN_SECONDS, f"{value:g}")

	def get_silence_lift_seconds(self) -> float:
		return self._positive_float(_KEY_LIFT_SECONDS, DEFAULT_LIFT_AFTER)

	def set_silence_lift_seconds(self, value: float) -> None:
		self._put(_KEY_LIFT_SECONDS, f"{value:g}")

	def _positive_float(self, key: str, default: float) -> float:
		"""Read one threshold, falling back on the default for anything unusable.

		The PAIR still has to be ordered, which two independent reads cannot check;
		SilenceCapPolicy.from_settings does that, and falls back the same way.
		"""
		parser = self._read()
		raw = parser.get(_SECTION, key, fallback=None)
		if raw is None:
			return default
		try:
			value = float(raw)
		except ValueError:
			value = 0.0
		if value <= 0:
			self._log.warning(f"nvdaMcpBridge: unusable {key}={raw!r} in config.ini; using {default:g}")
			return default
		return value

	# -- internals --------------------------------------------------------------

	def _read(self) -> configparser.ConfigParser:
		parser = configparser.ConfigParser()
		raw = self._file.read()
		if raw is not None:
			try:
				parser.read_string(raw)
			except configparser.Error:
				self._log.warning("nvdaMcpBridge: corrupt config.ini; using defaults")
		return parser

	def _put(self, key: str, value: str) -> None:
		"""Write one key into the section, creating file and section as needed."""
		parser = self._read()
		self._ensure_section(parser)
		parser.set(_SECTION, key, value)
		self._write(parser)

	def _ensure_section(self, parser: configparser.ConfigParser) -> None:
		if not parser.has_section(_SECTION):
			parser.add_section(_SECTION)

	def _write(self, parser: configparser.ConfigParser) -> None:
		buf = io.StringIO()
		parser.write(buf)
		self._file.write(buf.getvalue())
