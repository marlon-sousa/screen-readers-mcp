# nvdaMcpBridge tests -- the NVDA modules the adapter edge imports.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: test scaffolding; stubs for the NVDA modules that adapters/nvda_*.py import, mirroring NVDA 2026.1.
#
# One shared, idempotent stub per module: sys.modules is process-wide, so per-module stubs race on collection.

from __future__ import annotations

import logging
import sys
import types
from typing import Any


class StubFormatter(logging.Formatter):
	default_time_format = "%H:%M:%S"
	default_msec_format = "%s.%03d"


class StubLog:
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
		self.messages: list[str] = []

	def info(self, message: str) -> None:
		self.messages.append(message)

	def exception(self, message: str) -> None:
		self.messages.append(message)


class StubExtensionPoint:
	def __init__(self) -> None:
		self.handlers: list[Any] = []

	def register(self, handler: Any) -> None:
		self.handlers.append(handler)

	def unregister(self, handler: Any) -> None:
		if handler in self.handlers:
			self.handlers.remove(handler)


class StubEventQueue:
	"""Holds queued callbacks until pump(): running them on submit hides the recursion to avoid."""

	def __init__(self) -> None:
		self.queued: list[tuple[Any, tuple[Any, ...]]] = []

	def pump(self) -> None:
		while self.queued:
			func, args = self.queued.pop(0)
			func(*args)


class StubSpeechCommand:
	pass


class StubBaseCallbackCommand(StubSpeechCommand):
	def run(self) -> None:
		raise NotImplementedError


class StubCallbackCommand(StubBaseCallbackCommand):
	def __init__(self, callback: Any, name: str | None = None) -> None:
		self._callback = callback
		self._name = name or repr(callback)

	def run(self) -> None:
		self._callback()


class StubBeepCommand(StubBaseCallbackCommand):
	def __init__(self, hz: int = 440, length: int = 10) -> None:
		self.hz = hz
		self.length = length
		self.beeped = False

	def run(self) -> None:
		self.beeped = True


class StubWaveFileCommand(StubBaseCallbackCommand):
	def __init__(self, fileName: str = "sound.wav") -> None:
		self.fileName = fileName
		self.played = False

	def run(self) -> None:
		self.played = True


class StubSayAllHandler:
	"""In NVDA 2026.1 _getActiveSayAll is a weakref that keeps returning the reader after the read stopped."""

	def __init__(self, reader: Any = None) -> None:
		self.reader = reader

	def _getActiveSayAll(self) -> Any:
		return self.reader


class StubTextReader:
	"""_TextReader: nulls `reader` in stop(), which is what stop() guards on."""

	def __init__(self, *, stopped: bool = False) -> None:
		self.reader = None if stopped else object()


class StubObjectsReader:
	"""_ObjectsReader: the same, through `walker` instead."""

	def __init__(self, *, stopped: bool = False) -> None:
		self.walker = None if stopped else object()


log = StubLog()
eventQueue = StubEventQueue()
sayAll = types.ModuleType("speech.sayAll")
sayAll.SayAllHandler = None  # type: ignore[attr-defined]
filter_speechSequence = StubExtensionPoint()
pre_speechQueued = StubExtensionPoint()
pre_writeCells = StubExtensionPoint()


def set_say_all_handler(handler: Any) -> None:
	sayAll.SayAllHandler = handler  # type: ignore[attr-defined]


def _queueFunction(queue: StubEventQueue, func: Any, *args: Any, **kwargs: Any) -> None:
	queue.queued.append((func, args))


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

	if "speech.commands" not in sys.modules:
		commands = types.ModuleType("speech.commands")
		commands.SpeechCommand = StubSpeechCommand  # type: ignore[attr-defined]
		commands.BaseCallbackCommand = StubBaseCallbackCommand  # type: ignore[attr-defined]
		commands.CallbackCommand = StubCallbackCommand  # type: ignore[attr-defined]
		commands.BeepCommand = StubBeepCommand  # type: ignore[attr-defined]
		commands.WaveFileCommand = StubWaveFileCommand  # type: ignore[attr-defined]
		speech = sys.modules.get("speech") or types.ModuleType("speech")
		speech.commands = commands  # type: ignore[attr-defined]
		sys.modules["speech"] = speech
		sys.modules["speech.commands"] = commands

	if "speech.sayAll" not in sys.modules:
		speech = sys.modules.get("speech") or types.ModuleType("speech")
		speech.sayAll = sayAll  # type: ignore[attr-defined]
		sys.modules["speech"] = speech
		sys.modules["speech.sayAll"] = sayAll

	if "queueHandler" not in sys.modules:
		queue_handler = types.ModuleType("queueHandler")
		queue_handler.eventQueue = eventQueue  # type: ignore[attr-defined]
		queue_handler.queueFunction = _queueFunction  # type: ignore[attr-defined]
		sys.modules["queueHandler"] = queue_handler

	if "braille" not in sys.modules:
		braille = types.ModuleType("braille")
		braille.pre_writeCells = pre_writeCells  # type: ignore[attr-defined]
		sys.modules["braille"] = braille


def reset() -> None:
	"""Forget every registration and message; the stubs outlive any one test."""
	log.messages.clear()
	eventQueue.queued.clear()
	sayAll.SayAllHandler = None  # type: ignore[attr-defined]
	for point in (filter_speechSequence, pre_speechQueued, pre_writeCells):
		point.handlers.clear()
