# nvdaMcpBridge adapters -- SimpleEventBus: an in-process event bus.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: LEAF adapter. IMPLEMENTS the EventBus port. subscribe() returns an
#       int token; unsubscribe(token) removes it. Handlers are stored as
#       weakrefs so a destroyed subscriber is skipped and cleaned up on the
#       next emit — no leak, even if the token is never passed to unsubscribe.
#       No decisions — no unit test file.
# USED BY: plugin.py (builds one, hands it to BridgeServer and the dialog).
# BUILT BY: plugin.py at singleton scope.

from __future__ import annotations

import weakref
from collections import defaultdict
from typing import Union

from ..domain.entities.bridge_events import BridgeEvent, BridgeEventType
from ..domain.ports.event_bus import EventBus, EventHandler, SubscriptionToken

#: A weak reference to a handler: WeakMethod for bound methods, ref() otherwise.
_WeakHandler = Union["weakref.WeakMethod[EventHandler]", "weakref.ReferenceType[EventHandler]"]


def _make_weak(handler: EventHandler) -> _WeakHandler:
	try:
		return weakref.WeakMethod(handler)
	except TypeError:
		return weakref.ref(handler)


def _resolve(wh: _WeakHandler) -> EventHandler | None:
	result = wh()
	return result  # type: ignore[return-value]


#: Internal record for one subscription.
class _Entry:
	__slots__ = ("event_type", "weak_handler")

	def __init__(self, event_type: BridgeEventType, weak_handler: _WeakHandler) -> None:
		self.event_type = event_type
		self.weak_handler = weak_handler


class SimpleEventBus(EventBus):
	"""One dict mapping token → _Entry, plus a per-type index for fast emit."""

	def __init__(self) -> None:
		self._next_token = 1
		self._entries: dict[SubscriptionToken, _Entry] = {}
		# Per-type index: event_type → list of tokens (ordered by registration).
		self._by_type: dict[BridgeEventType, list[SubscriptionToken]] = defaultdict(list)

	def subscribe(self, event_type: BridgeEventType, handler: EventHandler) -> SubscriptionToken:
		token = self._next_token
		self._next_token += 1
		self._entries[token] = _Entry(event_type, _make_weak(handler))
		self._by_type[event_type].append(token)
		return token

	def unsubscribe(self, token: SubscriptionToken) -> None:
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
		tokens = self._by_type.get(event.type)
		if not tokens:
			return
		dead: list[SubscriptionToken] = []
		for token in tuple(tokens):
			entry = self._entries.get(token)
			if entry is None:
				dead.append(token)
				continue
			fn = _resolve(entry.weak_handler)
			if fn is None:
				dead.append(token)
				del self._entries[token]
				continue
			try:
				fn(event)
			except Exception:
				pass
		for token in dead:
			try:
				tokens.remove(token)
			except ValueError:
				pass
