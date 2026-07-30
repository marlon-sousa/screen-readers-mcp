# nvdaMcpBridge domain -- WaitForUserReplyHandler: poll for the human's answer.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `waitForUserReply`. Looks up the ticket, waits on the
# UserPrompt entity, and on a real answer resumes speech suppression and clears
# the outstanding prompt. A poll miss (timeout, no answer yet) leaves the window
# open. An expired or cancelled prompt resumes, clears, and returns
# answered=false.
#
# A single poll is CLAMPED to MAX_POLL_TIMEOUT. The command-inactivity watchdog
# is measured from the moment a command is dispatched and is deliberately not
# refreshed when a handler returns (spec 0016: inactivity answers "has the agent
# abandoned this session?", so a blocking handler must not extend it). A poll
# allowed to block longer than that window would therefore answer the agent and
# have the session torn down under it, one line later. Clamping here protects
# every client, not just the one whose tool schema says 110.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.user_prompt import PromptExpired
from .command_handler import CommandError, CommandHandler

if TYPE_CHECKING:
	from .session_context import SessionContext

#: The longest a single poll may block, comfortably inside the 120 s
#: command-inactivity window (SessionConfig.inactivity_timeout). The window's own
#: 300 s lifetime is unaffected -- the agent simply polls again.
MAX_POLL_TIMEOUT: float = 110.0


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
			ctx.transcript.note(
				f"askUser: prompt {prompt.ticket!r} expired before answer"
			)
			return protocol.WaitForUserReplyResult(answered=False)

		if answered:
			ctx.resume_speech()
			ctx.clear_outstanding_prompt()
			ctx.transcript.note(
				f"askUser: prompt {prompt.ticket!r} answered"
			)
			return protocol.WaitForUserReplyResult(answered=True, text=prompt.text)

		# Poll miss: the window is still open but nothing yet.
		return protocol.WaitForUserReplyResult(answered=False)
