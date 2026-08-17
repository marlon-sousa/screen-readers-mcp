# Integration scenario: a whole session over the wire, headless.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# Named after the USE CASE, not a file: this drives a REAL session end to end
# through real framing and real dispatch, with no NVDA and no socket. It is the
# recipe lane 2's server<->bridge integration tests build on -- build_session
# over one end of a LoopbackTransport with a fake NVDA, run() on a thread, and
# the test plays the agent on the other end speaking raw protocol. Headless, so
# it runs in CI (unlike the live-NVDA scenarios, which stay milestone 6).

from __future__ import annotations

import threading
import time
from pathlib import Path
from typing import Any

from fakes.adapter_factory import FakeAdapterFactory
from fakes.announcer import FakeAnnouncer
from fakes.log_capture import FakeLogCapture
from fakes.loopback_transport import loopback_pair
from fakes.session_signals import FakeSessionSignals
from fakes.user_prompter import FakeUserPrompter
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES
from nvdaMcpBridge.domain.ports.message_channel import Timeout
from nvdaMcpBridge.wiring import build_session


def _request(id: int, cmd: str, **params: Any) -> p.Request:
	return p.Request(id=id, cmd=cmd, params=dict(params))


def _read_reply(agent: JsonLinesChannel, timeout: float = 5.0) -> dict[str, Any]:
	"""Read past the poll-timeouts until the bridge actually answers."""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		message = agent.read_message()
		if not isinstance(message, Timeout):
			return message
	raise AssertionError("no reply from the bridge within timeout")


