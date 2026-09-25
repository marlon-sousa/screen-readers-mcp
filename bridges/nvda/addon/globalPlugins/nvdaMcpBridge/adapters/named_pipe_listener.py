# nvdaMcpBridge adapters -- NamedPipeListener: the Listener leaf over a Windows
# named pipe.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: leaf adapter implementing Listener over named pipes: remote clients rejected, owner-only DACL.
# BUILT BY: adapters/build_listener.py.
# USED BY: adapters/bridge_server.py, through the Listener seam.

from __future__ import annotations

import ctypes
import ctypes.wintypes as wintypes

from .named_pipe_transport import (
	BUFFER_SIZE,
	ERROR_IO_PENDING,
	ERROR_PIPE_CONNECTED,
	FILE_FLAG_OVERLAPPED,
	INVALID_HANDLE_VALUE,
	KERNEL32,
	OVERLAPPED,
	PIPE_ACCESS_DUPLEX,
	PIPE_READMODE_BYTE,
	PIPE_REJECT_REMOTE_CLIENTS,
	PIPE_TYPE_BYTE,
	PIPE_UNLIMITED_INSTANCES,
	SECURITY_ATTRIBUTES,
	WAIT_OBJECT_0,
	WAIT_TIMEOUT,
	NamedPipeTransport,
	create_event,
	free_security_descriptor,
	owner_only_security_attributes,
)
from .named_pipe_transport import DEFAULT_POLL_TIMEOUT as _DEFAULT_RECV_TIMEOUT
from .ports.listener import Listener, ListenerClosed
from .ports.transport import Transport

#: How long accept blocks before TimeoutError, so the server thread can notice a stop request.
DEFAULT_ACCEPT_TIMEOUT: float = 0.5


class _PendingInstance:
	"""Keeps the OVERLAPPED struct and its event alive while Windows still holds a pointer to them."""

	def __init__(self, handle: int, event: int, overlapped: OVERLAPPED) -> None:
		self.handle = handle
		self.event = event
		self.overlapped = overlapped


class NamedPipeListener(Listener):
	def __init__(
		self,
		pipe_name: str,
		*,
		accept_timeout: float = DEFAULT_ACCEPT_TIMEOUT,
		recv_timeout: float = _DEFAULT_RECV_TIMEOUT,
	) -> None:
		self._pipe_name = pipe_name
		self._accept_timeout = accept_timeout
		self._recv_timeout = recv_timeout
		self._security_attributes: SECURITY_ATTRIBUTES | None = None
		self._pending: _PendingInstance | None = None
		self._closed = True

	@property
	def endpoint(self) -> str:
		return self._pipe_name

	def open(self) -> None:
		self._security_attributes = owner_only_security_attributes()
		self._closed = False
		self._pending = self._create_pending_instance()

	def accept(self) -> Transport:
		if self._closed:
			raise ListenerClosed
		if self._pending is None:
			self._pending = self._create_pending_instance()
		pending = self._pending

		wait = KERNEL32.WaitForSingleObject(pending.event, int(self._accept_timeout * 1000))
		if wait == WAIT_TIMEOUT:
			raise TimeoutError
		if self._closed:
			# close() ran concurrently and already closed pending's handles.
			raise ListenerClosed
		if wait != WAIT_OBJECT_0:
			raise ctypes.WinError(ctypes.get_last_error())

		transferred = wintypes.DWORD()
		ok = KERNEL32.GetOverlappedResult(
			pending.handle, ctypes.byref(pending.overlapped), ctypes.byref(transferred), False
		)
		self._pending = None
		if not ok:
			err = ctypes.get_last_error()
			KERNEL32.CloseHandle(pending.handle)
			KERNEL32.CloseHandle(pending.event)
			if self._closed:
				raise ListenerClosed
			raise ctypes.WinError(err)

		transport = NamedPipeTransport(pending.handle, poll_timeout=self._recv_timeout)
		# Arm the next instance before returning, so one client may queue while this session runs.
		self._pending = self._create_pending_instance()
		return transport

	def close(self) -> None:
		self._closed = True
		pending = self._pending
		self._pending = None
		if pending is not None:
			KERNEL32.CancelIoEx(pending.handle, ctypes.byref(pending.overlapped))
			transferred = wintypes.DWORD()
			KERNEL32.GetOverlappedResult(
				pending.handle, ctypes.byref(pending.overlapped), ctypes.byref(transferred), True
			)
			KERNEL32.CloseHandle(pending.handle)
			KERNEL32.CloseHandle(pending.event)
		if self._security_attributes is not None:
			free_security_descriptor(self._security_attributes)
			self._security_attributes = None

	def _create_pending_instance(self) -> _PendingInstance:
		assert self._security_attributes is not None, "open() must run before accept()"
		handle = KERNEL32.CreateNamedPipeW(
			self._pipe_name,
			PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
			PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_REJECT_REMOTE_CLIENTS,
			PIPE_UNLIMITED_INSTANCES,
			BUFFER_SIZE,
			BUFFER_SIZE,
			0,
			ctypes.byref(self._security_attributes),
		)
		if handle == INVALID_HANDLE_VALUE:
			raise ctypes.WinError(ctypes.get_last_error())
		event = create_event()
		overlapped = OVERLAPPED()
		overlapped.hEvent = event
		pending = _PendingInstance(handle, event, overlapped)

		ok = KERNEL32.ConnectNamedPipe(handle, ctypes.byref(overlapped))
		if not ok:
			err = ctypes.get_last_error()
			if err == ERROR_PIPE_CONNECTED:
				# A client connected before ConnectNamedPipe; signal the event so accept sees it.
				KERNEL32.SetEvent(event)
			elif err != ERROR_IO_PENDING:
				KERNEL32.CloseHandle(handle)
				KERNEL32.CloseHandle(event)
				raise ctypes.WinError(err)
		return pending
