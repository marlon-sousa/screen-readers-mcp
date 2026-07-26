# nvdaMcpBridge adapters -- session-scoped config override hook.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: a pure hook on AggregatedSection.__getitem__ that checks a
#       session override map before falling through. This module has NO
#       NVDA imports (the AggregatedSection class is passed in) so it
#       can be unit-tested headlessly.
# USED BY: nvda_config_accessor.py and its unit tests.
#
# The override map sits ABOVE the profile stack, so a profile switch
# mid-session cannot displace an override. Installed on first set(),
# removed at teardown. A hard kill restores normal behaviour by the
# hook dying with the bridge process.
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

from typing import Any

#: The live session's override map, or None when no hook is installed. Keyed by
#: full config path as a tuple, e.g. ``("speech", "sayCapForCapitals")``.
_active: dict[tuple[str, ...], Any] | None = None

#: The original __getitem__, restored at teardown.
_original_getitem: Any = None

#: The class being patched; set by install().
_target_class: Any = None


def _hook_getitem(self: Any, key: Any, checkValidity: bool = True) -> Any:
	overrides = _active
	if not overrides:
		return _original_getitem(self, key, checkValidity)
	full_path = self.path + (key,)  # type: ignore[attr-defined]
	if full_path in overrides:
		return overrides[full_path]
	return _original_getitem(self, key, checkValidity)


def install(klass: Any, overrides: dict[tuple[str, ...], Any]) -> None:
	"""Install the hook on ``klass`` (AggregatedSection), reading ``overrides``.

	Idempotent for one session: a second call re-points the map without
	re-patching, so ``_original_getitem`` can never come to hold the hook
	itself (which would make ``remove`` a no-op and leak the override forever).
	"""
	global _active, _original_getitem, _target_class  # noqa: PLW0603
	_active = overrides
	if _target_class is not None:
		return
	_target_class = klass
	_original_getitem = klass.__getitem__
	klass.__getitem__ = _hook_getitem  # type: ignore[method-assign]


def remove() -> None:
	"""Remove the hook, restoring the original __getitem__. Idempotent."""
	global _active, _original_getitem, _target_class  # noqa: PLW0603
	_active = None
	if _target_class is None:
		return
	_target_class.__getitem__ = _original_getitem  # type: ignore[method-assign]
	_original_getitem = None
	_target_class = None
