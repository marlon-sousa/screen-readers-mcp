# Unit tests for domain/controllers/commands/hello.py.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import pytest
from fakes.adapter_factory import FakeAdapterFactory
from fakes.clock import FakeClock
from fakes.log_capture import FakeLogCapture
from fakes.transcript import FakeTranscript
from nvdaMcpBridge import protocol as p
from support.context import make_context

#: Stand-in for the installed add-on version reported in hello.
BRIDGE_VERSION = "9.9.9-test"
from nvdaMcpBridge.domain.controllers.commands.command_handler import CommandError
from nvdaMcpBridge.domain.controllers.commands.hello import HelloHandler
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES


def _hello(
	mode: str,
	version: int = p.PROTOCOL_VERSION,
	*,
	log_level: p.LogLevel | None = None,
	persona: str | None = None,
	normalize: bool | None = None,
) -> p.Request:
	params: dict[str, object] = {"mode": mode, "protocolVersion": version}
	if log_level is not None:
		params["logLevel"] = log_level.value
	if normalize is not None:
		params["normalize"] = normalize
	if persona is not None:
		params["persona"] = persona
	return p.Request(id=1, cmd="hello", params=params)


def _handler(factory: FakeAdapterFactory, version: str = "2026.1.0") -> HelloHandler:
	# The bridge stamps its NVDA identity + the capabilities it serves (as wiring
	# does): speech/braille/gestures, not the full enum -- see NVDA_CAPABILITIES.
	return HelloHandler(
		factory,
		p.ReaderInfo(name="nvda", version=version),
		list(NVDA_CAPABILITIES),
		BRIDGE_VERSION,
	)


