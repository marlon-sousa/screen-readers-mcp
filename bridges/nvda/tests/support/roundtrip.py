# nvdaMcpBridge tests -- the request/reply helpers the roundtrip scenarios share.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# NOT a port double -- there is no port here to stand in for -- so it lives in
# support/ rather than fakes/. Used by the three integration roundtrip tests
# (named pipe, socket, wire) and by nothing under tests/unit/.
#
# Spec 0039, board entry 11.28. These three functions were BYTE-IDENTICAL copies
# in all three files. That duplication was not merely untidy: when the pipe
# scenario failed once on 2026-08-21 with `no reply from the bridge within
# timeout`, the message named none of the eight exchanges the test makes, said
# nothing about how the budget had been spent, and the other two scenarios --
# which share the shape and so share the blind spot -- would have reported the
# same nothing.
#
# WHAT `read_reply` MEASURES, AND WHY IT IS NOT SECONDS. A wall-clock deadline
# answers "how much time passed", when the question a test is asking is "how
# many chances did the bridge have to answer". Those coincide only while this
# process is actually scheduled, which is the one condition in doubt: the only
# run that has ever failed was a full `poe dev`, which builds a binary an
# antivirus pass may then walk. So the budget counts polls that came back
# TIMEOUT, and a starved process takes longer to spend the same budget rather
# than failing on a shorter one.
#
# The budget is deliberately NOT more generous than the 5.0s it replaces:
# DEFAULT_POLLS * DEFAULT_POLL_TIMEOUT is the same 5 seconds of bridge silence.
# Raising it is the one change that could hide a real fault in the connection
# stack, and spec 0039 does not make it.

from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any, Final

from nvdaMcpBridge import protocol
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.domain.ports.message_channel import Timeout

#: How many TIMEOUT polls the bridge may spend before a reply is called missing.
#: 100 polls at the transports' 0.05s poll timeout is the 5.0s wall-clock budget
#: this replaced, expressed in the unit that survives a descheduled process.
DEFAULT_POLLS: Final = 100

#: A wall-clock ceiling that exists ONLY so a transport which stops returning
#: cannot hang the suite: a poll budget can never expire if nothing is polling.
#: Far above any plausible slow answer, so reaching it is a different finding
#: from spending the polls -- and it is reported as one.
BACKSTOP_SECONDS: Final = 60.0

#: The transports' own recv poll timeout, quoted here only to turn a poll count
#: back into seconds when reporting. Not imported from either transport: this is
#: a test's expectation about them, and the report says when it was wrong.
EXPECTED_POLL_SECONDS: Final = 0.05


def request(id: int, cmd: str, **params: Any) -> protocol.Request:
	"""A wire request, with its params inline at the call site."""
	return protocol.Request(id=id, cmd=cmd, params=dict(params))


def read_reply(
	agent: JsonLinesChannel,
	*,
	awaiting: str,
	polls: int = DEFAULT_POLLS,
) -> dict[str, Any]:
	"""Read past the poll-timeouts until the bridge actually answers.

	``awaiting`` names the exchange -- the command, and its request id where the
	test sends more than one. It is required rather than optional because its
	whole purpose is to make a failure say WHICH call gave up, which an optional
	argument would let a call site quietly decline to do.

	Raises ``AssertionError`` when the budget is spent, and a different one when
	the wall-clock backstop is hit first. ``ChannelClosed`` propagates: the
	bridge hanging up is a distinct fact from it staying silent, and flattening
	the two into one assertion is the mistake this helper exists to undo.
	"""
	started = time.monotonic()
	backstop = started + BACKSTOP_SECONDS
	spent = 0
	while spent < polls:
		message = agent.read_message()
		if not isinstance(message, Timeout):
			return message
		spent += 1
		if time.monotonic() >= backstop:
			raise AssertionError(_backstop_report(awaiting, spent, time.monotonic() - started))
	raise AssertionError(_silence_report(awaiting, polls, time.monotonic() - started))


def wait_until(predicate: Callable[[], bool], *, awaiting: str, timeout: float = 2.0) -> None:
	"""Block until ``predicate`` holds, or fail saying what never became true.

	Wall-clock on purpose, and the odd one out here for a reason: this polls a
	local object -- a server's own status -- rather than waiting on a peer, so
	there is no "chances the other side had to answer" to count. What it needs
	from spec 0039 is the label, not the instrument.
	"""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		if predicate():
			return
		time.sleep(0.005)
	raise AssertionError(f"{awaiting}: still not true after {timeout:.1f}s")


def _silence_report(awaiting: str, polls: int, elapsed: float) -> str:
	"""The bridge declined every chance it was given. Say how it was spent.

	The per-poll average is the load discriminator and the reason elapsed time is
	still reported now that it is not the budget: at roughly EXPECTED_POLL_SECONDS
	the bridge was genuinely silent while this process ran normally, and well
	above it this process was not being scheduled and the silence may be an
	artefact of the machine rather than a fact about the bridge.
	"""
	per_poll = elapsed / polls if polls else 0.0
	expected = polls * EXPECTED_POLL_SECONDS
	return (
		f"no reply from the bridge while awaiting {awaiting}: "
		f"{polls} polls returned TIMEOUT over {elapsed:.2f}s "
		f"({per_poll * 1000:.0f}ms per poll; ~{EXPECTED_POLL_SECONDS * 1000:.0f}ms expected, "
		f"so ~{expected:.2f}s of bridge silence was budgeted). "
		"The channel never reached EOF, so the bridge was connected and quiet "
		"rather than hung up. A per-poll figure near the expected one means the "
		"bridge really did not answer; one well above it means this process was "
		"not running, and the silence is the machine's rather than the bridge's."
	)


def _backstop_report(awaiting: str, spent: int, elapsed: float) -> str:
	"""Not silence -- the transport stopped answering US. A different finding.

	Reaching a 60s ceiling on a budget worth ~5s means the polls themselves
	stopped coming back on time, so the subject is the transport (or the
	scheduler), not whether the bridge replied.
	"""
	return (
		f"the transport stopped answering while awaiting {awaiting}: "
		f"hit the {BACKSTOP_SECONDS:g}s backstop after only {spent} polls "
		f"in {elapsed:.2f}s. This is NOT the bridge staying silent -- that fails "
		f"after {DEFAULT_POLLS} polls -- it is read_message itself failing to "
		"return on time, so look at the transport's poll timeout or at what is "
		"starving this process."
	)
