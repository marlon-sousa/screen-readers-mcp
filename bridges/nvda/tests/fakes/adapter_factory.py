# nvdaMcpBridge tests -- FakeAdapterFactory, standing in for the AdapterFactory port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# FAKES: domain/ports/adapter_factory.py
#
# Assembles the fake NVDA from the individual fakes and hands the SAME instances
# to both the Session (via the AdapterSet it returns) and the test (via its
# attributes), so a test can, e.g., assert the swapper's call order or make a
# gesture speak. It also records the mode it was asked to build for -- the check
# that the Session deferred construction until hello and passed the right mode.
#
# The gesture sender is wired to the speech source here, at construction, exactly
# as the real factory will bind the spy synth to the buffer -- that link is what
# lets a scripted gesture's speech reach the session's buffer.

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import TYPE_CHECKING

from nvdaMcpBridge import protocol as _p
from nvdaMcpBridge.domain.ports.adapter_factory import AdapterFactory, AdapterSet

from .braille_source import FakeBrailleSource
from .config_accessor import FakeConfigAccessor
from .continuous_read import FakeContinuousRead
from .focus_inspector import FakeFocusInspector
from .gesture_sender import FakeGestureSender
from .speech_source import FakeSpeechSource
from .state_inspector import FakeStateInspector
from .state_setter import FakeStateSetter
from .text_typer import FakeTextTyper

if TYPE_CHECKING:
	from nvdaMcpBridge import protocol


class FakeAdapterFactory(AdapterFactory):
	"""Builds a fake AdapterSet and remembers the mode it was built for."""

	def __init__(
		self,
		*,
		reject: Sequence[str] | None = None,
		speech: Mapping[str, Sequence[str]] | None = None,
		type_fail_on: Sequence[str] | None = None,
	) -> None:
		self.speech_source = FakeSpeechSource()
		self.braille_source = FakeBrailleSource()
		self.gesture_sender = FakeGestureSender(self.speech_source, reject=reject, speech=speech)
		self.text_typer = FakeTextTyper(fail_on=type_fail_on)
		self.focus_inspector = FakeFocusInspector()
		self.state_inspector = FakeStateInspector()
		self.state_setter = FakeStateSetter(inspector=self.state_inspector)
		self.config_accessor = FakeConfigAccessor()
		self.continuous_read = FakeContinuousRead()
		self.built_mode: protocol.CaptureMode | None = None

	def build(self, mode: protocol.CaptureMode) -> AdapterSet:
		self.built_mode = mode
		# As production does: only a silent session suppresses anything, so only a
		# silent one can have that suppression lifted (spec 0032).
		self.speech_source.suppressing = mode is _p.CaptureMode.SILENT
		return AdapterSet(
			speech_source=self.speech_source,
			braille_source=self.braille_source,
			gesture_sender=self.gesture_sender,
			text_typer=self.text_typer,
			focus_inspector=self.focus_inspector,
			state_inspector=self.state_inspector,
			state_setter=self.state_setter,
			config_accessor=self.config_accessor,
			continuous_read=self.continuous_read,
		)
