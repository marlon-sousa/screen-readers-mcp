# nvdaMcpBridge domain -- GetDocumentSnapshotHandler: answer "what is on this page".
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: command handler for `getDocumentSnapshot`.
# mutates_reader is False because the adapter neither speaks nor moves the caret.
# No document is a result with hasDocument False, not an error.

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from .... import protocol
from ...entities.document_snapshot import DocumentSnapshot
from .command_handler import CommandHandler
from .wallclock import format_wallclock

if TYPE_CHECKING:
	from .session_context import SessionContext


class GetDocumentSnapshotHandler(CommandHandler):
	mutates_reader = False

	def execute(self, ctx: SessionContext, request: protocol.Request) -> Any:
		params = protocol.from_dict(protocol.DocumentSnapshotParams, request.params)
		snapshot = DocumentSnapshot(
			from_line=params.fromLine,
			max_lines=params.maxLines,
			max_chars=params.maxChars,
		)
		# Stamped before the read, so capturedAt is a lower bound on the document's age.
		captured_at = format_wallclock(ctx.clock.time())
		read = ctx.adapter_set.document_reader.read(snapshot)
		if read is None:
			return protocol.DocumentSnapshotResult(hasDocument=False, capturedAt=captured_at)
		return protocol.DocumentSnapshotResult(
			hasDocument=True,
			capturedAt=captured_at,
			title=read.title,
			lines=snapshot.lines,
			fromLine=snapshot.from_line,
			toLine=snapshot.to_line,
			truncatedBy=snapshot.truncated_by,
		)
