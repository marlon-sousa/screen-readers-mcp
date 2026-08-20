# nvdaMcpBridge domain -- AskUserHandler: present a prompt to the human.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `askUser`. Mints a ticket, stores a UserPrompt on the
# context, suspends speech suppression, asks the prompter to present it audibly,
# and returns the ticket immediately -- so the handler never blocks past the
# heartbeat window. The agent then polls with `waitForUserReply`.
#
# Only one outstanding prompt at a time: a second `askUser` is a CommandError.
# mutates_reader is True because this command changes what the human hears.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.user_prompt import UserPrompt
from .command_handler import CommandError, CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class AskUserHandler(CommandHandler):
	mutates_reader = True

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.AskUserParams, request.params)

		prompt = UserPrompt(params.prompt, ctx.clock)
		if not ctx.set_outstanding_prompt(prompt):
			raise CommandError(
				"a prompt is already outstanding; wait for it or let it expire before asking another"
			)

		ctx.suspend_speech()
		ctx.user_prompter.present(params.prompt, prompt.ticket)
		# A question is one of the three sounds that reach the human past the
		# suppression, so it resets the silence cap exactly as `announce` does --
		# after the prompt is presented, not before (spec 0032).
		ctx.note_audible()

		ctx.transcript.note(f"askUser: prompt presented (ticket {prompt.ticket})")
		return protocol.AskUserResult(ticket=prompt.ticket)
