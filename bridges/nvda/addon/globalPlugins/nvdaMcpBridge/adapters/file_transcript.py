# nvdaMcpBridge adapters -- FileTranscript: the Transcript vocabulary.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing the Transcript port over the FileWriter seam.
# USED BY: the Session controller.
# BUILT BY: create_session_log.

from __future__ import annotations

import os
from collections.abc import Callable
from datetime import datetime
from pathlib import Path
from typing import TYPE_CHECKING

from ..domain.ports.transcript import Transcript
from .text_file_writer import TextFileWriter

if TYPE_CHECKING:
	from .ports.file_writer import FileWriter

DEFAULT_KEEP: int = 20


def _wallclock() -> str:
	return datetime.now().strftime("%Y-%m-%d %H:%M:%S.%f")[:-3]


class FileTranscript(Transcript):
	def __init__(self, writer: FileWriter, *, timestamp: Callable[[], str] = _wallclock) -> None:
		self._writer = writer
		self._timestamp = timestamp
		self._open = False

	@property
	def path(self) -> str:
		return self._writer.path

	def open(self) -> None:
		self._writer.open()
		self._open = True

	def _line(self, text: str) -> None:
		if not self._open:
			return
		self._writer.write_line(f"{self._timestamp()} {text}")

	def session_opened(self, mode: str, synth: str, persona: str) -> None:
		# An absent persona is written as `-` so every SESSION OPEN line has the same shape.
		self._line(f"SESSION OPEN mode={mode} synth={synth} persona={persona or '-'}")

	def gesture(self, gesture_id: str) -> None:
		self._line(f"GESTURE {gesture_id}")

	def typed(self, length: int) -> None:
		self._line(f"TYPE length={length}")

	def speech(self, text: str) -> None:
		self._line(f"SPEECH {text!r}")

	def note(self, text: str) -> None:
		self._line(f"NOTE {text}")

	def session_closed(self, reason: str) -> None:
		self._line(f"SESSION CLOSE reason={reason}")
		self._open = False
		self._writer.close()


def create_session_log(
	logs_dir: str | os.PathLike[str],
	*,
	keep: int = DEFAULT_KEEP,
	timestamp: Callable[[], str] = _wallclock,
	name_stamp: Callable[[], str] | None = None,
) -> FileTranscript:
	directory = Path(logs_dir)
	directory.mkdir(parents=True, exist_ok=True)
	stamp = (name_stamp or (lambda: datetime.now().strftime("%Y%m%d-%H%M%S-%f")))()
	transcript = FileTranscript(TextFileWriter(directory / f"session-{stamp}.log"), timestamp=timestamp)
	transcript.open()
	_prune(directory, keep)
	return transcript


def _prune(directory: Path, keep: int) -> None:
	# Names embed a time-sortable stamp, so a lexical sort is chronological.
	existing = sorted(directory.glob("session-*.log"), key=lambda p: p.name)
	for stale in existing[: max(0, len(existing) - keep)]:
		try:
			stale.unlink()
		except OSError:
			pass
