# Live-NVDA end-to-end scenario: drive the REAL bridge over a named pipe.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# EXPERIMENTAL, spec 0010's ad-hoc live check -- not a merge gate for entry
# 9.1a. Mirrors test_live_nvda_e2e.py exactly, dialling `DEFAULT_PIPE_NAME`
# with named_pipe_transport.dial() instead of a TCP socket, to prove
# NamedPipeListener against a real NVDA before 9.1b makes the pipe the
# plugin's default for real. Requires plugin.py's uncommitted swap to
# `NamedPipeListener(protocol.DEFAULT_PIPE_NAME)` (see plugin.py) -- with the
# stock TCP-listening addon installed, every test here SKIPS at the dial,
# same as test_live_nvda_e2e.py does with nothing listening.
#
# Run it locally with NVDA up, the pipe-listening build of the addon
# installed, and plugins reloaded (NVDA+control+F3):
#
#     uv run --directory bridges/nvda --with pytest pytest tests/integration/test_live_nvda_pipe_e2e.py -v

from __future__ import annotations

import ast
import time
from pathlib import Path
from typing import Any

import pytest
from support.platforms import skip_module_unless_windows

#: Every test here drives a REAL NVDA on this machine -- gestures, typed
#: text, config changes. Excluded from the default run; see pyproject.toml.
pytestmark = pytest.mark.live_nvda

# And the marker is NOT enough on its own: it deselects these tests only after
# this module has been imported, and the import below reaches an adapter whose
# module body calls ctypes.WinDLL. On a non-Windows host that is a collection
# error, not a deselection. Spec 0042, decision 6.
skip_module_unless_windows("dials a real named pipe, which is a Win32 facility")

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.adapters import named_pipe_transport
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.domain.controllers.commands.registry import NVDA_CAPABILITIES
from nvdaMcpBridge.domain.ports.message_channel import Timeout

#: Same choice as test_live_nvda_e2e.py: speaks in essentially any focus
#: context, so the capture assertion does not depend on a particular window.
SPEAKING_GESTURE = "NVDA+t"

#: The Run dialog is hosted by the shell, so NVDA attributes it to explorer.
RUN_DIALOG_APP_MODULE = "explorer"


@pytest.fixture(scope="module", autouse=True)
def require_live_bridge() -> None:
	try:
		named_pipe_transport.dial(p.DEFAULT_PIPE_NAME, timeout=0.5).close()
	except (OSError, TimeoutError):
		pytest.skip(
			f"no bridge on pipe {p.DEFAULT_PIPE_NAME!r} -- start NVDA with a "
			"pipe-listening build of the nvdaMcpBridge addon installed"
		)


class Agent:
	"""The client end of one bridge session: send a command, read its reply."""

	def __init__(self, channel: JsonLinesChannel) -> None:
		self._channel = channel
		self._id = 0

	def raw(self, cmd: str, *, reply_timeout: float = 10.0, **params: Any) -> dict[str, Any]:
		"""The reply exactly as it came, error and all.

		For the tests whose SUBJECT is a refusal -- an expired ticket, a rejected
		second prompt -- where `call` raising would hide the very thing being
		asserted.
		"""
		self._id += 1
		self._channel.write(p.Request(id=self._id, cmd=cmd, params=dict(params)))
		deadline = time.monotonic() + reply_timeout
		while time.monotonic() < deadline:
			message = self._channel.read_message()
			if isinstance(message, Timeout):
				continue
			return message
		raise AssertionError(f"no reply to {cmd} within {reply_timeout}s")

	def call(self, cmd: str, *, reply_timeout: float = 10.0, **params: Any) -> dict[str, Any]:
		reply = self.raw(cmd, reply_timeout=reply_timeout, **params)
		if reply.get("error") is not None:
			raise AssertionError(f"{cmd} failed: {reply['error']}")
		return reply

	def result(self, cmd: str, **params: Any) -> dict[str, Any]:
		return self.call(cmd, **params)["result"]

	def close(self) -> None:
		self._channel.close()


