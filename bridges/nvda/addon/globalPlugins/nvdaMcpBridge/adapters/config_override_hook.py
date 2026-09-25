# nvdaMcpBridge adapters -- session-scoped config override hook.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: a hook on AggregatedSection's __getitem__ and __setitem__ that consults a session override map
#       first; the class is passed in, so this module imports no NVDA.
# USED BY: nvda_config_accessor.py.
# Writes must be hooked as well as reads: NVDA's settings dialogs write every control back on OK, so an
# unhooked write would move an override into the real profile and the next save() would persist it.
# A write to an overridden key updates only the map, so the profile is never marked dirty.
# The map belongs to the caller; this module only holds a reference to it while the hook is live.

from __future__ import annotations

from collections.abc import Callable
from typing import Any

#: Validates and coerces a write to an overridden key as NVDA would; None stores the value as given.
Coercer = Callable[[tuple[str, ...], Any], Any]

#: The live session's override map keyed by full config path, or None when no hook is installed.
_active: dict[tuple[str, ...], Any] | None = None

_coerce: Coercer | None = None

_original_getitem: Any = None
_original_setitem: Any = None

_target_class: Any = None


def _hook_getitem(self: Any, key: Any, checkValidity: bool = True) -> Any:
	overrides = _active
	if not overrides:
		return _original_getitem(self, key, checkValidity)
	full_path = (*self.path, key)  # type: ignore[attr-defined]
	if full_path in overrides:
		return overrides[full_path]
	return _original_getitem(self, key, checkValidity)


def _hook_setitem(self: Any, key: Any, val: Any) -> None:
	overrides = _active
	if overrides:
		full_path = (*self.path, key)  # type: ignore[attr-defined]
		if full_path in overrides:
			overrides[full_path] = _coerce(full_path, val) if _coerce else val
			return
	_original_setitem(self, key, val)


def install(
	klass: Any,
	overrides: dict[tuple[str, ...], Any],
	coerce: Coercer | None = None,
) -> None:
	"""A second call re-points the map without re-patching, so the saved originals never become the hooks."""
	global _active, _coerce, _original_getitem, _original_setitem, _target_class
	_active = overrides
	_coerce = coerce
	if _target_class is not None:
		return
	_target_class = klass
	_original_getitem = klass.__getitem__
	_original_setitem = klass.__setitem__
	klass.__getitem__ = _hook_getitem  # type: ignore[method-assign]
	klass.__setitem__ = _hook_setitem  # type: ignore[method-assign]


def remove() -> None:
	global _active, _coerce, _original_getitem, _original_setitem, _target_class
	_active = None
	_coerce = None
	if _target_class is None:
		return
	_target_class.__getitem__ = _original_getitem  # type: ignore[method-assign]
	_target_class.__setitem__ = _original_setitem  # type: ignore[method-assign]
	_original_getitem = None
	_original_setitem = None
	_target_class = None
