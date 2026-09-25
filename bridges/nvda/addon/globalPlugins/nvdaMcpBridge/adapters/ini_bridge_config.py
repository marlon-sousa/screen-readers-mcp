# nvdaMcpBridge adapters -- IniBridgeConfig: the BridgeConfig port backed by a
# profile-independent config.ini.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing BridgeConfig; holds every configparser decision, file IO goes to ConfigFile.
# BUILT BY: plugin.py.
# USED BY: plugin.py and views/bridge_dialog.py.

from __future__ import annotations

import configparser
import io

from ..domain.entities.connection_mode import DEFAULT, ConnectionMode
from ..domain.entities.silence_cap import DEFAULT_LIFT_AFTER, DEFAULT_WARN_AFTER
from ..domain.ports.bridge_config import BridgeConfig
from ..domain.ports.log import Log
from .ports.config_file import ConfigFile

_SECTION = "nvdaMcpBridge"

_KEY_MODE = "connectionMode"
_KEY_AUTO_START = "autoStart"
_KEY_UNATTENDED = "unattended"
_KEY_WARN_SECONDS = "silenceWarnSeconds"
_KEY_LIFT_SECONDS = "silenceLiftSeconds"


class IniBridgeConfig(BridgeConfig):
	def __init__(self, file: ConfigFile, log: Log) -> None:
		self._file = file
		self._log = log

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

	# Every silence-cap read falls to the attended side when a value is absent or unusable: getting it
	# wrong leaves a blind user unable to hear their own computer.

	def get_unattended(self) -> bool:
		parser = self._read()
		try:
			return parser.getboolean(_SECTION, _KEY_UNATTENDED, fallback=False)
		except ValueError:
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
		"""The ordering of the pair is checked by SilenceCapPolicy.from_settings, not here."""
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
