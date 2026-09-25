# nvdaMcpBridge adapters -- NvdaAdapterFactory: builds the real AdapterSet.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing AdapterFactory, picking the speech source for the capture mode.
# BUILT BY: wiring.build_session.
# USED BY: the hello handler.

from __future__ import annotations

from .. import protocol
from ..domain.ports.adapter_factory import AdapterFactory, AdapterSet
from .nvda_braille_source import NvdaBrailleSource
from .nvda_config_accessor import NvdaConfigAccessor
from .nvda_continuous_read import NvdaContinuousRead
from .nvda_document_reader import NvdaDocumentReader
from .nvda_focus_inspector import NvdaFocusInspector
from .nvda_gesture_sender import NvdaGestureSender
from .nvda_live_speech_source import NvdaLiveSpeechSource
from .nvda_silent_speech_source import NvdaSilentSpeechSource
from .nvda_state_inspector import NvdaStateInspector
from .nvda_state_setter import NvdaStateSetter
from .nvda_text_typer import NvdaTextTyper


class NvdaAdapterFactory(AdapterFactory):
	def build(self, mode: protocol.CaptureMode) -> AdapterSet:
		silent = mode is protocol.CaptureMode.SILENT
		speech_source = NvdaSilentSpeechSource() if silent else NvdaLiveSpeechSource()
		return AdapterSet(
			speech_source=speech_source,
			braille_source=NvdaBrailleSource(),
			gesture_sender=NvdaGestureSender(),
			text_typer=NvdaTextTyper(),
			focus_inspector=NvdaFocusInspector(),
			state_inspector=NvdaStateInspector(),
			state_setter=NvdaStateSetter(),
			config_accessor=NvdaConfigAccessor(),
			continuous_read=NvdaContinuousRead(),
			document_reader=NvdaDocumentReader(),
		)
