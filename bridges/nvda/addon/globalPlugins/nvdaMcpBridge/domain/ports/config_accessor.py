# nvdaMcpBridge domain -- the ConfigAccessor port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Reads and writes the reader's in-memory config, and
#       restores every key this session touched at teardown -- so a session is an
#       experiment that never permanently reconfigures a blind person's screen
#       reader, even if it crashes. NEVER persists to disk (no .save() call).
# USED BY: GetConfigHandler, SetConfigHandler, and session teardown
#          (which calls restore_all() via ctx.adapters.config_accessor).
# IMPLEMENTED BY: adapters/nvda_config_accessor.py in session E (walks
#                 config.conf on NVDA's main thread);
#                 tests/fakes/config_accessor.py FakeConfigAccessor.
#
# The key-path vocabulary is opaque to the server and validated only by NVDA:
# a bad path or a value the confspec rejects becomes a CommandError, which the
# session survives (spec 0015).

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class ConfigAccessor(ABC):
    """Reads and writes the reader's config; restores everything at teardown."""

    @abstractmethod
    def get(self, key_path: list[str]) -> Any:
        """Read the config value at ``key_path`` (e.g. ``["speech", "synth"]``).

        Raises ``CommandError`` if the path is invalid.
        """

    @abstractmethod
    def set(self, key_path: list[str], value: Any) -> Any:
        """Write ``value`` at ``key_path`` in the in-memory config.

        Records the prior value on first write to each key so ``restore_all`` can
        undo it. NEVER calls ``.save()`` -- the change is visible to the running
        reader immediately but dies with the process or with ``restore_all``.

        Returns the **prior** value at that path.
        Raises ``CommandError`` if the path or value is rejected.
        """

    @abstractmethod
    def restore_all(self) -> None:
        """Restore every key this session touched to its prior value.

        Called at session teardown, on every exit path. Idempotent: the second
        call is a no-op.
        """
