# nvdaMcpBridge adapters -- NvdaLogCapture: journals NVDA's log for one session.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the LogCapture domain port with NVDA's own logging
#       machinery. On pyright's ignore list (imports NVDA via ``logHandler``);
#       validated by the live-NVDA checklist (spec 0020) and by
#       tests/unit/adapters/test_nvda_log_capture.py, which stubs ``logHandler``.
# BUILT BY: plugin.py (once, like NvdaSessionSignals/NvdaAnnouncer) and injected
#           via wiring.build_session.
# USED BY: the hello handler (start, with the requested level), SetLogLevelHandler
#          (set_level), GetLogHandler (position/slice), and the Session's teardown
#          (stop, unconditionally).
#
# A reused singleton, not built fresh per connection: the bridge serves one
# session at a time (AGENTS.md), so start()/stop() simply reset this instance's
# per-session state each time.
#
# Supersedes 0009's FileHandler: the journal replaces the per-session capture file.
# The level raise is global (on ``log.root``), so NVDA's own ``nvda.log`` already
# holds identical records; the session transcript's timestamps bracket the window
# in it. A ``logging.Handler`` subclass feeds records into the LogJournal entity
# BEFORE formatting, so filtering is exact and projection is free.
#
# Two details are NVDA's, not ours, and are borrowed rather than reimplemented:
#
# * The module name is the ``codepath`` attribute NVDA attaches to every record
#   (``speech.speech.speak``), NOT ``record.name`` -- NVDA has a single logger, so
#   ``record.name`` is the constant "NVDA" and would make ``exclude`` useless.
#   The fallback for records from other libraries is NVDA's own (logHandler.py).
# * The timestamp comes from NVDA's ``Formatter.formatTime``, which is local time
#   in nvda.log's exact shape and deliberately avoids ``time.localtime`` (it
#   crashes under some Universal CRT versions with a Unicode locale, NVDA #12160).

from __future__ import annotations

import logging
from typing import TYPE_CHECKING

from logHandler import Formatter, log

from ..domain.entities.log_journal import LogJournal, wire_level_for
from ..domain.ports.log_capture import LogCapture

if TYPE_CHECKING:
	from .. import protocol


class JournalHandler(logging.Handler):
	"""A logging handler that writes structured records into a LogJournal."""

	def __init__(self, journal: LogJournal) -> None:
		super().__init__()
		self.journal = journal
		# NVDA's own formatter, used ONLY for formatTime -- so a slice's timestamps
		# are the same local-time strings the user's nvda.log shows for the same
		# records, and stay that way if NVDA changes the format.
		self._formatter = Formatter()

	def emit(self, record: logging.LogRecord) -> None:
		# logging does NOT guard emit(): Handler.handle and Logger.callHandlers
		# both call it bare, so anything raised here propagates into whatever line
		# of NVDA called log.debug(). Inside a screen reader that turns a bad
		# journal record into a broken reader, so this catches everything and
		# routes it through the standard handleError path.
		try:
			# NVDA attaches `codepath` (module.class.function) to its own records;
			# records from other libraries reaching the root logger have none, and
			# NVDA's Formatter makes the same fallback for them.
			codepath = getattr(record, "codepath", None)
			if not codepath:
				codepath = f"{record.name}.{record.funcName}"
			self.journal.append(
				record.levelno,
				record.levelname,
				str(codepath),
				record.getMessage(),
				self._formatter.formatTime(record),
				record.threadName or "",
				record.thread or 0,
			)
		except Exception:
			self.handleError(record)


class NvdaLogCapture(LogCapture):
	"""Journals NVDA's log into an in-memory LogJournal, replacing 0009's file."""

	def __init__(self) -> None:
		self._journal = LogJournal()
		self._handler: JournalHandler | None = None
		self._previous_level: int | None = None
		self._current_level: protocol.LogLevel | None = None

	# -- port implementation ---------------------------------------------------

	@property
	def current_level(self) -> protocol.LogLevel:
		# Read before start() only if the wiring is wrong; report NVDA's actual
		# floor rather than raising, since this feeds a diagnostic field and an
		# AssertionError here would fail the command that asked for the slice.
		if self._current_level is not None:
			return self._current_level
		return self._wire_level(log.root.level)

	def start(self, level: protocol.LogLevel | None) -> None:
		self._journal.reset()
		handler = JournalHandler(self._journal)
		self._previous_level = log.root.level
		# Map the requested wire level to NVDA's logger level number, or leave
		# the root logger unchanged if no level was requested.
		if level is not None:
			log.root.setLevel(getattr(log, level.name))
		log.root.addHandler(handler)
		self._handler = handler
		# Record the level now in force for capturedAtLevel reporting.
		self._current_level = level or self._wire_level(log.root.level)

	def stop(self) -> None:
		if self._handler is None:
			return
		log.root.removeHandler(self._handler)
		self._handler = None
		# Restore the floor the user's NVDA had before hello, whatever setLogLevel
		# did in between -- _previous_level is written by start() alone.
		if self._previous_level is not None:
			log.root.setLevel(self._previous_level)
			self._previous_level = None
		self._current_level = None
		self._journal.reset()

	def position(self) -> int:
		return self._journal.mark()

	def slice(
		self, start: int, end: int, *,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		return self._journal.slice(
			start, end,
			min_level=min_level.value if min_level else None,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def set_level(self, level: protocol.LogLevel) -> None:
		log.root.setLevel(getattr(log, level.name))
		self._current_level = level

	# -- helpers ---------------------------------------------------------------

	@staticmethod
	def _wire_level(level_no: int) -> protocol.LogLevel:
		"""Map an NVDA logger level number to the wire enum."""
		from .. import protocol

		return protocol.LogLevel(wire_level_for(level_no))
