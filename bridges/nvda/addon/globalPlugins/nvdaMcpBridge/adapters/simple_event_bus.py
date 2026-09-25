# nvdaMcpBridge adapters -- SimpleEventBus: an in-process, thread-safe event bus.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: leaf adapter implementing EventBus; handlers are held weakly, and a dead one is dropped on emit.
# BUILT BY: plugin.py.
# USED BY: plugin.py, BridgeServer and the bridge dialog.

from __future__ import annotations

import threading
import uuid
import weakref
from collections import defaultdict
from typing import Any

from ..domain.entities.bridge_events import BridgeEvent, BridgeEventType
from ..domain.ports.event_bus import EventBus, EventHandler, SubscriptionToken


def _make_weak(handler: EventHandler) -> Any:
	try:
		return weakref.WeakMethod(handler)
	except TypeError:
		return weakref.ref(handler)


def _resolve(wh: Any) -> EventHandler | None:
	return wh()  # type: ignore[no-any-return]


class SimpleEventBus(EventBus):
	def __init__(self) -> None:
		self._lock = threading.Lock()
		self._entries: dict[SubscriptionToken, _Entry] = {}
		self._by_type: dict[BridgeEventType, list[SubscriptionToken]] = defaultdict(list)

	def subscribe(self, event_type: BridgeEventType, handler: EventHandler) -> SubscriptionToken:
		token = uuid.uuid4().hex
		entry = _Entry(event_type, _make_weak(handler))
		with self._lock:
			self._entries[token] = entry
			self._by_type[event_type].append(token)
		return token

	def unsubscribe(self, token: SubscriptionToken) -> None:
		with self._lock:
			entry = self._entries.pop(token, None)
			if entry is None:
				return
			tokens = self._by_type.get(entry.event_type)
			if tokens is not None:
				try:
					tokens.remove(token)
				except ValueError:
					pass

	def emit(self, event: BridgeEvent) -> None:
		# emit() runs on the server thread while subscribe and unsubscribe run on the main thread;
		# handlers run on the emitter's thread and marshal themselves.
		pairs: list[tuple[SubscriptionToken, _Entry]] = []
		with self._lock:
			for token in self._by_type.get(event.type, ()):
				entry = self._entries.get(token)
				if entry is not None:
					pairs.append((token, entry))

		dead: list[SubscriptionToken] = []
		for token, entry in pairs:
			fn = _resolve(entry.weak_handler)
			if fn is None:
				dead.append(token)
				continue
			try:
				fn(event)
			except Exception:
				pass

		if dead:
			with self._lock:
				for token in dead:
					self._entries.pop(token, None)
				by_type = self._by_type.get(event.type)
				if by_type is not None:
					for token in dead:
						try:
							by_type.remove(token)
						except ValueError:
							pass


class _Entry:
	__slots__ = ("event_type", "weak_handler")

	def __init__(self, event_type: BridgeEventType, weak_handler: Any) -> None:
		self.event_type = event_type
		self.weak_handler = weak_handler
