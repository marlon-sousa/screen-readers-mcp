# nvdaMcpBridge domain -- CommandHandler: the per-command controller interface.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: the interface every command handler implements (an abc.ABC, not a
# Protocol -- an incomplete handler fails at construction). One handler per wire
# command; the Session dispatches to it and wraps the outcome.
# USED BY: the Session (dispatch) and registry.py (builds the map).
#
# The contract is deliberately thin so the Session stays a pure dispatcher and
# all error/id/heartbeat handling stays in one place:
#   * execute returns a wire RESULT dataclass; the Session wraps it in a Response
#     with the request id.
#   * to FAIL a command, a handler RAISES -- CommandError for its own domain
#     errors, or lets a protocol.ValidationError (bad params) / GestureError
#     propagate. The Session turns any of these into an error Response and, when
#     established, carries on; a pre-hello failure ends the handshake.
# Two class attributes carry the policy that used to be ``if cmd == ...`` in the
# loop, now declared on the handler itself.

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
	from .... import protocol
	from .session_context import SessionContext


class CommandError(Exception):
	"""A handler-level failure that becomes an error Response (e.g. version
	mismatch, not-yet-implemented). Distinct from a transport/validation fault."""


class CommandHandler(ABC):
	"""Handles one wire command over a SessionContext."""

	#: Whether a successful call resets the command-inactivity watchdog. ``ping``
	#: sets this False -- it proves liveness (heartbeat) but not that the agent is
	#: still testing.
	resets_inactivity: bool = True

	#: Whether this command is valid before ``hello``. Only the hello handler sets
	#: it True; every other command is rejected until the handshake completes.
	available_before_hello: bool = False

	#: Whether this command moves the user's machine (a keypress, typed text, a
	#: config write) rather than only observing it. Set True on the handlers that
	#: do -- ``PressGestureHandler``, ``TypeTextHandler``, ``SetConfigHandler`` --
	#: and an observe-only session (spec 0017) refuses them. The base default is
	#: False and the failure mode of forgetting to opt in is "allowed", so a
	#: future mutating command must set this deliberately; registry.py's
	#: enumeration test is what makes forgetting visible.
	mutates_reader: bool = False

	@abstractmethod
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		"""Run the command and return its wire result, or raise to fail it."""
