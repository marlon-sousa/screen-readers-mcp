# nvdaMcpBridge domain -- the StateInspector port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. Reads the reader's current mode-state: whether it is in
#       browse or focus mode, whether speech is on, whether it is asleep, and
#       whether input help is active. These are signalled by sound rather than
#       speech -- an agent that diffed two get_speech snapshots across NVDA+space
#       would see nothing change, but the mode DID change, and this port is the
#       channel for that question.
# USED BY: the GetStateHandler.
# IMPLEMENTED BY: adapters/nvda_state_inspector.py in session E (reads
#                 speech.getState(), api.getFocusObject().sleepMode,
#                 inputCore.manager.isInputHelpActive, and derives the browse-mode
#                 tri-state); tests/fakes/state_inspector.py FakeStateInspector.
#
# browse_mode is a tri-state string, not a nullable bool (spec 0015):
#   "browse" -- the focus has a TreeInterceptor with passThrough False.
#   "focus"  -- the focus has a TreeInterceptor with passThrough True.
#   "none"   -- the focus has no TreeInterceptor (e.g. a plain Win32 dialog).
# A nullable bool would collapse "none" to None and "focus" to False, making a
# naive ``if not result.browseMode`` conflate the two, which is exactly the class
# of ambiguity this project exists to remove.

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class ReaderState:
    """A snapshot of the reader's mode-state, all sent as stable names."""

    browse_mode: str  # "browse" | "focus" | "none"
    speech_mode: str  # "talk" | "off" | "beeps" | "onDemand"
    sleep_mode: bool
    input_help: bool


class StateInspector(ABC):
    """Answers "what mode is the reader in right now?"."""

    @abstractmethod
    def state(self) -> ReaderState:
        """Return the current reader state snapshot."""
