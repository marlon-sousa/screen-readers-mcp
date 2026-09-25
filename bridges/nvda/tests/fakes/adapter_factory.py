# nvdaMcpBridge tests -- FakeAdapterFactory, standing in for the AdapterFactory port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# Hands the same fake instances to the Session and to the test's attributes.

from __future__ import annotations

from collections.abc import Mapping, Sequence
from typing import TYPE_CHECKING

from nvdaMcpBridge import protocol as _p
from nvdaMcpBridge.domain.ports.adapter_factory import AdapterFactory, AdapterSet

from .braille_source import FakeBrailleSource
from .config_accessor import FakeConfigAccessor
from .continuous_read import FakeContinuousRead
from .document_reader import FakeDocumentReader
from .focus_inspector import FakeFocusInspector
from .gesture_sender import FakeGestureSender
from .speech_source import FakeSpeechSource
from .state_inspector import FakeStateInspector
from .state_setter import FakeStateSetter
from .text_typer import FakeTextTyper

if TYPE_CHECKING:
	from nvdaMcpBridge import protocol


class FakeAdapterFactory(AdapterFactory):
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
		self.document_reader = FakeDocumentReader()
		self.built_mode: protocol.CaptureMode | None = None

	def build(self, mode: protocol.CaptureMode) -> AdapterSet:
		self.built_mode = mode
		# As in production, only a silent session suppresses, so only it can have suppression lifted.
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
			document_reader=self.document_reader,
		)
