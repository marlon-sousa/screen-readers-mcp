# nvdaMcpBridge domain -- GetDocumentSnapshotHandler: answer "what is on this page".
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: command handler for `getDocumentSnapshot` (spec 0026). Builds the
#       DocumentSnapshot entity from the request's bounds, hands it to the
#       DocumentReader port to fill, stamps the instant, and maps to the wire.
#
# mutates_reader stays False, and it is a claim rather than a default: the
# adapter renders through NVDA's speech layer WITHOUT speaking, and walks its own
# TextInfo WITHOUT moving the caret, so an observe-only session (spec 0017) may
# call this and the user's reader is exactly where they left it afterwards.
#
# WHY THE STAMP IS TAKEN HERE and not in the adapter: `capturedAt` is the whole
# of what stops this result reading as a description of the page rather than of
# the page at one instant, and a handler with an injected Clock can be tested for
# it. The adapter has no clock and should not grow one.
#
# NO DOCUMENT IS A RESULT, NOT AN ERROR. A dialog, the desktop, a native app: the
# port answers None and this returns `hasDocument: False` with everything else
# empty and the stamp still set. Raising instead would make "you are not in a
# document" -- an ordinary fact an agent branches on -- indistinguishable from a
# fault, which is the confusion specs 0020, 0021, 0023 and 0024 each had to undo.

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
		# Stamped BEFORE the read, not after: the instant an agent cares about is
		# when the picture was taken, and on a long document the two differ by the
		# whole render. Erring towards the earlier one keeps `capturedAt` a lower
		# bound on the document's age rather than an optimistic one.
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
