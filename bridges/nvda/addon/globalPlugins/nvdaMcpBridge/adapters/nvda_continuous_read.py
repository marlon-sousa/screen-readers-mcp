# nvdaMcpBridge adapters -- NvdaContinuousRead: is a say all in progress?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: adapter implementing ContinuousRead: true while NVDA's say all is running.
# BUILT BY: adapters/nvda_adapter_factory.py.
# In NVDA 2026.1 SayAllHandler.isRunning() tests a weakref that outlives the read until cyclic garbage
# collection, so this reads the reader's own guard fields instead, which its stop() sets to None.
# SayAllHandler must be read from the module at call time: NVDA rebinds it during startup, and it is None
# before then.
# Runs on the server thread without run_on_main: it only reads attributes, and the settle loop polls it.

from __future__ import annotations

from logHandler import log

from ..domain.ports.continuous_read import ContinuousRead


class NvdaContinuousRead(ContinuousRead):
	def in_progress(self) -> bool:
		try:
			from speech import sayAll

			handler = sayAll.SayAllHandler
			if handler is None:
				return False
			reader = handler._getActiveSayAll()  # pyright: ignore[reportPrivateUsage]
			if reader is None:
				return False
			return getattr(reader, "reader", None) is not None or getattr(reader, "walker", None) is not None
		except Exception:
			# Never let this sink a settle; False falls back to the heuristic alone.
			log.exception("nvdaMcpBridge: could not read the reader's continuous-read state")
			return False
