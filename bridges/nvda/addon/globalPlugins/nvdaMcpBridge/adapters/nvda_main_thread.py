# nvdaMcpBridge adapters -- run_on_main: marshal a call onto NVDA's wx main thread.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: shared edge helper that marshals a call onto NVDA's wx main thread.
# USED BY: the NVDA adapters; touching NVDA off its main thread races NVDA.
# Fire-and-forget by default, so a main-thread caller never deadlocks; block=True only off the main thread
# with the main thread free.

from __future__ import annotations

import threading
from collections.abc import Callable
from typing import Any

import wx

_MAIN_THREAD_TIMEOUT: float = 10.0


def run_on_main[T](func: Callable[[], T], *, block: bool = False) -> T | None:
	if wx.IsMainThread():
		return func()
	if not block:
		try:
			wx.CallAfter(func)
		except Exception:
			pass  # wx gone (NVDA shutting down): nothing to do
		return None
	done = threading.Event()
	box: dict[str, Any] = {}

	def runner() -> None:
		try:
			box["value"] = func()
		except BaseException as exc:
			box["error"] = exc
		finally:
			done.set()

	wx.CallAfter(runner)
	if not done.wait(_MAIN_THREAD_TIMEOUT):
		raise TimeoutError("timed out marshaling to NVDA's main thread")
	if "error" in box:
		raise box["error"]
	return box.get("value")