def test_a_whole_session_over_the_wire(tmp_path: Path) -> None:
	bridge_end, agent_end = loopback_pair()
	factory = FakeAdapterFactory(speech={"NVDA+f7": ["Elements list dialog"]})
	signals = FakeSessionSignals()
	announcer = FakeAnnouncer()
	log_capture = FakeLogCapture()
	user_prompter = FakeUserPrompter()
	session = build_session(
		bridge_end,
		factory,
		tmp_path,
		"2026.1.0",
		signals,
		announcer,
		log_capture,
		user_prompter,
	)
	agent = JsonLinesChannel(agent_end)

	thread = threading.Thread(target=session.run, daemon=True)
	thread.start()
	try:
		# Handshake.
		agent.write(_request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
		hello = _read_reply(agent)
		assert hello["result"]["mode"] == "silent"
		assert hello["result"]["synth"] == "espeak"
		# The multi-reader handshake fields arrive over the real wire (entry 8).
		assert hello["result"]["reader"] == {"name": "nvda", "version": "2026.1.0"}
		assert hello["result"]["capabilities"] == [c.value for c in NVDA_CAPABILITIES]

		# Echo an awkward payload -- byte-exact through encode/frame/decode/validate.
		payload = {"u": "olá café \U0001f600", "nested": [1, 2, {"x": True}], "n": 3.5}
		agent.write(_request(2, "echo", payload=payload))
		assert _read_reply(agent)["result"]["payload"] == payload

		# Scripted gesture -> speech -> wait-to-finish -> read it back.
		agent.write(_request(3, "pressGesture", gestures=["NVDA+f7"]))
		assert _read_reply(agent)["result"] == {"ok": True}
		# Silent mode has no exact finish now (the synth is untouched), so this
		# resolves on the buffer's ~1s elapsed heuristic -- give it room.
		agent.write(_request(4, "waitForSpeechToFinish", timeout=3.0))
		assert _read_reply(agent, timeout=6.0)["result"]["finished"] is True
		agent.write(_request(5, "getSpeech", sinceIndex=0))
		# One entry per utterance, each with its own index and journal position
		# (spec 0021) -- the joined blob is gone, so the assertion looks per entry.
		entries = _read_reply(agent)["result"]["entries"]
		assert any("Elements list dialog" in entry["text"] for entry in entries)
		assert all("index" in entry and "logPosition" in entry for entry in entries)

		# Announce a hint through the (fake) synth -- bridge->human channel.
		agent.write(_request(6, "announce", text="pressing bye now"))
		assert _read_reply(agent)["result"] == {"ok": True}

		# -- askUser / waitForUserReply (spec 0016) --------------------------
		agent.write(_request(7, "askUser", prompt="plug in the display"))
		ask_reply = _read_reply(agent)["result"]
		ticket = ask_reply["ticket"]
		assert len(ticket) == 12
		# Speech suppression is suspended while the window is open.
		assert factory.speech_source.suspended == 1
		assert len(user_prompter.presented) == 1

		# Poll once before the answer -- answered=false, window still open.
		agent.write(_request(8, "waitForUserReply", ticket=ticket, timeout=0.0))
		poll1 = _read_reply(agent)["result"]
		assert poll1["answered"] is False

		# The human answers (simulating the ack gesture via the entity).
		prompt = session.session_context.get_outstanding_prompt()
		assert prompt is not None
		prompt.answer()

		# Poll again -- answered=true, speech resumed, prompt cleared.
		agent.write(_request(9, "waitForUserReply", ticket=ticket, timeout=0.0))
		poll2 = _read_reply(agent)["result"]
		assert poll2["answered"] is True
		assert factory.speech_source.resumed == 1
		assert session.session_context.get_outstanding_prompt() is None

		# -- introspection commands (entry 11.1) -------------------------------
		# Seed config fake before the session reads it.
		factory.config_accessor.seed(["speech", "synth"], "espeak")

		# getFocusInfo from the seeded fake.
		agent.write(_request(10, "getFocusInfo"))
		focus = _read_reply(agent)["result"]
		assert focus["name"] == "Test Button"
		assert focus["role"] == "BUTTON"
		assert focus["states"] == ["FOCUSABLE", "FOCUSED"]

		# getState from the seeded fake.
		agent.write(_request(11, "getState"))
		state_reply = _read_reply(agent)
		assert state_reply is not None, "no reply for getState"
		assert state_reply.get("error") is None, f"getState error: {state_reply.get('error')}"
		state = state_reply["result"]
		assert state["browseMode"] == "none"
		assert state["speechMode"] == "talk"
		assert state["sleepMode"] is False

		# getConfig reads a pre-seeded key.
		agent.write(_request(12, "getConfig", keyPath=["speech", "synth"]))
		config_read = _read_reply(agent)["result"]
		assert config_read == {"value": "espeak"}

		# setConfig writes and returns the prior value.
		agent.write(_request(13, "setConfig", keyPath=["speech", "synth"], value="sapi5"))
		config_write = _read_reply(agent)["result"]
		assert config_write == {"value": "espeak"}

		# Bye -> ack, then teardown stops capture (speech would flow again).
		agent.write(_request(14, "bye"))
		assert _read_reply(agent)["result"] == {"ok": True}
	finally:
		thread.join(timeout=5.0)

	assert not thread.is_alive()
	assert factory.speech_source.stopped == 1
	assert signals.started == 1 and signals.ended == 1
	assert announcer.announced == ["pressing bye now"]
	# Config was seeded then read/written; teardown should have restored.
	assert factory.config_accessor.get(["speech", "synth"]) == "espeak"
	assert factory.config_accessor.restore_calls >= 1


def test_get_guidance_answers_for_the_persona_hello_declared(tmp_path: Path) -> None:
	"""The persona crosses the wire at hello and decides what getGuidance returns.

	Over a REAL session rather than a hand-built context, because the thing being
	proved is the hop: hello writes the persona into the session, getGuidance
	reads it back, and no parameter is involved. A handler test cannot show that
	-- it sets ``ctx.persona`` itself.
	"""
	text, unknown_text = _guidance_over_a_session(tmp_path, "expert", "auditor")

	assert "`expert` stance" in text
	# The unknown persona is the case the SERVER's own tool surface can never
	# reach, because connect_reader validates the value at its boundary
	# (spec 0029 3.1). Here nothing validates it, which is the point: this is
	# what an older bridge sees when a newer server adds a fourth persona, and
	# it must be an ordinary answer rather than a failed handshake.
	assert "No section for the persona you declared" in unknown_text


def _guidance_over_a_session(tmp_path: Path, *personas: str) -> tuple[str, ...]:
	"""Run one real session per persona and return each getGuidance text."""
	texts: list[str] = []
	for index, persona in enumerate(personas):
		bridge_end, agent_end = loopback_pair()
		session = build_session(
			bridge_end,
			FakeAdapterFactory(),
			tmp_path / f"session{index}",
			"2026.1.0",
			FakeSessionSignals(),
			FakeAnnouncer(),
			FakeLogCapture(),
			FakeUserPrompter(),
		)
		agent = JsonLinesChannel(agent_end)
		thread = threading.Thread(target=session.run, daemon=True)
		thread.start()
		try:
			agent.write(
				_request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION, persona=persona)
			)
			hello = _read_reply(agent)
			# The handshake SUCCEEDS whatever the persona is -- including one this
			# bridge has never heard of (protocol.md §4).
			assert hello["result"]["mode"] == "silent"
			assert p.Capability.GUIDANCE.value in hello["result"]["capabilities"]

			agent.write(_request(2, "getGuidance"))
			guidance = _read_reply(agent)["result"]
			# Echoed as received, and answered for the session's own persona:
			# there is no parameter to have got wrong.
			assert guidance["persona"] == persona
			assert guidance["recognised"] is (persona != "auditor")
			texts.append(guidance["text"])

			agent.write(_request(3, "bye"))
			_read_reply(agent)
		finally:
			thread.join(timeout=5.0)
	return tuple(texts)
