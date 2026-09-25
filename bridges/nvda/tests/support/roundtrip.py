# nvdaMcpBridge tests -- the request/reply helpers the roundtrip scenarios share.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: test scaffolding; request and reply helpers for the three integration roundtrip tests.
#
# read_reply budgets polls that came back TIMEOUT rather than seconds, so a descheduled process takes
# longer instead of failing.

from __future__ import annotations

import time
from collections.abc import Callable
from typing import Any, Final

from nvdaMcpBridge import protocol
from nvdaMcpBridge.adapters.json_lines_channel import JsonLinesChannel
from nvdaMcpBridge.domain.ports.message_channel import Timeout

#: 100 polls at the transports' 0.05 s poll timeout is 5 s of bridge silence.
DEFAULT_POLLS: Final = 100

#: Only so a transport that stops returning cannot hang the suite.
BACKSTOP_SECONDS: Final = 60.0

#: The transports' recv poll timeout, used only to turn a poll count into seconds when reporting.
EXPECTED_POLL_SECONDS: Final = 0.05


def request(id: int, cmd: str, **params: Any) -> protocol.Request:
	return protocol.Request(id=id, cmd=cmd, params=dict(params))


def read_reply(
	agent: JsonLinesChannel,
	*,
	awaiting: str,
	polls: int = DEFAULT_POLLS,
) -> dict[str, Any]:
	"""ChannelClosed propagates: the bridge hanging up is a different fact from it staying silent."""
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
	"""Wall-clock on purpose: it polls a local object, not a peer."""
	deadline = time.monotonic() + timeout
	while time.monotonic() < deadline:
		if predicate():
			return
		time.sleep(0.005)
	raise AssertionError(f"{awaiting}: still not true after {timeout:.1f}s")


def _silence_report(awaiting: str, polls: int, elapsed: float) -> str:
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
	return (
		f"the transport stopped answering while awaiting {awaiting}: "
		f"hit the {BACKSTOP_SECONDS:g}s backstop after only {spent} polls "
		f"in {elapsed:.2f}s. This is NOT the bridge staying silent -- that fails "
		f"after {DEFAULT_POLLS} polls -- it is read_message itself failing to "
		"return on time, so look at the transport's poll timeout or at what is "
		"starving this process."
	)
