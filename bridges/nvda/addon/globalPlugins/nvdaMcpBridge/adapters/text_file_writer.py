# nvdaMcpBridge adapters -- TextFileWriter: the FileWriter leaf.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: leaf adapter implementing FileWriter with real file IO.
# BUILT BY: create_session_log.
# USED BY: adapters/file_transcript.py, through the FileWriter seam.

from __future__ import annotations

import os
from pathlib import Path
from typing import TextIO

from .ports.file_writer import FileWriter


class TextFileWriter(FileWriter):
	def __init__(self, path: str | os.PathLike[str]) -> None:
		self._path = Path(path)
		self._file: TextIO | None = None

	@property
	def path(self) -> str:
		return str(self._path)

	def open(self) -> None:
		self._path.parent.mkdir(parents=True, exist_ok=True)
		# The handle stays open for the whole session; close() closes it.
		self._file = open(self._path, "w", encoding="utf-8", buffering=1)  # noqa: SIM115

	def write_line(self, text: str) -> None:
		if self._file is None:
			return
		try:
			self._file.write(text + "\n")
			self._file.flush()
		except OSError:
			pass  # a failed transcript write must never take a session down

	def close(self) -> None:
		f = self._file
		self._file = None
		if f is not None:
			try:
				f.close()
			except OSError:
				pass
