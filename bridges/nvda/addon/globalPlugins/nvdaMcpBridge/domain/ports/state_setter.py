# nvdaMcpBridge domain -- the StateSetter port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: domain port. ARRIVES at a mode the reader already gives its user a
#       command for, idempotently. Separate from state_inspector.py rather than
#       added to it: a port called *inspector* that mutates is a mislabelled
#       role, and the two are separately implementable -- a bridge may well read
#       a mode it cannot set (spec 0033).
# USED BY: the SetStateHandler.
# IMPLEMENTED BY: adapters/nvda_state_setter.py (NVDA's own browse-mode path,
#                 never a synthetic keypress); tests/fakes/state_setter.py
#                 FakeStateSetter.
#
# THE COMPARE HAPPENS INSIDE THE ADAPTER, on the reader's own thread, never in
# the handler. A handler that read through the inspector, compared in the domain
# and then asked this port to write would rebuild the very race this command
# exists to remove -- a shorter window, the same shape. So the contract is
# compare-and-set: pass the target, get back whether anything moved.
#
# What may be set at all is a MEMBERSHIP RULE, not a list (spec 0033 Part 2):
#
#   A mode may be set only where the reader already gives its user a command
#   for it. It adds idempotence, never capability.
#
# browse mode qualifies (NVDA+space). speech mode and sleep mode qualify and are
# still held back, because they are the two that can leave a human unable to hear
# their own machine. Input help does not qualify at all: it exists to DESCRIBE
# keys instead of acting on them, so a session that turned it on would silently
# disarm every gesture it sent afterwards.

from __future__ import annotations

from abc import ABC, abstractmethod


class StateSetError(Exception):
	"""A mode that cannot be reached from here, said in terms the agent can act on.

	Part of this port's contract, so it lives here -- the rule config_accessor.py
	and gesture_sender.py already follow. A normal per-command failure the Session
	reports and recovers from, never a session-ending fault.

	The message must name the SPECIFIC obstacle ("the focused object is not a
	browsable document"), because a bare failure sends an agent looking in the
	wrong component -- which is the failure spec 0027's reporter demonstrated and
	spec 0023 predicted.
	"""


class StateSetter(ABC):
	"""Arrives at a reader mode, idempotently, comparing inside the reader."""

	@abstractmethod
	def set_browse_mode(self, target: str) -> bool:
		"""Put the focus in ``"browse"`` or ``"focus"`` mode; say whether it moved.

		Returns ``True`` when this call changed the mode and ``False`` when the
		reader was already in it. Already-there must do NOTHING AT ALL -- no
		script, no earcon, no utterance -- so a human in a live session is not
		made to listen to a tone every time an agent restates a precondition.

		``target`` is ``"browse"`` or ``"focus"``. ``"none"`` is not settable and
		is refused by the handler before this port is reached.

		Raises :class:`StateSetError` when the focused object is not a browsable
		document, naming that as the reason.
		"""
