# nvdaMcpBridge domain -- WaitForUserReplyHandler: poll for the human's answer.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `waitForUserReply`, polling the outstanding UserPrompt for the human's answer.
# A poll is clamped to MAX_POLL_TIMEOUT because the inactivity watchdog is not refreshed when a handler
# returns; a longer poll would answer the agent and have the session torn down under it.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.user_prompt import PromptExpired
from .command_handler import MAX_POLL_TIMEOUT, CommandError, CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext


class WaitForUserReplyHandler(CommandHandler):
	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.WaitForUserReplyParams, request.params)
		prompt = ctx.get_outstanding_prompt()
		if prompt is None or prompt.ticket != params.ticket:
			raise CommandError(
				f"no outstanding prompt with ticket {params.ticket!r}; "
				f"the window may have expired or already been answered"
			)

		timeout = min(params.timeout, MAX_POLL_TIMEOUT)
		if timeout < params.timeout:
			ctx.transcript.note(
				f"waitForUserReply: poll timeout {params.timeout} clamped to "
				f"{MAX_POLL_TIMEOUT} (the inactivity window is not extended by a "
				f"blocking handler); poll again to keep waiting"
			)

		try:
			answered = prompt.wait(timeout)
		except PromptExpired:
			ctx.resume_speech()
			ctx.clear_outstanding_prompt()
			ctx.transcript.note(f"askUser: prompt {prompt.ticket!r} expired before answer")
			return protocol.WaitForUserReplyResult(answered=False)

		if answered:
			ctx.resume_speech()
			ctx.clear_outstanding_prompt()
			ctx.transcript.note(f"askUser: prompt {prompt.ticket!r} answered")
			return protocol.WaitForUserReplyResult(answered=True, text=prompt.text)

		return protocol.WaitForUserReplyResult(answered=False)
