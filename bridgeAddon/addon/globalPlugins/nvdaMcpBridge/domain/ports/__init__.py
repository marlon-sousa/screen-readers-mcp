# nvdaMcpBridge domain -- the ports (abstract interfaces the domain depends on).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# These are the seams of the hexagon, one port per file. The domain (session
# state machine, speech buffers, framing) is written against these ABCs and
# nothing else; the ``adapters/`` package provides one concrete subclass of each
# (NVDA-backed in production, in-memory fakes in tests), and ``wiring.py`` is the
# only place that binds the two together.
#
# They are ``abc.ABC`` with ``@abstractmethod`` -- not ``typing.Protocol`` -- on
# purpose: an adapter that forgets a method fails loudly at construction, and
# the interface itself can never be instantiated. A port's own DTO (e.g.
# ``AdapterSet``) lives in the same file as the port that returns it.
#
# This package re-exports every port so callers import ``from ..ports import X``
# without caring which file it lives in.

from __future__ import annotations

from .adapter_factory import AdapterFactory, AdapterSet
from .clock import Clock
from .gesture_sender import GestureSender
from .speech_source import SpeechSource
from .synth_swapper import SynthSwapper
from .transcript import Transcript
from .transport import Transport

__all__ = [
	"AdapterFactory",
	"AdapterSet",
	"Clock",
	"GestureSender",
	"SpeechSource",
	"SynthSwapper",
	"Transcript",
	"Transport",
]
