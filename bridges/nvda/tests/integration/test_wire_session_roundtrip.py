# Integration scenario: a whole session over the wire, headless.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import threading
from pathlib import Path

from fakes.adapter_factory import FakeAdapterFactory
from fakes.announcer import FakeAnnouncer
from fakes.gesture_resolver import FakeGestureResolver
from fakes.log_capture import FakeLogCapture
from fakes.loopback_transport import loopback_pair
from fakes.session_signals import FakeSessionSignals
from fakes.user_prompter import FakeUserPrompter
from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES
from nvdaMcpBridge.wiring import build_session
from support.roundtrip import read_reply, request


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
		FakeGestureResolver(),
	)
	agent = JsonLinesChannel(agent_end)

	thread = threading.Thread(target=session.run, daemon=True)
	thread.start()
	try:
		agent.write(request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION))
		hello = read_reply(agent, awaiting="hello")
		assert hello["result"]["mode"] == "silent"
		assert hello["result"]["synth"] == "espeak"
		assert hello["result"]["reader"] == {"name": "nvda", "version": "2026.1.0"}
		assert hello["result"]["capabilities"] == [c.value for c in NVDA_CAPABILITIES]

		payload = {"u": "olá café \U0001f600", "nested": [1, 2, {"x": True}], "n": 3.5}
		agent.write(request(2, "echo", payload=payload))
		assert read_reply(agent, awaiting="echo (id 2)")["result"]["payload"] == payload

		agent.write(request(3, "pressGesture", gestures=["NVDA+f7"]))
		pressed = read_reply(agent, awaiting="pressGesture (id 3)")["result"]
		assert [p["gesture"] for p in pressed["pressed"]] == ["NVDA+f7"]
		assert any("Elements list dialog" in e["text"] for e in pressed["speech"])
		assert pressed["speechTo"] > pressed["speechFrom"]
		assert pressed["state"]["speechMode"] == "talk"
		agent.write(request(4, "waitForSpeechToFinish", timeout=3.0))
		assert (
			read_reply(agent, awaiting="waitForSpeechToFinish (id 4)", polls=120)["result"]["finished"]
			is True
		)
		agent.write(request(5, "getSpeech", sinceIndex=0))
		entries = read_reply(agent, awaiting="getSpeech (id 5)")["result"]["entries"]
		assert any("Elements list dialog" in entry["text"] for entry in entries)
		assert all("index" in entry and "logPosition" in entry for entry in entries)

		agent.write(request(6, "announce", text="pressing bye now"))
		assert read_reply(agent, awaiting="announce (id 6)")["result"] == {"ok": True}

		agent.write(request(7, "askUser", prompt="plug in the display"))
		ask_reply = read_reply(agent, awaiting="askUser (id 7)")["result"]
		ticket = ask_reply["ticket"]
		assert len(ticket) == 12
		assert factory.speech_source.suspended == 1
		assert len(user_prompter.presented) == 1

		agent.write(request(8, "waitForUserReply", ticket=ticket, timeout=0.0))
		poll1 = read_reply(agent, awaiting="waitForUserReply (id 8)")["result"]
		assert poll1["answered"] is False

		prompt = session.session_context.get_outstanding_prompt()
		assert prompt is not None
		prompt.answer()

		agent.write(request(9, "waitForUserReply", ticket=ticket, timeout=0.0))
		poll2 = read_reply(agent, awaiting="waitForUserReply (id 9)")["result"]
		assert poll2["answered"] is True
		assert factory.speech_source.resumed == 1
		assert session.session_context.get_outstanding_prompt() is None

		factory.config_accessor.seed(["speech", "synth"], "espeak")

		agent.write(request(10, "getFocusInfo"))
		focus = read_reply(agent, awaiting="getFocusInfo (id 10)")["result"]
		assert focus["name"] == "Test Button"
		assert focus["role"] == "BUTTON"
		assert focus["states"] == ["FOCUSABLE", "FOCUSED"]

		agent.write(request(11, "getState"))
		state_reply = read_reply(agent, awaiting="getState (id 11)")
		assert state_reply is not None, "no reply for getState"
		assert state_reply.get("error") is None, f"getState error: {state_reply.get('error')}"
		state = state_reply["result"]
		assert state["browseMode"] == "browse"
		assert state["speechMode"] == "talk"
		assert state["sleepMode"] is False

		agent.write(request(12, "getConfig", keyPath=["speech", "synth"]))
		config_read = read_reply(agent, awaiting="getConfig (id 12)")["result"]
		assert config_read == {"value": "espeak"}

		agent.write(request(13, "setConfig", keyPath=["speech", "synth"], value="sapi5"))
		config_write = read_reply(agent, awaiting="setConfig (id 13)")["result"]
		assert config_write == {"value": "espeak"}

		agent.write(request(14, "bye"))
		assert read_reply(agent, awaiting="bye (id 14)")["result"] == {"ok": True}
	finally:
		thread.join(timeout=5.0)

	assert not thread.is_alive()
	assert factory.speech_source.stopped == 1
	assert signals.started == 1 and signals.ended == 1
	assert announcer.announced == ["pressing bye now"]
	assert factory.config_accessor.get(["speech", "synth"]) == "espeak"
	assert factory.config_accessor.restore_calls >= 1


def test_get_guidance_answers_for_the_persona_hello_declared(tmp_path: Path) -> None:
	"""Over a real session, because the hop from hello to getGuidance is what is proved."""
	text, unknown_text = _guidance_over_a_session(tmp_path, "expert", "auditor")

	assert "`expert` stance" in text
	# An unknown persona must get an ordinary answer: an older bridge meets a newer server's persona this way.
	assert "No section for the persona you declared" in unknown_text


def _guidance_over_a_session(tmp_path: Path, *personas: str) -> tuple[str, ...]:
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
			FakeGestureResolver(),
		)
		agent = JsonLinesChannel(agent_end)
		thread = threading.Thread(target=session.run, daemon=True)
		thread.start()
		try:
			agent.write(
				request(1, "hello", mode="silent", protocolVersion=p.PROTOCOL_VERSION, persona=persona)
			)
			hello = read_reply(agent, awaiting="hello")
			assert hello["result"]["mode"] == "silent"
			assert p.Capability.GUIDANCE.value in hello["result"]["capabilities"]

			agent.write(request(2, "getGuidance"))
			guidance = read_reply(agent, awaiting="getGuidance (id 2)")["result"]
			assert guidance["persona"] == persona
			assert guidance["recognised"] is (persona != "auditor")
			texts.append(guidance["text"])

			agent.write(request(3, "bye"))
			read_reply(agent, awaiting="bye (id 3)")
		finally:
			thread.join(timeout=5.0)
	return tuple(texts)
