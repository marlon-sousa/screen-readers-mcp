# nvdaMcpBridge tests -- FakeConfigAccessor, standing in for the ConfigAccessor port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from typing import Any

from nvdaMcpBridge.domain.ports.config_accessor import ConfigAccessor, ConfigError


class FakeConfigAccessor(ConfigAccessor):
	def __init__(self) -> None:
		# Seeded with NVDA's default for the one admitted key, so silent-mode tests exercise normalisation.
		self._store: dict[tuple[str, ...], Any] = {
			("virtualBuffers", "passThroughAudioIndication"): True,
		}
		self._prior: dict[tuple[str, ...], Any] = {}
		self._restored = False
		self.get_calls: list[list[str]] = []
		self.set_calls: list[tuple[list[str], Any]] = []
		self.restore_calls: int = 0

	def get(self, key_path: list[str]) -> Any:
		self.get_calls.append(key_path)
		key = tuple(key_path)
		if key not in self._store:
			raise ConfigError(f"unknown key: {key_path!r}")
		return self._store[key]

	def set(self, key_path: list[str], value: Any) -> Any:
		self.set_calls.append((key_path, value))
		key = tuple(key_path)
		if key not in self._store:
			raise ConfigError(f"unknown key: {key_path!r}")
		prior = self._store[key]
		if key not in self._prior:
			self._prior[key] = prior
		self._store[key] = value
		return prior

	def restore_all(self) -> None:
		self.restore_calls += 1
		if self._restored:
			return
		self._restored = True
		for key, prior_value in self._prior.items():
			self._store[key] = prior_value

	def seed(self, key_path: list[str], value: Any) -> None:
		self._store[tuple(key_path)] = value

	def forget(self, key_path: list[str]) -> None:
		self._store.pop(tuple(key_path), None)

	@property
	def store(self) -> dict[tuple[str, ...], Any]:
		return dict(self._store)
