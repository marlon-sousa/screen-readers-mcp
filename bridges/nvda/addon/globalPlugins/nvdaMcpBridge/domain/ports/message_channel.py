# nvdaMcpBridge domain -- the MessageChannel port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: domain port, the session's request/response seam; the domain never sees bytes, sockets or JSON.
# USED BY: the Session controller.
# IMPLEMENTED BY: adapters/json_lines_channel.py; tests/fakes/message_channel.py.

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Final


class ChannelClosed(Exception):
	"""Raised by :meth:`MessageChannel.read_message` when the peer is gone."""


class Timeout:
	""" "No message yet", distinct from ``None`` and from :class:`ChannelClosed`; see :data:`TIMEOUT`."""

	__slots__ = ()

	def __repr__(self) -> str:  # pragma: no cover - debug aid
		return "TIMEOUT"


TIMEOUT: Final = Timeout()


class MessageChannel(ABC):
	@abstractmethod
	def read_message(self) -> dict[str, Any] | Timeout:
		"""Raises :class:`ChannelClosed` when the peer is gone, ``ValidationError`` on garbage."""

	@abstractmethod
	def write(self, message: Any) -> None:
		"""A wire dataclass or plain dict."""

	@abstractmethod
	def close(self) -> None: ...
