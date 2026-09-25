# nvdaMcpBridge domain -- the AdapterFactory port + the AdapterSet it returns.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, building the mode-specific collaborators once hello has named the capture mode.
# USED BY: the hello handler.
# IMPLEMENTED BY: adapters/nvda_adapter_factory.py; tests/fakes/adapter_factory.py.

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass

from ... import protocol
from .braille_source import BrailleSource
from .config_accessor import ConfigAccessor
from .continuous_read import ContinuousRead
from .document_reader import DocumentReader
from .focus_inspector import FocusInspector
from .gesture_sender import GestureSender
from .speech_source import SpeechSource
from .state_inspector import StateInspector
from .state_setter import StateSetter
from .text_typer import TextTyper


@dataclass(frozen=True)
class AdapterSet:
	speech_source: SpeechSource
	braille_source: BrailleSource
	gesture_sender: GestureSender
	text_typer: TextTyper
	focus_inspector: FocusInspector
	state_inspector: StateInspector
	state_setter: StateSetter
	config_accessor: ConfigAccessor
	continuous_read: ContinuousRead
	document_reader: DocumentReader


class AdapterFactory(ABC):
	"""Builds the :class:`AdapterSet` for a capture mode, known only after hello."""

	@abstractmethod
	def build(self, mode: protocol.CaptureMode) -> AdapterSet:
		"""Construct the collaborators for ``mode``."""