def _dial() -> Agent:
	try:
		transport = named_pipe_transport.dial(p.DEFAULT_PIPE_NAME, timeout=1.0)
	except (OSError, TimeoutError):
		pytest.skip(
			f"no bridge on pipe {p.DEFAULT_PIPE_NAME!r} -- start NVDA with a "
			"pipe-listening build of the nvdaMcpBridge addon installed"
		)
	return Agent(JsonLinesChannel(transport))


def _hello(agent: Agent, mode: str) -> dict[str, Any]:
	return agent.result("hello", mode=mode, protocolVersion=p.PROTOCOL_VERSION)


def _expected_bridge_version() -> str:
	"""The add-on version this CHECKOUT would build, read from buildVars.py.

	Parsed rather than imported: buildVars.py pulls in the site_scons tooling,
	so importing it needs SCons installed in whatever interpreter runs pytest.
	The version is a literal keyword argument, and reading it with ast keeps
	this check working in a bare test environment.
	"""
	source = Path(__file__).resolve().parents[2] / "buildVars.py"
	tree = ast.parse(source.read_text(encoding="utf-8"), str(source))
	for node in ast.walk(tree):
		if not isinstance(node, ast.Call):
			continue
		for keyword in node.keywords:
			if keyword.arg == "addon_version" and isinstance(keyword.value, ast.Constant):
				return str(keyword.value.value)
	raise AssertionError(f"no addon_version literal found in {source}")


def _caps_key(agent: Agent) -> list[str]:
	"""The real path of sayCapForCapitals: PER SYNTH, not directly under speech.

	It is declared in [speech][[__many__]] (config/configSpec.py:52-55), and
	NVDA's own voice panel reads it as config.conf["speech"][driver.name][...]
	(gui/settingsDialogs.py:1801). ["speech", "sayCapForCapitals"] is not a real
	key: getConfig on it raises, and an override there is inaudible because
	nothing in NVDA ever reads it.
	"""
	synth = agent.result("getConfig", keyPath=["speech", "synth"])["value"]
	return ["speech", synth, "sayCapForCapitals"]


def _settled_index(agent: Agent, *, settle: float = 0.4, timeout: float = 4.0) -> int:
	"""The speech index once NVDA has genuinely stopped talking.

	`waitForSpeechToFinish` answers "does the buffer look finished now", which is
	a statement about the LAST utterance, not "has everything I just triggered
	arrived". Bookmarking an index on it is what made
	test_set_config_changes_nvda_behaviour flaky: one run bookmarked too early
	and the selection chatter landed after the mark (three utterances captured,
	``'A\\nA\\nseleção removida'``), the next bookmarked after everything and
	captured nothing at all.

	Waiting for the index to hold still for ``settle`` seconds fences the
	measurement on the observable fact the test actually depends on -- nothing
	more is coming -- instead of on a heuristic about one utterance.
	"""
	last = agent.result("getNextSpeechIndex")["index"]
	quiet_since = time.monotonic()
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		time.sleep(0.1)
		now = agent.result("getNextSpeechIndex")["index"]
		if now != last:
			last, quiet_since = now, time.monotonic()
		elif time.monotonic() - quiet_since >= settle:
			return last
	return last


def _speech_after(agent: Agent, start: int, *, timeout: float = 4.0) -> str:
	"""Everything spoken since ``start``, once speech has stopped again.

	Waits for the index to MOVE before waiting for it to settle, so an
	announcement that simply has not begun yet is never read as silence -- the
	second half of the flake above.
	"""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		if agent.result("getNextSpeechIndex")["index"] > start:
			break
		time.sleep(0.1)
	_settled_index(agent)
	# One entry per utterance since spec 0021; joined here so callers keep
	# asserting on what NVDA said rather than on the result's shape.
	speech = agent.result("getSpeech", sinceIndex=start)
	return "\n".join(entry["text"] for entry in speech["entries"]).strip()


