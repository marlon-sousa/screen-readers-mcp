# nvdaMcpBridge adapters -- the Listener seam.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter seam for the accepting edge.
# USED BY: adapters/bridge_server.py.
# IMPLEMENTED BY: adapters/tcp_listener.py, adapters/named_pipe_listener.py and tests/fakes/listener.py.

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING

if TYPE_CHECKING:
	from .transport import Transport


class ListenerClosed(Exception):
	"""Raised by accept() once the listener has been closed."""


class Listener(ABC):
	@property
	@abstractmethod
	def endpoint(self) -> str:
		"""Human-readable accepting address, defined once open() has bound."""

	@abstractmethod
	def open(self) -> None:
		"""Raises on a bind failure."""

	@abstractmethod
	def accept(self) -> Transport:
		"""TimeoutError after a poll window so the loop can check for a stop; ListenerClosed after close()."""

	@abstractmethod
	def close(self) -> None:
		"""Idempotent; unblocks a pending accept()."""
