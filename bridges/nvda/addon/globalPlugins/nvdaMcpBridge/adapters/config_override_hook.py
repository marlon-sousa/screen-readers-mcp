# nvdaMcpBridge adapters -- session-scoped config override hook.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: a pure hook on AggregatedSection's __getitem__ AND __setitem__ that
#       checks a session override map before falling through. This module has NO
#       NVDA imports (the AggregatedSection class is passed in) so it
#       can be unit-tested headlessly.
# USED BY: nvda_config_accessor.py and its unit tests.
#
# The override map sits ABOVE the profile stack, so a profile switch
# mid-session cannot displace an override. Installed on first set(),
# removed at teardown. A hard kill restores normal behaviour by the
# hook dying with the bridge process.
#
# BOTH ENDS ARE HOOKED, and that is the point. Hooking reads alone made the
# layer asymmetric -- reads went through it, writes went around it -- and NVDA's
# own settings GUI does a read-modify-write: it reads a value into a control and
# writes every control back on OK. With writes unhooked, that round trip lifted
# the override out of the map, put it in the real profile, marked the profile
# dirty, and the next save() wrote it to disk. Opening a settings dialog was
# enough to permanently reconfigure the user's screen reader.
#
# So a write to a key already in the map updates the MAP and stops there: the
# profile is never touched, never marked dirty, and save() has nothing to leak
# -- which is why save() needs no hook of its own. A write to any other key
# falls through untouched, so settings this session never overrode behave, and
# persist, exactly as they always did.
#
# THE MAP IS OWNED BY THE CALLER, NOT BY THIS MODULE. install() takes the
# accessor's own dict and this module only holds a REFERENCE to it while the
# hook is live. That keeps session state on the session's object: the accessor
# is per-session, and a module-level map would have made every session share one
# -- correct only for as long as `BridgeServer` serves one session at a time
# (adapters/bridge_server.py: "One session at a time"), and silently wrong the
# day it does not. There is still exactly one hook, because there is exactly one
# AggregatedSection class to patch; what varies per session is which map it
# reads.

from __future__ import annotations

from collections.abc import Callable
from typing import Any

#: Validates and coerces a value being written to an overridden key, mirroring
#: what NVDA's own __setitem__ would have done. Supplied by the caller (it needs
#: NVDA's confspec, which this module deliberately cannot reach); ``None`` means
#: store the value as given, which is what the headless tests do.
Coercer = Callable[[tuple[str, ...], Any], Any]

#: The live session's override map, or None when no hook is installed. Keyed by
#: full config path as a tuple, e.g. ``("speech", "espeak", "sayCapForCapitals")``.
_active: dict[tuple[str, ...], Any] | None = None

#: The caller's validate-and-coerce hook for writes; see :data:`Coercer`.
_coerce: Coercer | None = None

#: The originals, restored at teardown.
_original_getitem: Any = None
_original_setitem: Any = None

#: The class being patched; set by install().
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
	"""Redirect a write to an overridden key into the map; pass everything else on.

	Only a key ALREADY in the map is captured. This is not "the session owns
	config now" -- it is "the session owns the keys it overrode". A write to any
	other key reaches NVDA untouched and persists as it always did, and a write
	here never marks a profile dirty, so ``save()`` has nothing of ours to write.
	"""
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
	"""Install the hooks on ``klass`` (AggregatedSection), reading ``overrides``.

	Idempotent for one session: a second call re-points the map without
	re-patching, so the saved originals can never come to hold the hooks
	themselves (which would make ``remove`` a no-op and leak the override
	forever).
	"""
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
	"""Remove both hooks, restoring the originals. Idempotent."""
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
