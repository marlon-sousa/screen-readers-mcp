# nvdaMcpBridge domain -- SetStateHandler: arrive at a reader mode, idempotently.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `setState`. Validates the request against the
#       SET-DOMAIN, asks the StateSetter port for each field present, and
#       assembles the state AFTER plus the list of fields this call moved.
#
# IT DOES NOT COMPARE. The compare-and-set lives in the adapter, inside NVDA, on
# NVDA's own thread (spec 0033 Part 3.2): a handler that read the inspector,
# compared here and then wrote would rebuild the race the command exists to
# remove. This handler's job is the set-domain, the dispatch, and the answer.
#
# MUTATES_READER = True: it changes the reader's behaviour as surely as the
# keypress it replaces, so an observe-only session (spec 0017) refuses it exactly
# as it refuses a gesture.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandError, CommandHandler
from .observation import state_snapshot

if TYPE_CHECKING:
	from .session_context import SessionContext

#: The browse-mode values that can be ARRIVED AT. `"none"` is readable and not
#: settable: it means the focus has no treeInterceptor at all, which cannot be
#: conjured. Refusing it here -- before the adapter is reached -- is what honours
#: the tri-state instead of quietly widening it (spec 0033 Part 3.1a).
_SETTABLE_BROWSE_MODES: frozenset[str] = frozenset({"browse", "focus"})

#: Why each mode `getState` reports is not in the first cut's set-domain. Named
#: rather than dropped: `from_dict` IGNORES a field the params type does not
#: declare, so a client asking to set `speechMode` would get `changed: []` back --
#: the exact reading of "it was already so". One observable, two situations, in
#: the one field built to separate two situations (spec 0033 Part 3.1).
_NOT_SETTABLE: dict[str, str] = {
	"speechMode": (
		"it can leave the human at the reader unable to hear their own machine, "
		"and the silence cap counts suppression, not a speech mode an agent "
		"switched off"
	),
	"sleepMode": (
		"it can leave the human at the reader unable to hear their own machine, "
		"and it is per-application, so a session could silence an app and forget"
	),
	"inputHelp": (
		"it exists to DESCRIBE keys instead of acting on them, so turning it on "
		"would silently disarm every gesture sent afterwards"
	),
}


class SetStateHandler(CommandHandler):
	mutates_reader = True

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		self._refuse_unsettable(request.params)
		params = protocol.from_dict(protocol.SetStateParams, request.params)

		changed: list[str] = []
		if params.browseMode is not None:
			if params.browseMode.value not in _SETTABLE_BROWSE_MODES:
				settable = ", ".join(sorted(_SETTABLE_BROWSE_MODES))
				raise CommandError(
					f"browseMode {params.browseMode.value!r} cannot be set: "
					f"it reports that the focus has no browsable document, which cannot be "
					f"created by asking for it. Settable values are {settable}."
				)
			if ctx.adapter_set.state_setter.set_browse_mode(params.browseMode.value):
				changed.append("browseMode")

		# The state AFTER, never `ok: true`: the caller's next question is always
		# "am I there now", and answering it in the same round trip costs nothing
		# (spec 0025). Sampled after every write, so a caller that reads the result
		# never needs the re-check a toggle forces.
		return protocol.SetStateResult(state=state_snapshot(ctx), changed=changed)

	@staticmethod
	def _refuse_unsettable(params: dict[str, Any]) -> None:
		"""Refuse a mode this reader reports but does not let a session set.

		The get-domain is wider than the set-domain, and an agent has every reason
		to expect the mirror to be exact. Saying which field and WHY costs one
		message and saves the agent from concluding the write succeeded.
		"""
		for field, reason in _NOT_SETTABLE.items():
			if field in params:
				raise CommandError(f"{field} cannot be set: {reason}")
