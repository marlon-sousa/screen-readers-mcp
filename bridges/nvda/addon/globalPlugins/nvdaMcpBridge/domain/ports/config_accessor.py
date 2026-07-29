# nvdaMcpBridge domain -- the ConfigAccessor port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Reads the reader's config, and applies session-scoped
#       OVERRIDES to it that are dropped at teardown -- so a session is an
#       experiment that never permanently reconfigures a blind person's screen
#       reader, even if it crashes. NEVER persists to disk (no .save() call) and,
#       since the 2026-07-26 amendment, never writes to the reader's config at
#       all: an override is a read-time layer above the profile stack.
# USED BY: GetConfigHandler, SetConfigHandler, and session teardown
#          (which calls restore_all() via ctx.adapters.config_accessor).
# IMPLEMENTED BY: adapters/nvda_config_accessor.py in session E (an override map
#                 plus a hook on NVDA's AggregatedSection.__getitem__);
#                 tests/fakes/config_accessor.py FakeConfigAccessor.
#
# ConfigError is part of this port's contract, so it lives here -- the same rule
# gesture_sender.py and text_typer.py follow. A bad key path or a value the
# reader's own schema rejects is a normal, per-command failure the Session
# reports and recovers from, not a session-ending fault (spec 0015).

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class ConfigError(Exception):
    """A key path the reader does not define, or a value its schema rejects."""


class ConfigAccessor(ABC):
    """Reads the reader's config and layers session-scoped overrides over it."""

    @abstractmethod
    def get(self, key_path: list[str]) -> Any:
        """Read the effective value at ``key_path`` (e.g. ``["speech", "synth"]``).

        Effective means: this session's override if one is set, otherwise the
        reader's own profile-resolved value.

        Raises :class:`ConfigError` if the path is invalid.
        """

    @abstractmethod
    def set(self, key_path: list[str], value: Any) -> Any:
        """Override ``key_path`` with ``value`` for the rest of the session.

        The reader's stored configuration is NOT written -- the override is a
        read-time layer that every consumer of the reader's config sees, and it
        sits above the profile stack, so switching profiles mid-session cannot
        displace it. It dies with ``restore_all`` or with the process.

        ``value`` is validated and coerced against the reader's own schema
        first, so an override can never inject a type the reader would have
        refused to store.

        Returns the **prior** effective value at that path, captured on the
        first override of that key.
        Raises :class:`ConfigError` if the path or the value is rejected.
        """

    @abstractmethod
    def restore_all(self) -> None:
        """Drop every override this session set, restoring the reader's own values.

        Nothing was ever written, so this is a discard rather than a rewrite.
        Called at session teardown, on every exit path. Idempotent: the second
        call is a no-op.
        """
