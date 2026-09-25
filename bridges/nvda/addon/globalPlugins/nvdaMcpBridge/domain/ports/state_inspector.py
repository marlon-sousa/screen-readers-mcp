# nvdaMcpBridge domain -- the StateInspector port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port; reads the reader's mode-state: browse mode, speech mode, sleep mode and input help.
# USED BY: the GetStateHandler.
# IMPLEMENTED BY: adapters/nvda_state_inspector.py and tests/fakes/state_inspector.py.
# browse_mode "none" means the focus has no TreeInterceptor, which is not the same as "focus".

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass(frozen=True)
class ReaderState:
	browse_mode: str  # "browse" | "focus" | "none"
	speech_mode: str  # "talk" | "off" | "beeps" | "onDemand"
	sleep_mode: bool
	input_help: bool


class StateInspector(ABC):
	@abstractmethod
	def state(self) -> ReaderState:
		pass
