# nvdaMcpBridge domain -- HelloHandler: the bootstrap command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `hello`, the one command valid before the handshake; it builds the session's
#       adapters and buffers.
# A protocol-version mismatch raises CommandError before the factory is called.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.braille_buffer import BrailleBuffer
from ...entities.channel_normalisation import ADMITTED_SETTINGS
from ...entities.log_journal import SETTABLE_LEVELS
from ...entities.reader_guidance import guidance_for
from ...entities.speech_buffer import SpeechBuffer
from ...ports.config_accessor import ConfigAccessor, ConfigError
from .command_handler import CommandError, CommandHandler

if TYPE_CHECKING:
	from ....protocol import Capability, ReaderInfo
	from ...ports.adapter_factory import AdapterFactory
	from .session_context import SessionContext


class HelloHandler(CommandHandler):
	available_before_hello = True
	# hello starts the journal, so its own window would always be empty.
	marks_log = False

	def __init__(
		self,
		factory: AdapterFactory,
		reader: ReaderInfo,
		capabilities: list[Capability],
		bridge_version: str,
	) -> None:
		self._factory = factory
		self._reader = reader
		self._capabilities = capabilities
		self._bridge_version = bridge_version

	@staticmethod
	def _wants_normalisation(params: protocol.HelloParams) -> bool:
		"""Unset follows the mode: silent normalises; live does not, its user would hear words, not a tone."""
		if params.normalize is not None:
			return params.normalize
		return params.mode is protocol.CaptureMode.SILENT

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.HelloParams, request.params)
		if params.protocolVersion != protocol.PROTOCOL_VERSION:
			raise CommandError(
				f"protocol version mismatch: bridge speaks {protocol.PROTOCOL_VERSION}, "
				f"client sent {params.protocolVersion}"
			)
		# warning and error are filters only; setting NVDA's level to one would silence warnings in the user's
		# own nvda.log for the whole session.
		if params.logLevel is not None and params.logLevel.value not in SETTABLE_LEVELS:
			valid = ", ".join(sorted(SETTABLE_LEVELS))
			raise CommandError(
				f"log level {params.logLevel.value!r} cannot be set on the reader: want one of {valid}"
			)
		# Recorded before anything else can fail, so the session's evidence stays attributable.
		ctx.persona = params.persona
		ctx.mode = params.mode
		ctx.transcript.open()
		# logLevel, if set, raises NVDA's own level until teardown.
		ctx.log_capture.start(params.logLevel)
		adapters = self._factory.build(params.mode)
		# Installed before capture starts, so teardown can stop the sources if a start() raises.
		ctx.adapters = adapters

		# After ctx.adapters is set, so teardown restores it; before capture, so nothing is captured under a
		# configuration the result has not disclosed.
		normalized = _normalise(adapters.config_accessor, self._wants_normalisation(params))

		# Silent mode has no synth done-signal, so both modes use the elapsed-time heuristic, corrected by the
		# reader's continuous-read state.
		speech = SpeechBuffer(
			ctx.clock,
			exact_finish=False,
			continuous_read=adapters.continuous_read,
		)
		braille = BrailleBuffer(ctx.clock)
		speech.set_observer(ctx.transcript.speech)
		ctx.speech = speech
		ctx.braille = braille
		adapters.speech_source.start(speech, ctx.log_capture.position)
		adapters.braille_source.start(braille, ctx.log_capture.position)

		synth = ctx.announcer.current_synth()
		ctx.transcript.session_opened(params.mode, synth, params.persona)

		text, recognised = guidance_for(ctx.persona, ctx.gesture_resolver)

		# Reported, never settable: an agent that could raise its own ceiling would not have one.
		policy = ctx.silence_cap_policy
		silence_cap = (
			None
			if policy is None
			else protocol.SilenceCapInfo(
				enabled=policy.enabled,
				warnAfterSeconds=policy.warn_after,
				liftAfterSeconds=policy.lift_after,
			)
		)

		return protocol.HelloResult(
			protocolVersion=protocol.PROTOCOL_VERSION,
			reader=self._reader,
			capabilities=self._capabilities,
			mode=params.mode,
			synth=synth,
			logPath=ctx.transcript.path,
			bridgeVersion=self._bridge_version,
			guidance=protocol.GetGuidanceResult(
				persona=ctx.persona,
				recognised=recognised,
				text=text,
			),
			silenceCap=silence_cap,
			# Always sent by this bridge; absent means a bridge that does not know, and the server then
			# infers it from silenceCap.enabled.
			attended=ctx.attended,
			normalized=normalized,
		)


def _normalise(config: ConfigAccessor, wanted: bool) -> list[protocol.NormalizedSetting]:
	"""Apply the admitted channel shifts and report the ones that moved.

	A key already at the wanted value is left alone and not reported. A ConfigError raises, because the
	session's premise that the agent can hear a mode change would be false.
	"""
	if not wanted:
		return []
	normalized: list[protocol.NormalizedSetting] = []
	for admitted in ADMITTED_SETTINGS:
		key_path = list(admitted.key_path)
		try:
			current = config.get(key_path)
			if current == admitted.value:
				continue
			prior = config.set(key_path, admitted.value)
		except ConfigError as exc:
			raise CommandError(
				f"cannot normalise {'.'.join(key_path)}: {exc}. Pass normalize: false to connect without it."
			) from exc
		normalized.append(
			protocol.NormalizedSetting(
				keyPath=key_path,
				previous=prior,
				current=admitted.value,
				why=admitted.why,
			)
		)
	return normalized
