# nvdaMcpBridge adapters -- NvdaConfigAccessor: session-scoped config overrides.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing ConfigAccessor as a session override map; it never writes to config.conf.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: GetConfigHandler, SetConfigHandler and session teardown.
# Values are validated and coerced against NVDA's confspec before they are stored, so an override never
# injects a str where NVDA expects a bool.

from __future__ import annotations

from typing import Any

import config
from config import AggregatedSection
from configobj.validate import ValidateError

from ..domain.ports.config_accessor import ConfigAccessor, ConfigError
from .config_override_hook import install, remove
from .nvda_main_thread import run_on_main


class NvdaConfigAccessor(ConfigAccessor):
	def __init__(self) -> None:
		self._overrides: dict[tuple[str, ...], Any] = {}
		self._prior: dict[tuple[str, ...], Any] = {}
		self._restored = False

	def get(self, key_path: list[str]) -> Any:
		key = tuple(key_path)
		if key in self._overrides:
			return self._overrides[key]
		return run_on_main(lambda: self._get_from_conf(key_path), block=True)

	def set(self, key_path: list[str], value: Any) -> Any:
		key = tuple(key_path)

		# Both steps touch config.conf, so they run on the main thread in one hop.
		def _prepare() -> tuple[Any, Any]:
			prior = self._prior[key] if key in self._prior else self._get_from_conf(key_path)
			return prior, self._validated(key_path, value)

		prior, coerced = run_on_main(_prepare, block=True)
		self._prior.setdefault(key, prior)

		# A value NVDA's settings GUI writes back to an overridden key is coerced the same way.
		install(AggregatedSection, self._overrides, self._coerce_for_hook)
		self._overrides[key] = coerced
		return self._prior[key]

	def restore_all(self) -> None:
		if self._restored:
			return
		# Clear and unhook before setting the flag, so a failure never reports an override as restored.
		self._overrides.clear()
		remove()
		self._restored = True

	@staticmethod
	def _coerce_for_hook(key_path: tuple[str, ...], value: Any) -> Any:
		"""Never fails: a hooked write has no caller to tell, so a rejected value is stored as given."""
		try:
			return NvdaConfigAccessor._validated(list(key_path), value)
		except ConfigError:
			return value

	@staticmethod
	def _get_from_conf(key_path: list[str]) -> Any:
		try:
			node: Any = config.conf
			for key in key_path:
				node = node[key]
			return node
		except (KeyError, TypeError, AttributeError) as exc:
			raise ConfigError(f"invalid config key path {key_path!r}: {exc}") from exc

	@staticmethod
	def _validated(key_path: list[str], value: Any) -> Any:
		"""A path with no confspec entry passes through unchanged, as NVDA allows unspecced keys."""
		try:
			spec: Any = config.conf.spec
			for key in key_path:
				spec = spec[key]
		except (KeyError, TypeError, AttributeError):
			return value
		if not spec or isinstance(spec, dict):
			return value
		try:
			return config.conf.validator.check(spec, value)
		except ValidateError as exc:
			raise ConfigError(
				f"config value {value!r} rejected for {key_path!r} (spec {spec!r}): {exc}"
			) from exc
