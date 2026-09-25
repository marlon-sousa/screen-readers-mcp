# nvdaMcpBridge domain -- SetStateHandler: arrive at a reader mode, idempotently.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `setState`, reporting the state after and the fields it moved.
# The compare-and-set must stay in the adapter on NVDA's thread; comparing here would reintroduce the race.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from .command_handler import CommandError, CommandHandler
from .observation import state_snapshot

if TYPE_CHECKING:
	from .session_context import SessionContext

# "none" means the focus has no treeInterceptor, which cannot be created by asking.
_SETTABLE_BROWSE_MODES: frozenset[str] = frozenset({"browse", "focus"})

# Named rather than dropped: from_dict ignores undeclared fields, so they would read as "already so".
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

		return protocol.SetStateResult(state=state_snapshot(ctx), changed=changed)

	@staticmethod
	def _refuse_unsettable(params: dict[str, Any]) -> None:
		for field, reason in _NOT_SETTABLE.items():
			if field in params:
				raise CommandError(f"{field} cannot be set: {reason}")
