# nvdaMcpBridge adapters -- NvdaLogCapture: journals NVDA's log for one session.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing LogCapture with a handler on NVDA's root logger.
# BUILT BY: plugin.py, once; start() and stop() reset it for each session.
# USED BY: the hello handler, SetLogLevelHandler, GetLogHandler and the Session's teardown.

from __future__ import annotations

import logging
import time
from typing import TYPE_CHECKING

from logHandler import Formatter, log

from ..domain.entities.log_journal import LogJournal, wire_level_for
from ..domain.ports.log_capture import LogCapture

if TYPE_CHECKING:
	from .. import protocol


class JournalHandler(logging.Handler):
	def __init__(self, journal: LogJournal) -> None:
		super().__init__()
		self.journal = journal
		# NVDA's formatTime gives nvda.log's own local-time shape and avoids time.localtime, which crashes
		# under some Universal CRT versions with a Unicode locale.
		self._formatter = Formatter()

	def emit(self, record: logging.LogRecord) -> None:
		# logging does not guard emit(), so anything raised here would break the NVDA line that logged.
		try:
			# NVDA has a single logger, so record.name is always "NVDA"; the module is the codepath NVDA
			# attaches, with NVDA's own fallback for records from other libraries.
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
				record.created,
			)
		except Exception:
			self.handleError(record)


class NvdaLogCapture(LogCapture):
	def __init__(self) -> None:
		self._journal = LogJournal()
		self._handler: JournalHandler | None = None
		self._previous_level: int | None = None
		self._current_level: protocol.LogLevel | None = None

	@property
	def current_level(self) -> protocol.LogLevel:
		# Before start(), report NVDA's actual level rather than failing the command that asked.
		if self._current_level is not None:
			return self._current_level
		return self._wire_level(log.root.level)

	def start(self, level: protocol.LogLevel | None) -> None:
		self._journal.reset()
		handler = JournalHandler(self._journal)
		self._previous_level = log.root.level
		if level is not None:
			log.root.setLevel(getattr(log, level.name))
		log.root.addHandler(handler)
		self._handler = handler
		self._current_level = level or self._wire_level(log.root.level)

	def stop(self) -> None:
		if self._handler is None:
			return
		log.root.removeHandler(self._handler)
		self._handler = None
		# Restore the level the user had before hello, whatever setLogLevel did since.
		if self._previous_level is not None:
			log.root.setLevel(self._previous_level)
			self._previous_level = None
		self._current_level = None
		self._journal.reset()

	def position(self) -> int:
		return self._journal.mark()

	def slice(
		self,
		start: int,
		end: int,
		*,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		return self._journal.slice(
			start,
			end,
			min_level=min_level.value if min_level else None,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def slice_since(
		self,
		position: int,
		*,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		return self._journal.slice_since(
			position,
			min_level=min_level.value if min_level else None,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def slice_last_seconds(
		self,
		seconds: float,
		*,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
		exclude: list[str] | None = None,
		fields: list[str] | None = None,
		max_entries: int = 200,
	) -> tuple[str, int, int, bool]:
		return self._journal.slice_last_seconds(
			seconds,
			time.time(),
			min_level=min_level.value if min_level else None,
			contains=contains,
			exclude=exclude,
			fields=fields,
			max_entries=max_entries,
		)

	def find_since(
		self,
		start: int,
		*,
		min_level: protocol.LogLevel | None = None,
		contains: list[str] | None = None,
	) -> tuple[int, str] | None:
		return self._journal.find_since(
			start,
			min_level=min_level.value if min_level else None,
			contains=contains,
		)

	def set_level(self, level: protocol.LogLevel) -> None:
		log.root.setLevel(getattr(log, level.name))
		self._current_level = level

	@staticmethod
	def _wire_level(level_no: int) -> protocol.LogLevel:
		from .. import protocol

		return protocol.LogLevel(wire_level_for(level_no))
