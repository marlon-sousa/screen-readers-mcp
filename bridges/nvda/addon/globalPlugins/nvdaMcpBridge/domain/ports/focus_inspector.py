# nvdaMcpBridge domain -- the FocusInspector port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Reads what is focused and returns a structured snapshot --
#       name, role, states, value, and the owning app module. "Where am I?" is the
#       agent's first question after pressing a gesture, and this answers it.
# USED BY: the GetFocusInfoHandler.
# IMPLEMENTED BY: adapters/nvda_focus_inspector.py in session E (reads
#                 api.getFocusObject() on NVDA's main thread);
#                 tests/fakes/focus_inspector.py FakeFocusInspector.
#
# Role and state strings go over the wire as stable enum .name values (e.g.
# "BUTTON", "FOCUSED"), never as localized display strings, so an agent's
# assertion passes regardless of the tester's NVDA language (spec 0015).

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class FocusInfo:
    """A snapshot of the current focus object, encoding its role and states as
    stable enum names (not display strings, which are localized)."""

    name: str
    role: str
    states: list[str]
    value: str | None
    app_module: str | None


class FocusInspector(ABC):
    """Answers "what is NVDA focused on right now?"."""

    @abstractmethod
    def focus_info(self) -> FocusInfo:
        """Return the current focus snapshot.

        A null focus (nothing focused) yields an empty ``FocusInfo`` (all fields
        defaulted) rather than raising, so an agent can check for it with a
        normal assertion.
        """
