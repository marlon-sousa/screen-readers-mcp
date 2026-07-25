# nvdaMcpBridge adapters -- NvdaConfigAccessor: read/write/restore the reader's config.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the ConfigAccessor port. On pyright's ignore list
#       (imports NVDA); validated by the 11.1 live-NVDA checklist.
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: GetConfigHandler, SetConfigHandler, and session teardown
#          (which calls restore_all via ctx.adapters.config_accessor).
#
# THE RULE: never call config.conf.save(). Every key this session touches is
# recorded on first write and restored at teardown, so the session is an
# experiment that never permanently reconfigures a blind person's screen reader
# -- even if it crashes. The precedent is spec 0009's logLevel restore.
#
# A hard kill of NVDA itself needs no cleanup code because the unsaved in-memory
# change dies with the process. Restore-at-teardown only has to cover the case
# where the session ends while NVDA keeps running, which is exactly what the
# session's existing teardown machinery already handles.

from __future__ import annotations

from typing import Any

import config

from ..domain.controllers.commands.command_handler import CommandError
from ..domain.ports.config_accessor import ConfigAccessor
from .nvda_main_thread import run_on_main


class NvdaConfigAccessor(ConfigAccessor):
    """Walks config.conf on NVDA's main thread; never persists to disk."""

    def __init__(self) -> None:
        self._prior: dict[tuple[str, ...], Any] = {}
        self._restored = False

    def get(self, key_path: list[str]) -> Any:
        return run_on_main(lambda: self._get(key_path), block=True)

    def set(self, key_path: list[str], value: Any) -> Any:
        return run_on_main(lambda: self._set(key_path, value), block=True)

    def restore_all(self) -> None:
        if self._restored:
            return
        self._restored = True
        run_on_main(self._restore_impl)

    # -- main-thread helpers --------------------------------------------------

    @staticmethod
    def _get(key_path: list[str]) -> Any:
        try:
            node: Any = config.conf
            for key in key_path:
                node = node[key]
            return node
        except (KeyError, TypeError, AttributeError) as exc:
            raise CommandError(f"invalid config key path {key_path!r}: {exc}") from exc

    def _set(self, key_path: list[str], value: Any) -> Any:
        # Read the current value (will raise if the path is invalid -- no half-done
        # writes if the key doesn't exist).
        try:
            node: Any = config.conf
            for key in key_path:
                node = node[key]
            prior = node
        except (KeyError, TypeError, AttributeError) as exc:
            raise CommandError(f"invalid config key path {key_path!r}: {exc}") from exc

        # Record the prior value on first write to this key (idempotent).
        key_t = tuple(key_path)
        if key_t not in self._prior:
            self._prior[key_t] = prior

        # Walk again to write: stop one level early so we can mutate the container.
        try:
            node = config.conf
            for key in key_path[:-1]:
                node = node[key]
            node[key_path[-1]] = value
        except (KeyError, TypeError, AttributeError) as exc:
            raise CommandError(f"cannot set config key path {key_path!r}: {exc}") from exc

        return prior

    def _restore_impl(self) -> None:
        for key_path, prior_value in self._prior.items():
            try:
                node: Any = config.conf
                for key in key_path[:-1]:
                    node = node[key]
                node[key_path[-1]] = prior_value
            except Exception:
                # Guarded restoration: a single key restore failure does not stop
                # the remaining restores, matching the _guard pattern in session.py.
                pass
