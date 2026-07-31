# nvdaMcpBridge adapters -- NvdaConfigAccessor: session-scoped config overrides.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the ConfigAccessor port. On pyright's ignore list
#       (imports NVDA); validated by the 11.1 live-NVDA checklist.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: GetConfigHandler, SetConfigHandler, and session teardown.
#
# DESIGN (amended 2026-07-26). Never writes to config.conf. Instead, holds a
# session override map and installs a hook on AggregatedSection.__getitem__ that
# checks the map first. The map sits ABOVE the profile stack, so a profile
# switch mid-session cannot displace an override. set() reads the effective
# value from config.conf (the prior), then stores the new value in the map only.
# get() checks the map first, then falls through to config.conf. restore_all()
# clears the map and removes the hook -- there is nothing to "restore" because
# no config was ever written.
#
# BUT THE VALUE IS STILL VALIDATED. Not writing to config.conf means configobj
# never gets to vet the value, so this does what AggregatedSection.__setitem__
# does before storing (config/__init__.py:1261-1263): look up the confspec for
# the key path and run `config.conf.validator.check(spec, value)`, which both
# rejects a value the reader's own schema refuses AND coerces it to the declared
# type. The coerced value is what goes in the map, so every NVDA consumer reads
# back exactly the type a real config read would have produced -- an override
# can never inject a `str` where NVDA expects a `bool`.
#
# The override map is OWNED HERE (one dict per session) and merely lent to the
# hook module for as long as the hook is installed; see config_override_hook.py
# for why that matters.

from __future__ import annotations

from typing import Any

import config
from config import AggregatedSection
from configobj.validate import ValidateError

from ..domain.ports.config_accessor import ConfigAccessor, ConfigError
from .config_override_hook import install, remove
from .nvda_main_thread import run_on_main


class NvdaConfigAccessor(ConfigAccessor):
	"""Session-scoped config override map; never writes to config.conf."""

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

		# Read the prior (effective) value on first write to this key, and
		# validate/coerce the new one -- both touch config.conf, so both run on
		# the main thread in one hop rather than two.
		def _prepare() -> tuple[Any, Any]:
			prior = self._prior[key] if key in self._prior else self._get_from_conf(key_path)
			return prior, self._validated(key_path, value)

		prior, coerced = run_on_main(_prepare, block=True)
		self._prior.setdefault(key, prior)

		# Install the hooks on first set(), lending them this session's map and
		# the same confspec check, so a value NVDA's GUI writes back into an
		# overridden key is coerced exactly as one arriving via setConfig is.
		install(AggregatedSection, self._overrides, self._coerce_for_hook)
		self._overrides[key] = coerced
		return self._prior[key]

	def restore_all(self) -> None:
		if self._restored:
			return
		# Clear and unhook BEFORE claiming success: if either step raises, the
		# session's teardown guard swallows it, and a flag already flipped to
		# True would leave an override live while reporting it restored.
		self._overrides.clear()
		remove()
		self._restored = True

	# -- helpers --------------------------------------------------------------

	@staticmethod
	def _coerce_for_hook(key_path: tuple[str, ...], value: Any) -> Any:
		"""Validate a hooked write, but never fail one.

		The write is already happening -- typically NVDA's own settings GUI
		saving a panel -- and there is no caller to hand an error to. So a value
		the confspec rejects is stored as given rather than raised on: the
		session keeps its override, the dialog keeps working, and the blast
		radius is one in-memory value that dies at teardown. Rejection is for
		``setConfig``, which HAS a caller to tell.
		"""
		try:
			return NvdaConfigAccessor._validated(list(key_path), value)
		except ConfigError:
			return value

	@staticmethod
	def _get_from_conf(key_path: list[str]) -> Any:
		"""Read a value from NVDA's config (profile-aware)."""
		try:
			node: Any = config.conf
			for key in key_path:
				node = node[key]
			return node
		except (KeyError, TypeError, AttributeError) as exc:
			raise ConfigError(f"invalid config key path {key_path!r}: {exc}") from exc

	@staticmethod
	def _validated(key_path: list[str], value: Any) -> Any:
		"""Vet ``value`` against the confspec for ``key_path``; return it coerced.

		Mirrors what NVDA itself does on a real write. A path with no confspec
		entry (NVDA allows unspecced keys) is passed through unchanged -- there
		is no schema to check it against, and refusing would be stricter than
		NVDA is with its own writes.
		"""
		try:
			spec: Any = config.conf.spec
			for key in key_path:
				spec = spec[key]
		except (KeyError, TypeError, AttributeError):
			return value
		if not spec or isinstance(spec, dict):
			# A section, not a leaf: there is no scalar check to apply.
			return value
		try:
			return config.conf.validator.check(spec, value)
		except ValidateError as exc:
			raise ConfigError(
				f"config value {value!r} rejected for {key_path!r} (spec {spec!r}): {exc}"
			) from exc
