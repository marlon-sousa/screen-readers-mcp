# nvdaMcpBridge adapters -- the FileWriter seam.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter seam that appends lines to a file.
# USED BY: adapters/file_transcript.py.
# IMPLEMENTED BY: adapters/text_file_writer.py and tests/fakes/file_writer.py.

from __future__ import annotations

from abc import ABC, abstractmethod


class FileWriter(ABC):
	@property
	@abstractmethod
	def path(self) -> str:
		pass

	@abstractmethod
	def open(self) -> None: ...

	@abstractmethod
	def write_line(self, text: str) -> None:
		"""Flushed per line, and never raises.

		A crashed harness must not lose the transcript's tail, and a broken log must not end a session.
		"""

	@abstractmethod
	def close(self) -> None: ...
