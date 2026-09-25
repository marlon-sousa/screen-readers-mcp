# nvdaMcpBridge tests -- shared scaffolding for fakes that replay a script.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: test scaffolding; the event replay shared by FakeTransport and FakeChannel.

from __future__ import annotations

from typing import TYPE_CHECKING, Any, Final

if TYPE_CHECKING:
	from .clock import FakeClock


class TimeoutEvent:
	"""The peer stayed quiet; match it with isinstance so a strict type checker narrows the union."""

	__slots__ = ()


class ClosedEvent:
	"""The peer went away: EOF at the byte level, ChannelClosed at the message level."""

	__slots__ = ()


TIMEOUT_EVENT: Final = TimeoutEvent()
CLOSED_EVENT: Final = ClosedEvent()


class ScriptedQueue:
	"""on_empty "closed" ends the session once the script runs out; "timeout" keeps advancing the clock."""

	def __init__(
		self,
		events: list[Any],
		clock: FakeClock | None,
		timeout_advance: float,
		on_empty: str,
	) -> None:
		self._events = list(events)
		self._clock = clock
		self._timeout_advance = timeout_advance
		self._on_empty = on_empty

	def next_event(self) -> Any:
		if self._events:
			return self._events.pop(0)
		return TIMEOUT_EVENT if self._on_empty == "timeout" else CLOSED_EVENT

	def tick_timeout(self) -> None:
		if self._clock is not None:
			self._clock.advance(self._timeout_advance)
