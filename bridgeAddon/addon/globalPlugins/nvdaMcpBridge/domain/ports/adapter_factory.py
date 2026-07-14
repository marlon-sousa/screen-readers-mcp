# nvdaMcpBridge domain -- the AdapterFactory port (and the AdapterSet it returns).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import TYPE_CHECKING

from .gesture_sender import GestureSender
from .speech_source import SpeechSource
from .synth_swapper import SynthSwapper

if TYPE_CHECKING:
	from ... import protocol as p


@dataclass
class AdapterSet:
	"""The session-scoped, mode-specific adapters the factory hands back."""

	speech_source: SpeechSource
	synth_swapper: SynthSwapper
	gesture_sender: GestureSender


class AdapterFactory(ABC):
	"""Builds the mode-specific adapter set once the handshake reveals the mode.

	This is the injection seam that keeps mode out of construction order: the
	composition root wires a factory, and only after reading ``hello`` does the
	session ask it to build the silent- or live-mode adapters. The real factory
	(session C) builds NVDA-backed adapters; the test factory builds fakes.
	"""

	@abstractmethod
	def build(self, mode: p.CaptureMode) -> AdapterSet: ...
