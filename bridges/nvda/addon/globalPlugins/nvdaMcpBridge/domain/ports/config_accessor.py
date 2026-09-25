# nvdaMcpBridge domain -- the ConfigAccessor port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, reading the reader's config with session-scoped overrides above its profiles.
# USED BY: GetConfigHandler, SetConfigHandler, HelloHandler and session teardown.
# IMPLEMENTED BY: adapters/nvda_config_accessor.py; tests/fakes/config_accessor.py.
# Overrides must never be written to the reader's config or disk, so a crash cannot reconfigure the reader.

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class ConfigError(Exception):
	"""A key path the reader does not define, or a value its schema rejects."""


class ConfigAccessor(ABC):
	@abstractmethod
	def get(self, key_path: list[str]) -> Any:
		"""The session's override if set, otherwise the reader's own value; raises :class:`ConfigError`."""

	@abstractmethod
	def set(self, key_path: list[str], value: Any) -> Any:
		"""Validated against the reader's schema; returns the prior value. Raises :class:`ConfigError`."""

	@abstractmethod
	def restore_all(self) -> None:
		"""Called at teardown on every exit path. Idempotent."""
