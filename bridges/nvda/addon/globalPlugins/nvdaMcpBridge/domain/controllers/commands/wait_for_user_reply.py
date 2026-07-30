# nvdaMcpBridge domain -- WaitForUserReplyHandler: poll for the human's answer.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `waitForUserReply`. Looks up the ticket, waits on the
# UserPrompt entity, and on a real answer resumes speech suppression and clears
# the outstanding prompt. A poll miss (timeout, no answer yet) leaves the window
# open. An expired or cancelled prompt resumes, clears, and returns
# answered=false.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.user_prompt import PromptExpired
from .command_handler import CommandError, CommandHandler

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

        try:
            answered = prompt.wait(params.timeout)
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
