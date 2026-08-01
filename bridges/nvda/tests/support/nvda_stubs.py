# nvdaMcpBridge tests -- the NVDA modules the adapter edge imports.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# The bridge domain imports NVDA nowhere, so the suite needs no stubs at all --
# except for the handful of adapters under adapters/nvda_*.py, which are the
# NVDA-importing edge and are on pyright's ignore list. Those are worth testing
# anyway: spec 0020 shipped two defects in nvda_log_capture.py precisely because
# nothing exercised it, and spec 0021's per-capture journal position is the same
# kind of thing -- an adapter that read it once at start() would ship a constant
# integer that looks perfectly valid on the wire.
#
# The stubs live HERE rather than in each test module because sys.modules is
# process-wide: two modules each installing their own partial "logHandler" with
# setdefault meant whichever pytest collected first won, and the other silently
# tested against a stub missing the names it needed. One complete stub, installed
# idempotently, removes the ordering hazard.
#
# They mirror only what the adapters actually use, taken from NVDA's own source:
#
#   * logHandler.Logger carries the level constants, and IO is 12 -- ABOVE
#     DEBUG's 10, not below it (source/logHandler.py: `IO = 12`).
#   * logHandler.Formatter renders time as "%H:%M:%S" plus ".%03d" milliseconds,
#     local -- the shape nvda.log lines carry. NVDA overrides formatTime only to
#     dodge a Universal CRT crash (#12160); the OUTPUT is the stdlib's, so this
#     uses the stdlib implementation with NVDA's two format attributes.
#   * extensionPoints Action/Filter expose register/unregister and are fired BY
#     NVDA, never by us -- so the stub keeps the handlers and lets a test fire
#     them, which is exactly what NVDA does at the moment of capture.

from __future__ import annotations

import logging
import sys
import types
from typing import Any


class StubFormatter(logging.Formatter):
	"""NVDA's Formatter, reduced to the time format the log adapter borrows."""

	default_time_format = "%H:%M:%S"
	default_msec_format = "%s.%03d"


class StubLog:
	"""Stands in for logHandler.log: NVDA's level constants, a real root logger.

	``info`` records rather than emits, because the silent speech source writes
	its session markers through it and a test needs to see exactly those.
	"""

	DEBUG = logging.DEBUG  # 10
	IO = 12  # NVDA's custom level, between DEBUG and DEBUGWARNING
	DEBUGWARNING = 15
	INFO = logging.INFO  # 20
	WARNING = logging.WARNING  # 30
	ERROR = logging.ERROR  # 40

	def __init__(self) -> None:
		self.root = logging.getLogger("nvda-mcp-bridge-test-root")
		self.root.propagate = False
		self.root.handlers.clear()
		self.root.setLevel(logging.INFO)
		#: Everything written through info(), in order.
		self.messages: list[str] = []

	def info(self, message: str) -> None:
		self.messages.append(message)


class StubExtensionPoint:
	"""Stands in for an NVDA Action/Filter: holds handlers, fires on demand."""

	def __init__(self) -> None:
		self.handlers: list[Any] = []

	def register(self, handler: Any) -> None:
		self.handlers.append(handler)

	def unregister(self, handler: Any) -> None:
		if handler in self.handlers:
			self.handlers.remove(handler)


#: The one instance of each, shared by every test module that installs them --
#: which is what makes the install idempotent and order-independent.
log = StubLog()
filter_speechSequence = StubExtensionPoint()
pre_speechQueued = StubExtensionPoint()
pre_writeCells = StubExtensionPoint()


def install() -> None:
	"""Put the stub NVDA modules in sys.modules. Safe to call more than once."""
	if "logHandler" not in sys.modules:
		log_handler = types.ModuleType("logHandler")
		log_handler.log = log  # type: ignore[attr-defined]
		log_handler.Formatter = StubFormatter  # type: ignore[attr-defined]
		sys.modules["logHandler"] = log_handler

	if "speech.extensions" not in sys.modules:
		extensions = types.ModuleType("speech.extensions")
		extensions.filter_speechSequence = filter_speechSequence  # type: ignore[attr-defined]
		extensions.pre_speechQueued = pre_speechQueued  # type: ignore[attr-defined]
		speech = sys.modules.get("speech") or types.ModuleType("speech")
		speech.extensions = extensions  # type: ignore[attr-defined]
		sys.modules["speech"] = speech
		sys.modules["speech.extensions"] = extensions

	if "braille" not in sys.modules:
		braille = types.ModuleType("braille")
		braille.pre_writeCells = pre_writeCells  # type: ignore[attr-defined]
		sys.modules["braille"] = braille


def reset() -> None:
	"""Forget every registration and message; the stubs outlive any one test."""
	log.messages.clear()
	for point in (filter_speechSequence, pre_speechQueued, pre_writeCells):
		point.handlers.clear()
