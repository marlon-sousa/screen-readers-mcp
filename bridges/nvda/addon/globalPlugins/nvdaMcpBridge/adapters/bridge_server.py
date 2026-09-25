# nvdaMcpBridge adapters -- BridgeServer: the start/stop connection controller.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter-layer controller owning the connection lifecycle and server thread, one session at a time.
# BUILT BY: plugin.py.
# USED BY: plugin.py and the bridge control dialog.

from __future__ import annotations

import enum
import threading
from collections.abc import Callable
from dataclasses import dataclass
from typing import TYPE_CHECKING

from ..domain.controllers.teardown_reason import TeardownReason
from ..domain.entities.bridge_events import BridgeEvent, BridgeEventType
from ..domain.ports.event_bus import EventBus
from .ports.listener import Listener, ListenerClosed

if TYPE_CHECKING:
	from ..domain.controllers.commands.session_context import SessionContext
	from ..domain.controllers.session import Session
	from .ports.transport import Transport

SessionFactory = Callable[["Transport"], "Session"]

#: stop() is often called on NVDA's main thread, so its join must stay short enough that speech never stalls.
_STOP_JOIN_TIMEOUT: float = 5.0


class ServerState(enum.Enum):
	STOPPED = "stopped"
	LISTENING = "listening"
	SESSION_ACTIVE = "session-active"


@dataclass(frozen=True)
class ServerStatus:
	"""``endpoint`` is None when stopped."""

	state: ServerState
	endpoint: str | None


class BridgeServer:
	def __init__(
		self,
		listener: Listener,
		session_factory: SessionFactory,
		event_bus: EventBus | None = None,
	) -> None:
		self._listener = listener
		self._session_factory = session_factory
		self._event_bus = event_bus

		# One lock guards every field shared between the server thread and a caller thread.
		self._lock = threading.Lock()
		self._state = ServerState.STOPPED
		self._endpoint: str | None = None
		self._active_session: Session | None = None
		self._thread: threading.Thread | None = None
		self._stopping = False

	def _notify(self) -> None:
		bus = self._event_bus
		if bus is not None:
			bus.emit(BridgeEvent(type=BridgeEventType.SERVER_STATUS, payload=self.status))

	@property
	def status(self) -> ServerStatus:
		with self._lock:
			return ServerStatus(self._state, self._endpoint)

	def start(self, listener: Listener | None = None) -> None:
		"""Binds on the caller's thread so a bind failure surfaces here, not in the server thread."""
		with self._lock:
			if self._state is not ServerState.STOPPED:
				return
			if listener is not None:
				self._listener.close()
				self._listener = listener
			self._listener.open()
			self._endpoint = self._listener.endpoint
			self._state = ServerState.LISTENING
			self._stopping = False
			self._thread = threading.Thread(target=self._serve, name="nvdaMcpBridge-server", daemon=True)
			self._thread.start()
		self._notify()

	def stop(self) -> None:
		"""Never call on the server thread; the join is bounded: the caller is often NVDA's main thread."""
		with self._lock:
			thread = self._thread
			session = self._active_session
			self._stopping = True
		if session is not None:
			session.request_teardown(TeardownReason.EXTERNAL)
		self._listener.close()
		if thread is not None:
			thread.join(timeout=_STOP_JOIN_TIMEOUT)
		with self._lock:
			self._state = ServerState.STOPPED
			self._endpoint = None
			self._active_session = None
			self._thread = None
			self._stopping = False
		self._notify()

	def _serve(self) -> None:
		try:
			while not self._is_stopping():
				try:
					transport = self._listener.accept()
				except TimeoutError:
					continue
				except ListenerClosed:
					break
				except Exception:
					break  # an unexpected listener fault: stop, do not spin
				try:
					self._run_session(transport)
				except Exception:
					# A single session must never take the server down.
					pass
		finally:
			# stop() owns the status and the socket; this covers an abnormal exit only.
			if not self._is_stopping():
				self._listener.close()
				with self._lock:
					self._state = ServerState.STOPPED
					self._endpoint = None
					self._active_session = None
				self._notify()

	def _run_session(self, transport: Transport) -> None:
		session = self._session_factory(transport)
		with self._lock:
			self._active_session = session
			self._state = ServerState.SESSION_ACTIVE
			stopping = self._stopping
		self._notify()
		# stop() may have raced in before the session was registered, so tear it down here.
		if stopping:
			session.request_teardown(TeardownReason.EXTERNAL)
		try:
			session.run()
		finally:
			with self._lock:
				self._active_session = None
				if not self._stopping:
					self._state = ServerState.LISTENING
			if not self._is_stopping():
				self._notify()

	def current_session_context(self) -> SessionContext | None:
		"""Read under the lock because the caller is NVDA's main thread."""
		with self._lock:
			session = self._active_session
		if session is None:
			return None
		return session.session_context

	def _is_stopping(self) -> bool:
		with self._lock:
			return self._stopping