def test_the_installed_addon_is_the_one_in_this_checkout() -> None:
	"""Guard every other live test in this file against a STALE install.

	These tests import the bridge package from the SOURCE TREE but talk over the
	pipe to whatever add-on build NVDA actually loaded. When the two drift, the
	failures land somewhere else entirely -- a capability list that does not
	match, a command that answers "unknown" -- and read like bridge bugs. Asking
	directly turns a session of confusion into one clear line.

	Caveat worth knowing: this compares VERSIONS, so it catches an install from
	a different release. It cannot catch editing code without bumping
	addon_version; for that the discipline is still rebuild-and-reinstall.
	"""
	agent = _dial()
	try:
		hello = _hello(agent, "silent")
		expected = _expected_bridge_version()
		rebuild = "rebuild and reinstall the add-on (cd bridges/nvda && scons), then restart NVDA"
		# A build predating this field omits it entirely -- which IS the stale
		# case, and the commonest one, so it gets the same clear message rather
		# than a KeyError from the middle of a fixture.
		assert "bridgeVersion" in hello, (
			f"the running bridge does not report bridgeVersion at all, so it predates "
			f"this check; this checkout is {expected!r} -- {rebuild}"
		)
		reported = hello["bridgeVersion"]
		assert reported == expected, (
			f"the running NVDA has bridge {reported!r}, this checkout is {expected!r} -- {rebuild}"
		)
		agent.result("bye")
	finally:
		agent.close()


def test_hello_reports_real_nvda_and_served_capabilities() -> None:
	agent = _dial()
	try:
		hello = _hello(agent, "silent")
		assert hello["reader"]["name"] == "nvda"
		assert hello["reader"]["version"], "reader.version should match About NVDA"
		assert hello["capabilities"] == [c.value for c in NVDA_CAPABILITIES]
		assert hello["mode"] == "silent"
		assert hello["synth"], "hello should report NVDA's real synth"
		agent.result("bye")
	finally:
		agent.close()


def test_silent_session_captures_a_gesture_and_finishes() -> None:
	agent = _dial()
	try:
		_hello(agent, "silent")
		start = agent.result("getNextSpeechIndex")["index"]
		assert agent.result("pressGesture", gestures=[SPEAKING_GESTURE]) == {"ok": True}
		assert agent.result("waitForSpeechToFinish", timeout=3.0)["finished"] is True
		speech = agent.result("getSpeech", sinceIndex=start)
		spoken = "\n".join(entry["text"] for entry in speech["entries"])
		assert spoken.strip(), "the gesture should have been captured as speech"
		assert speech["toIndex"] > speech["fromIndex"]
		agent.result("bye")
	finally:
		agent.close()


def test_two_sequential_sessions_on_one_server() -> None:
	synths: list[str] = []
	for _ in range(2):
		agent = _dial()
		try:
			synths.append(_hello(agent, "silent")["synth"])
			agent.result("bye")
		finally:
			agent.close()
	assert synths[0] == synths[1]
	assert synths[0]  # a real synth name, stable across sessions


class _RunDialog:
	"""Focus the Run dialog for the block, and ALWAYS dismiss it afterwards.

	The Run dialog is the cheapest real focus this suite can borrow: present on
	every Windows box, a plain edit field, an app module that is a known
	constant, and Escape puts everything back exactly as it was. Nothing is
	launched and nothing is left running.

	It replaced opening Notepad, which spawned a process, raced the window
	appearing, and left a window on the tester's desktop -- for no coverage that
	the dialog itself does not already provide.

	Written as a class rather than @contextlib.contextmanager only because
	pyright's strict mode reports that decorator as deprecated; the behaviour is
	the same and the two dunders make the guarantee easier to see.
	"""

	def __init__(self, agent: Agent) -> None:
		self._agent = agent

	def __enter__(self) -> None:
		self._agent.result("pressGesture", gestures=["windows+r"])
		deadline = time.monotonic() + 5.0
		while time.monotonic() < deadline:
			if self._agent.result("getFocusInfo")["appModule"] == RUN_DIALOG_APP_MODULE:
				break
			time.sleep(0.1)
		else:
			# Dismiss before failing: an assertion must not leave a dialog open
			# over someone's work just because it did not recognise it.
			self._agent.result("pressGesture", gestures=["escape"])
			raise AssertionError(
				f"the Run dialog never took focus within 5s (appModule stayed "
				f"{self._agent.result('getFocusInfo')['appModule']!r})"
			)
		# Let the dialog finish announcing ITSELF before handing over. Focus
		# arrives before the announcement ends, so a body that immediately takes
		# a speech index captures the tail of "Run dialog, Type the name of a
		# program..." and attributes it to whatever it did next.
		self._agent.result("waitForSpeechToFinish", timeout=5.0)

	def __exit__(self, *exc_info: object) -> None:
		# In __exit__ because this drives a REAL machine: a failed assertion
		# must not walk away leaving a dialog open over someone's work. Escape,
		# never Enter -- the typed text is never committed, so nothing can be
		# executed by accident.
		self._agent.result("pressGesture", gestures=["escape"])