def test_silent_hello_builds_and_reports(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	log_capture = FakeLogCapture()
	ctx = make_context(clock, transcript=transcript, log_capture=log_capture)
	result = _handler(factory).execute(ctx, _hello("silent"))

	assert factory.built_mode is p.CaptureMode.SILENT
	assert factory.speech_source.started == 1 and factory.braille_source.started == 1
	assert factory.speech_source.buffer is ctx.speech

	assert isinstance(result, p.HelloResult)
	assert result.mode is p.CaptureMode.SILENT
	# The real synth is read via the announcer and never swapped.
	assert result.synth == "espeak"
	assert result.reader == p.ReaderInfo(name="nvda", version="2026.1.0")
	assert result.capabilities == list(NVDA_CAPABILITIES)
	assert result.logPath == transcript.path

	# No logLevel requested -- capture still starts, just with no level change.
	assert log_capture.events == [("start", None)]

	# No synth swap event -- the synth is left loaded; capture is via the filter.
	assert transcript.events[:2] == [
		("open",),
		("session_opened", p.CaptureMode.SILENT, "espeak", ""),
	]
	assert all(event[0] != "synth_swapped" for event in transcript.events)


# -- persona (spec 0029) ------------------------------------------------------


def test_hello_records_the_declared_persona(clock: FakeClock) -> None:
	transcript = FakeTranscript()
	ctx = make_context(clock, transcript=transcript)
	_handler(FakeAdapterFactory()).execute(ctx, _hello("silent", persona="validator"))

	# On the context, for the Session to speak at the start cue...
	assert ctx.persona == "validator"
	# ...and in the transcript, which is how a run is attributed afterwards.
	assert ("session_opened", p.CaptureMode.SILENT, "espeak", "validator") in transcript.events


def test_an_unrecognised_persona_is_recorded_rather_than_refused(clock: FakeClock) -> None:
	"""protocol.md §4: the bridge must DEGRADE, never error.

	The server owns the set of personas. If a value this bridge has never heard of
	failed the handshake, adding a persona upstream would mean a synchronised
	release across every bridge in the field -- so an unknown one is simply
	carried, and it is the guidance served later (11.20) that says it was not
	recognised.
	"""
	ctx = make_context(clock)
	result = _handler(FakeAdapterFactory()).execute(ctx, _hello("silent", persona="archaeologist"))

	assert isinstance(result, p.HelloResult)
	assert ctx.persona == "archaeologist"


def test_a_hello_without_a_persona_still_handshakes(clock: FakeClock) -> None:
	"""An older server declares none; the field is optional and defaults empty."""
	ctx = make_context(clock)
	result = _handler(FakeAdapterFactory()).execute(ctx, _hello("silent"))

	assert isinstance(result, p.HelloResult)
	assert ctx.persona == ""


def test_hello_with_log_level_starts_capture_at_that_level(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	log_capture = FakeLogCapture()
	ctx = make_context(clock, log_capture=log_capture)
	_handler(factory).execute(ctx, _hello("silent", log_level=p.LogLevel.DEBUG))

	assert log_capture.events == [("start", p.LogLevel.DEBUG)]


def test_live_hello_builds_and_reports(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	ctx = make_context(clock, transcript=transcript)
	result = _handler(factory, "x").execute(ctx, _hello("live"))

	assert factory.built_mode is p.CaptureMode.LIVE
	assert isinstance(result, p.HelloResult)
	assert result.mode is p.CaptureMode.LIVE
	assert all(event[0] != "synth_swapped" for event in transcript.events)


def test_version_mismatch_raises_before_building(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	log_capture = FakeLogCapture()
	ctx = make_context(clock, transcript=transcript, log_capture=log_capture)
	with pytest.raises(CommandError) as exc:
		_handler(factory, "x").execute(ctx, _hello("silent", p.PROTOCOL_VERSION + 1))

	message = str(exc.value)
	assert str(p.PROTOCOL_VERSION) in message and str(p.PROTOCOL_VERSION + 1) in message
	assert factory.built_mode is None
	assert transcript.opened is False
	assert log_capture.events == []


def test_captured_speech_flows_to_the_transcript(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	transcript = FakeTranscript()
	ctx = make_context(clock, transcript=transcript)
	_handler(factory, "x").execute(ctx, _hello("silent"))
	ctx.speech_buffer.append(["Elements list"])
	assert ("speech", "Elements list") in transcript.events


# -- the guidance document rides in the handshake (spec 0022 A.5) -------------


def test_hello_returns_the_guidance_document_for_the_declared_persona(
	clock: FakeClock,
) -> None:
	"""The document arrives WITH the session, not on a later request.

	A pointer at it is a pointer agents do not follow: two external runs (specs
	0027 and 0030) each held one and each went elsewhere. It costs nothing to
	send -- the persona arrived in these very params, and this reply was already
	being written.
	"""
	ctx = make_context(clock)

	result = _handler(FakeAdapterFactory()).execute(ctx, _hello("silent", persona="user"))

	assert result.guidance is not None
	# Echoed AS RECEIVED, like getGuidance's, so a server can tell which
	# declaration the document answers without its own bookkeeping.
	assert result.guidance.persona == "user"
	assert result.guidance.recognised is True
	assert result.guidance.text.strip() != ""


def test_the_handshake_document_matches_what_get_guidance_would_answer(
	clock: FakeClock,
) -> None:
	"""One document, two routes -- so the two cannot describe it differently.

	``getGuidance`` remains for a re-read; what must never happen is the
	handshake and the command disagreeing about the same session's stance.
	"""
	from nvdaMcpBridge.domain.controllers.commands.get_guidance import GetGuidanceHandler

	ctx = make_context(clock)
	handshake = _handler(FakeAdapterFactory()).execute(ctx, _hello("silent", persona="expert"))

	on_demand = GetGuidanceHandler().execute(ctx, p.Request(id=2, cmd="getGuidance", params={}))

	assert handshake.guidance is not None
	assert handshake.guidance.text == on_demand.text
	assert handshake.guidance.recognised == on_demand.recognised
	assert handshake.guidance.persona == on_demand.persona


def test_an_unrecognised_persona_still_gets_a_document_marked_unrecognised(
	clock: FakeClock,
) -> None:
	"""Degrading, never erroring -- the same carve-out the persona itself gets.

	``recognised=False`` with the general text is a real answer, and a necessary
	one: silence would leave an agent believing it had been instructed when it
	had not.
	"""
	ctx = make_context(clock)

	result = _handler(FakeAdapterFactory()).execute(ctx, _hello("silent", persona="archaeologist"))

	assert result.guidance is not None
	assert result.guidance.persona == "archaeologist"
	assert result.guidance.recognised is False
	assert result.guidance.text.strip() != ""


# -- channel normalisation (spec 0024) ----------------------------------------

#: The one key the membership test admits today.
_TONE_KEY = ["virtualBuffers", "passThroughAudioIndication"]


def test_silent_normalises_by_default_and_discloses_it(clock: FakeClock) -> None:
	# Silent is the case where the split is total: the human hears no speech
	# anyway, so moving the mode-change signal into the speech channel takes
	# nothing from them and the agent gains the words.
	factory = FakeAdapterFactory()
	ctx = make_context(clock)
	result = _handler(factory).execute(ctx, _hello("silent"))

	assert factory.config_accessor.store[tuple(_TONE_KEY)] is False
	assert len(result.normalized) == 1
	disclosed = result.normalized[0]
	assert disclosed.keyPath == _TONE_KEY
	assert disclosed.previous is True and disclosed.current is False
	# The reason is fixed data, not runtime prose: it is read by humans who will
	# not have the spec open.
	assert disclosed.why == "browse/focus mode changes are a wave file by default"


def test_live_does_not_normalise_unless_asked(clock: FakeClock) -> None:
	# In live mode the change is AUDIBLE -- the human would hear "Focus mode"
	# spoken instead of the tone they chose -- so it is theirs to decide.
	factory = FakeAdapterFactory()
	result = _handler(factory).execute(make_context(clock), _hello("live"))

	assert result.normalized == []
	assert factory.config_accessor.store[tuple(_TONE_KEY)] is True


def test_live_normalises_when_the_session_opts_in(clock: FakeClock) -> None:
	factory = FakeAdapterFactory()
	result = _handler(factory).execute(make_context(clock), _hello("live", normalize=True))

	assert [entry.keyPath for entry in result.normalized] == [_TONE_KEY]
	assert factory.config_accessor.store[tuple(_TONE_KEY)] is False


def test_silent_can_opt_out(clock: FakeClock) -> None:
	# The escape hatch matters: a session debugging the tone behaviour ITSELF
	# wants the reader exactly as its user left it.
	factory = FakeAdapterFactory()
	result = _handler(factory).execute(make_context(clock), _hello("silent", normalize=False))

	assert result.normalized == []
	assert factory.config_accessor.set_calls == []


def test_a_key_already_at_the_wanted_value_is_not_reported(clock: FakeClock) -> None:
	# "What the session asked for" and "what the session changed" are two facts.
	# An agent reading an empty list is being told it is on the user's own
	# configuration -- so a key that needed no write must not appear.
	factory = FakeAdapterFactory()
	factory.config_accessor.seed(_TONE_KEY, False)
	result = _handler(factory).execute(make_context(clock), _hello("silent"))

	assert result.normalized == []
	assert factory.config_accessor.set_calls == []


def test_a_reader_that_rejects_the_key_fails_loudly(clock: FakeClock) -> None:
	# Not swallowed: a rejection means the session's premise -- that the agent can
	# hear a mode change at all -- is false, and a session that proceeded quietly
	# would produce exactly the confident, half-blind evidence 0024 exists to
	# prevent. The message names the way past it.
	factory = FakeAdapterFactory()
	factory.config_accessor.forget(_TONE_KEY)
	with pytest.raises(CommandError) as caught:
		_handler(factory).execute(make_context(clock), _hello("silent"))
	assert "normalize: false" in str(caught.value)
