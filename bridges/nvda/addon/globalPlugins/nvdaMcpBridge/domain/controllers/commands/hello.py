# nvdaMcpBridge domain -- HelloHandler: the bootstrap command.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `hello` -- the one command valid before the handshake
# completes, and the one that BUILDS the session. Unlike the operational handlers
# (which only read a ready SessionContext), hello is wired with the AdapterFactory
# and the NVDA version, and it populates the context: builds the mode-specific
# adapters, creates the buffers, and starts capture. There is NO synth swap: the
# reader's real synth stays loaded in every mode; silent mode suppresses NVDA's
# speak() output at the speech source instead (see nvda_silent_speech_source), so
# NVDA and other add-ons keep seeing their configured synth as valid and active.
#
# On a protocol-version mismatch it raises CommandError before touching anything
# -- the factory is never called -- and the Session ends the handshake.

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
	# hello starts the journal itself, so there is nothing to mark before it
	# runs; its own window would always be empty (spec 0020).
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
		"""Whether this session normalises, honouring the per-mode default.

		Unset is not "no": the two modes differ and only the caller's silence is
		ambiguous (spec 0024, "Per mode"). SILENT normalises -- the human hears no
		speech anyway, so moving a signal into the speech channel takes nothing
		from them and the agent gains the words. LIVE does not: the human would
		hear "Focus mode" spoken instead of the tone they chose, and that is
		theirs to decide, so it is offered rather than done.
		"""
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
		# Same refusal as setLogLevel, for the same reason: `warning`/`error` are
		# getLog filters, and setting NVDA's floor to one would silence warnings in
		# the user's own nvda.log for the whole session (spec 0020).
		if params.logLevel is not None and params.logLevel.value not in SETTABLE_LEVELS:
			valid = ", ".join(sorted(SETTABLE_LEVELS))
			raise CommandError(
				f"log level {params.logLevel.value!r} cannot be set on the reader: want one of {valid}"
			)
		# Recorded before anything else can fail: the persona is what the rest of
		# the session MEANS (spec 0029), and a session that established without it
		# would produce evidence nobody could attribute. Not validated here -- see
		# SessionContext.persona for why an unrecognised value must not error.
		ctx.persona = params.persona
		# The Session reads this to decide whether a silence cap applies at all: in
		# live mode nothing is suppressed, so there is no silence to bound.
		ctx.mode = params.mode
		ctx.transcript.open()
		# Capture is always on (spec 0009); logLevel, if set, additionally bumps
		# NVDA's own verbosity for the session -- restored at teardown.
		ctx.log_capture.start(params.logLevel)
		adapters = self._factory.build(params.mode)
		# Installed before starting capture, so teardown can stop the sources even
		# if a start() below raises.
		ctx.adapters = adapters

		# Move the reader's inaudible-to-a-session signals into the channel a
		# session CAN read (spec 0024). After ctx.adapters is set, so a failure
		# here is still restored by teardown; before capture starts, so nothing
		# is captured under a configuration the result has not yet disclosed.
		normalized = _normalise(adapters.config_accessor, self._wants_normalisation(params))

		# No exact-finish signal: silent mode suppresses at the speak() filter, so
		# there is no synth "done speaking" to key off; both modes use the buffer's
		# elapsed-time heuristic -- corrected by the reader's own account of
		# whether a continuous read is still going (entry 11.21), which is the one
		# case where the heuristic is not merely imprecise but wrong.
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

		# The reader's real synth stays loaded in every mode; just report it.
		synth = ctx.announcer.current_synth()
		ctx.transcript.session_opened(params.mode, synth, params.persona)

		# The guidance document rides back in the handshake (spec 0022 A.5).
		# Composed here rather than left for `getGuidance` because a POINTER at
		# it is a pointer agents do not follow -- two external runs each had one
		# and each went elsewhere. It costs no round trip: the persona arrived in
		# these very params, and this reply was already being sent.
		#
		# `getGuidance` still answers, unchanged, for a re-read.
		text, recognised = guidance_for(ctx.persona, ctx.gesture_resolver)

		# Whether THIS MACHINE bounds how long a silent session may keep its human
		# mute, and with what thresholds (spec 0032 Part 5). Information and never a
		# control: the agent reads it and cannot write it, because an agent that
		# could raise its own ceiling does not have one. It earns the space because
		# it changes what a well-behaved agent does -- narrate before going quiet on
		# a capped machine, and do not spend round trips narrating to an empty room
		# on an uncapped one. Today an agent cannot tell those apart at all.
		#
		# A machine fact, so it is reported whatever mode was asked for; it simply
		# has nothing to bite on in a live session.
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
			normalized=normalized,
		)


def _normalise(config: ConfigAccessor, wanted: bool) -> list[protocol.NormalizedSetting]:
	"""Apply the admitted channel shifts; report the ones that actually moved.

	A key ALREADY at the wanted value is applied and not reported: "what the
	session asked for" and "what the session changed" are two facts, and an agent
	that reads an empty list knows it is driving the user's own configuration
	untouched -- which is what it needs before it reports a finding.

	Written through the ConfigAccessor, so it is a session-scoped override that
	teardown drops. Nothing reaches the user's disk, and a crash loses it too.

	A ConfigError here RAISES rather than being swallowed. The admitted key is
	the reader's own and long-standing, so a rejection means the session's
	premise -- that the agent can hear a mode change at all -- is false, and a
	session that proceeded quietly would produce exactly the confident, half-blind
	evidence spec 0024 exists to prevent. `normalize: false` is the way past it.
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