# -- introspection e2e (entry 11.1) ------------------------------------------


def test_get_focus_info_reports_real_focus() -> None:
	"""getFocusInfo returns a real role and appModule from the running NVDA."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		result = agent.result("getFocusInfo")
		assert result["role"], "focus role should be non-empty"
		assert isinstance(result["states"], list)

		with _RunDialog(agent):
			focus = agent.result("getFocusInfo")
			assert focus["appModule"] == RUN_DIALOG_APP_MODULE, (
				f"expected the Run dialog to be hosted by "
				f"{RUN_DIALOG_APP_MODULE!r}, got {focus['appModule']!r}"
			)
			# The role is asserted as NON-EMPTY and stable rather than as a
			# specific member: this field's contract is "a stable enum NAME
			# rather than a localized display string" (spec 0015), and which
			# member the Run dialog's field reports is a Windows detail that
			# has changed between releases. Pinning it would test Windows.
			assert focus["role"], "the Run dialog's field should report a role"
			assert focus["role"] == focus["role"].upper(), (
				f"role should be a stable enum NAME, got {focus['role']!r}"
			)

			# Deliberately NOT asserting that typing echoes here. Character echo
			# is a user setting ("speak typed characters"), off on at least one
			# maintainer's machine, and this test is about getFocusInfo -- an
			# assertion that fails on someone's keyboard preferences would be
			# blaming the bridge for the tester's configuration.

		agent.result("bye")
	finally:
		agent.close()


def test_get_state_reports_real_modes() -> None:
	"""getState returns real browseMode, speechMode, sleepMode, inputHelp."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		state = agent.result("getState")
		assert state["browseMode"] in ("browse", "focus", "none")
		assert state["speechMode"] in ("talk", "off", "beeps", "onDemand")
		assert isinstance(state["sleepMode"], bool)
		assert isinstance(state["inputHelp"], bool)
		agent.result("bye")
	finally:
		agent.close()


