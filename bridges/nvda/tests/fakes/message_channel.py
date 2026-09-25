# nvdaMcpBridge tests -- FakeChannel, standing in for the MessageChannel port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# Script entries: a dict is a message, TIMEOUT_EVENT a quiet poll, CLOSED_EVENT the peer leaving, and an
# Exception instance is raised as-is.

from __future__ import annotations

from typing import TYPE_CHECKING, Any, cast

from nvdaMcpBridge import protocol as p
from nvdaMcpBridge.domain.ports.message_channel import TIMEOUT, ChannelClosed, MessageChannel, Timeout

from .script import ClosedEvent, ScriptedQueue, TimeoutEvent

if TYPE_CHECKING:
	from .clock import FakeClock


class FakeChannel(MessageChannel):
	def __init__(
		self,
		events: list[Any] | None = None,
		*,
		# FakeClock, not Clock: a scripted timeout advances time, which the port cannot.
		clock: FakeClock | None = None,
		timeout_advance: float = 5.0,
		on_empty: str = "closed",
	) -> None:
		self._queue = ScriptedQueue(list(events or []), clock, timeout_advance, on_empty)
		self.sent: list[Any] = []
		self.closed = False

	def read_message(self) -> dict[str, Any] | Timeout:
		event = self._queue.next_event()
		if isinstance(event, TimeoutEvent):
			self._queue.tick_timeout()
			return TIMEOUT
		if isinstance(event, ClosedEvent):
			raise ChannelClosed
		if isinstance(event, Exception):
			raise event
		assert isinstance(event, dict)
		return cast("dict[str, Any]", event)

	def write(self, message: Any) -> None:
		self.sent.append(message)

	def close(self) -> None:
		self.closed = True

	def responses(self) -> list[dict[str, Any]]:
		return [p.to_dict(m) for m in self.sent]