def test_get_config_reads_real_config_key() -> None:
	"""getConfig reads a known NVDA config key."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		result = agent.result("getConfig", keyPath=["speech", "synth"])
		assert result["value"], "speech.synth should be a non-empty string"
		agent.result("bye")
	finally:
		agent.close()


def test_set_config_roundtrip_and_restore() -> None:
	"""set_config -> get_config sees override; new session sees original."""
	agent = _dial()
	try:
		_hello(agent, "silent")
		original = agent.result("getConfig", keyPath=_caps_key(agent))["value"]

		flipped = not bool(original)
		prior = agent.result(
			"setConfig",
			keyPath=_caps_key(agent),
			value=flipped,
		)["value"]
		assert prior == original, f"setConfig should return prior {original}, got {prior}"

		current = agent.result("getConfig", keyPath=_caps_key(agent))["value"]
		assert current == flipped, f"getConfig should see override {flipped}, got {current}"

		agent.result("bye")
	finally:
		agent.close()

	# New session: override is gone (teardown cleared the map).
	agent2 = _dial()
	try:
		_hello(agent2, "silent")
		restored = agent2.result("getConfig", keyPath=_caps_key(agent2))["value"]
		assert restored == original, f"new session should see original {original}, got {restored}"
		agent2.result("bye")
	finally:
		agent2.close()


def test_set_config_changes_nvda_behaviour() -> None:
	"""set_config changes what NVDA speaks -- the hook reaches NVDA code.

	Asserts that the two spoken results DIFFER, not that either contains a
	particular word. NVDA announces a capital in the tester's own language
	("cap" in English, "maiuscula" in Portuguese), and spec 0015 rejected
	localized strings in assertions for exactly this reason -- an assertion
	that passes or fails depending on the tester's NVDA language is the class
	of flakiness this project exists to remove.
	"""
	agent = _dial()
	try:
		_hello(agent, "silent")
		key = _caps_key(agent)

		def _speak_a_capital() -> str:
			"""Put a capital A in the field, then ARROW ONTO IT and listen.

			Not "type it and listen to the echo". typeText injects
			KEYEVENTF.UNICODE events (adapters/nvda_text_typer.py), which carry
			the character in wScan with no virtual-key -- NVDA's typed-character
			echo keys off real character-producing keystrokes and never fires
			for injected text. Reading that silence as "the user has echo
			switched off" was wrong; the setting was on the whole time.

			Moving the caret over a character makes NVDA announce it through the
			caret path instead, which is core behaviour rather than a keyboard
			preference -- so this measures sayCapForCapitals wherever it runs.

			control+a first, so each measurement starts from a field holding
			exactly one character rather than whatever the previous one left.
			"""
			agent.result("pressGesture", gestures=["control+a"])
			agent.result("typeText", text="A")
			# Bookmark once NVDA has actually gone quiet, not merely once one
			# utterance reports finished -- otherwise the selection and echo
			# chatter lands after the mark and is read as the caret announcement.
			start = _settled_index(agent)
			agent.result("pressGesture", gestures=["leftArrow"])
			return _speech_after(agent, start)

		# Type into the Run dialog, not into "whatever happens to have focus".
		# The old form typed a capital A into the tester's foreground window --
		# their editor, their terminal, their email -- which is both a way to
		# corrupt someone's work and a way to get a flaky result, since not
		# every control echoes typed characters.
		with _RunDialog(agent):
			agent.result("setConfig", keyPath=key, value=False)
			without = _speak_a_capital()

			agent.result("setConfig", keyPath=key, value=True)
			with_cap = _speak_a_capital()

		assert without, "arrowing onto a character announced nothing at all"
		assert with_cap != without, (
			"turning sayCapForCapitals on did not change what NVDA spoke for a "
			f"capital A (both were {without!r}) -- the override never reached NVDA"
		)
		assert len(with_cap) > len(without), (
			f"expected the announcement to GAIN a capital marker, got {without!r} -> {with_cap!r}"
		)

		agent.result("bye")
	finally:
		agent.close()


# -- human-in-the-loop (spec 0016, entry 11.2) --------------------------------
#
# The acknowledgement is a real NVDA gesture, so the obvious reading is that a
# human has to be present for these. They do not: `askUser` RETURNS IMMEDIATELY
# (that is the whole point of present-then-poll), so the same session can send
# the ack gesture itself, and what runs is the real script_acknowledge against
# the real UserPrompt. The human is only needed to judge what they HEARD, which
# is what checklist items 1 and 2 are for.


def test_ask_user_round_trip_with_the_real_acknowledgement_gesture() -> None:
	# Checklist items 4 and 5, automated: present a prompt, miss a poll, answer
	# it with the gesture a tester would actually press, and get answered=true.
	agent = _dial()
	try:
		_hello(agent, "silent")

		ticket = agent.result("askUser", prompt="This is an automated test. No action needed.")["ticket"]
		assert ticket, "askUser returned no ticket"

		# A poll before the answer: a miss is an ordinary outcome and must leave
		# the window open rather than closing it (spec 0016's first decision).
		missed = agent.result("waitForUserReply", ticket=ticket, timeout=0.5)
		assert missed["answered"] is False, "a prompt nobody answered reported answered=true"

		# The tester's keypress, sent as a real gesture: NVDA runs the ack script,
		# which answers the prompt held by the live session.
		agent.result("pressGesture", gestures=["NVDA+control+shift+a"])

		answered = agent.result("waitForUserReply", ticket=ticket, timeout=5.0)
		assert answered["answered"] is True, (
			"the acknowledgement gesture did not answer the prompt -- the ack script "
			"could not reach the session's outstanding prompt"
		)

		# The window is closed, so the ticket is spent: polling it again is an
		# error, not a second answer. Agent.call turns an error reply into an
		# AssertionError, so that is what a refusal looks like from here.
		with pytest.raises(AssertionError, match="no outstanding prompt"):
			agent.call("waitForUserReply", ticket=ticket, timeout=0.5)

		agent.result("bye")
	finally:
		agent.close()


def test_nothing_the_tester_hears_during_the_window_is_captured() -> None:
	# Checklist item 3, automated: suppression is SUSPENDED for the window, so
	# speech during it reaches the human and must not enter the buffer -- if it
	# did, the agent's own before/after index arithmetic would silently include
	# the human's navigation.
	agent = _dial()
	try:
		_hello(agent, "silent")

		before = agent.result("getNextSpeechIndex")["index"]
		ticket = agent.result("askUser", prompt="Automated test. Ignore this.")["ticket"]

		# Make NVDA speak while the window is open. In a suspended session this
		# goes to the synth and NOT to the buffer.
		agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		time.sleep(0.5)

		during = agent.result("getNextSpeechIndex")["index"]
		assert during == before, (
			f"speech index moved {before} -> {during} while the window was open: "
			"the tester's own speech is being captured as if it were reader output"
		)

		agent.result("pressGesture", gestures=["NVDA+control+shift+a"])
		assert agent.result("waitForUserReply", ticket=ticket, timeout=5.0)["answered"] is True

		# And capture resumes afterwards, or the session would be useless from
		# here on.
		agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		time.sleep(0.5)
		after = agent.result("getNextSpeechIndex")["index"]
		assert after > during, (
			f"speech index stuck at {during} after the window closed -- suppression "
			"did not resume, so nothing is being captured any more"
		)

		agent.result("bye")
	finally:
		agent.close()


def test_a_session_that_dies_with_a_window_open_recovers() -> None:
	# Checklist item 8's live analogue. Dropping the connection mid-window is the
	# case where suppression is deliberately OFF, so teardown must leave the
	# filter unregistered and the server able to serve again. What proves it from
	# out here is that a FRESH session captures speech normally: that can only
	# happen if the previous one released cleanly.
	agent = _dial()
	try:
		_hello(agent, "silent")
		agent.result("askUser", prompt="Automated test. This session will drop.")
	finally:
		agent.close()  # no bye, no answer -- the agent just vanishes

	# The bridge notices the dead pipe on its next read and tears the session
	# down; the next dial gets a new one.
	time.sleep(1.0)

	recovered = _dial()
	try:
		_hello(recovered, "silent")
		before = recovered.result("getNextSpeechIndex")["index"]
		recovered.result("pressGesture", gestures=[SPEAKING_GESTURE])
		time.sleep(0.5)
		after = recovered.result("getNextSpeechIndex")["index"]
		assert after > before, (
			"a fresh session captured nothing, so the abandoned window left the "
			"bridge in a state it could not recover from"
		)
		recovered.result("bye")
	finally:
		recovered.close()


def test_the_acknowledgement_is_confirmed_out_loud() -> None:
	# The confirmation exists ONLY for the person listening: pressing the gesture
	# used to be silent, which for a blind tester is indistinguishable from a
	# keypress that never registered. So "did it speak" is the requirement, not a
	# nicety -- and it needs asserting somewhere, because ui.message lives in
	# plugin.py, the NVDA edge that no unit test reaches.
	#
	# LIVE mode is what makes it observable: the speech source watches NVDA's own
	# pipeline, so ui.message enters the buffer. In silent mode it cannot be seen
	# from here at all -- the open window suspends suppression, so the words go to
	# the synth and are deliberately never captured.
	agent = _dial()
	try:
		_hello(agent, "live")
		ticket = agent.result("askUser", prompt="Automated test. Ignore this.")["ticket"]

		start = _settled_index(agent)
		agent.result("pressGesture", gestures=["NVDA+control+shift+a"])
		spoken = _speech_after(agent, start)

		assert spoken, (
			"the acknowledgement gesture said NOTHING; silence is indistinguishable "
			"from a keypress that missed the dialog"
		)
		# Our own string, and untranslated today -- when a catalog lands this needs
		# the same treatment spec 0015 gave localized assertions.
		assert "acknowledg" in spoken.casefold(), (
			f"the gesture spoke {spoken!r}, which is not the confirmation"
		)
		assert agent.result("waitForUserReply", ticket=ticket, timeout=5.0)["answered"] is True

		agent.result("bye")
	finally:
		agent.close()


@pytest.mark.slow
def test_an_unanswered_window_expires_and_the_session_survives() -> None:
	"""Checklist items 6 and 9, in one real five-minute run.

	Both are questions about WALL-CLOCK time, which is exactly what the headless
	tier cannot answer: FakeClock proves the arithmetic in microseconds (a 301 s
	advance in test_user_prompt.py), and what remains is whether the numbers
	COMPILED INTO THE INSTALLED ADD-ON behave on a real NVDA -- the 300 s window,
	the 30 s heartbeat, the 120 s inactivity watchdog. Hurrying it would mean
	testing numbers the add-on does not ship, so it is marked slow and left out of
	`poe live`.

	Item 6: nobody answers, so the window closes on its own. Its deadline is
	observed BY A POLL rather than by a timer (spec 0016, amendment 4), so this
	keeps polling instead of sleeping blind -- and the proof that it closed is that
	the ticket then stops being accepted at all.

	Item 9: those same polls are what keeps the session alive, each one resetting
	command-inactivity while the heartbeat sees traffic. So a session that is still
	answering after the whole window has passed IS item 9, and the closing `bye`
	proves it was never torn down underneath us.

	It announces as it goes, because a human is listening to a five-minute test and
	silence is indistinguishable from a hang.
	"""
	agent = _dial()
	try:
		_hello(agent, "silent")
		agent.result(
			"announce",
			text=(
				"Starting the slow checklist run. I will open a question and deliberately "
				"never answer it, for about five minutes, announcing as I go. Nothing is "
				"needed from you."
			),
		)

		ticket = agent.result("askUser", prompt="Slow test. Do not answer this one.")["ticket"]
		started = time.monotonic()

		expired = False
		polls = 0
		# Generous ceiling: the window is 300 s, so anything past ~360 s means it
		# did not close when it should have.
		while time.monotonic() - started < 420.0:
			polls += 1
			# raw, not call: a refused ticket is the OUTCOME being waited for here,
			# and call() would raise it away.
			reply = agent.raw("waitForUserReply", reply_timeout=90.0, ticket=ticket, timeout=60.0)
			if reply.get("error") is not None:
				# The ticket is no longer accepted: the window closed and the poll
				# before this one is the one that observed it.
				expired = True
				break
			assert reply["result"]["answered"] is False, (
				"the bridge reported an answer, but nothing acknowledged the prompt"
			)
			minutes = (time.monotonic() - started) / 60.0
			agent.result("announce", text=f"Still waiting. {minutes:.0f} minutes so far.")

		elapsed = time.monotonic() - started
		assert expired, (
			f"the window was still open after {elapsed:.0f}s and {polls} polls; it should close at 300s"
		)
		assert elapsed >= 290.0, (
			f"the window closed after only {elapsed:.0f}s -- far short of its 300 s deadline, "
			"so something other than the deadline ended it"
		)

		# Suppression resumed when the expiry was observed, so capture works again.
		before = agent.result("getNextSpeechIndex")["index"]
		agent.result("pressGesture", gestures=[SPEAKING_GESTURE])
		time.sleep(0.5)
		after = agent.result("getNextSpeechIndex")["index"]
		assert after > before, "nothing was captured after the window expired, so suppression never resumed"

		# Item 9, stated as an assertion: the session is still the same one, still
		# serving, after five minutes -- neither watchdog fired.
		agent.result(
			"announce",
			text=f"Slow run finished. The window expired on its own after {elapsed:.0f} seconds.",
		)
		agent.result("bye")
	finally:
		agent.close()
