# nvdaMcpBridge adapters -- NvdaContinuousRead: is a say all in progress?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the ContinuousRead port for NVDA, whose continuous
#       read is "say all". On pyright's ignore list (imports NVDA).
# BUILT BY: adapters/nvda_adapter_factory.py, in every capture mode.
# COLLABORATORS: speech.sayAll.SayAllHandler and the reader object it holds.
#
# WHY NOT isRunning(). The obvious call is `SayAllHandler.isRunning()`, and it is
# wrong for this. It is `bool(self._getActiveSayAll())` -- a WEAKREF to the reader
# object, assigned when a read starts and never reset. So it answers "has the
# reader object been garbage-collected yet?", not "is a read in progress". And
# `_Reader` inherits `garbageHandler.TrackedObject`, whose docstring is expressly
# about objects "being deleted by Python's CYCLIC garbage collector": these
# readers sit in reference cycles as a matter of course, so they are not reclaimed
# by refcounting and the flag lags by however long collection takes.
#
# Measured, 2026-08-18: a settle built on isRunning() returned "not finished"
# indefinitely after the document ended, and after a keypress that stopped the
# read. That is worse than the bug it was fixing -- a settle that never settles --
# and it is why this file now reads a different thing.
#
# WHAT WE READ INSTEAD. Each reader nulls its OWN guard field when it stops, and
# both stop() methods begin by returning early on it:
#
#     _TextReader.stop():     self.reader = None
#     _ObjectsReader.stop():  self.walker = None
#
# That is the reader's own account of whether it is still going, and it is set on
# both routes out: normal completion (finish() queues a stop callback) and
# interruption (inputCore calls SayAllHandler.stop()). Private attributes, which
# is a cost worth naming -- but they fail CLOSED. If a future NVDA renames them,
# getattr returns None, this reports "not running", and the settle falls back to
# exactly the behaviour it had before this port existed. A rename cannot produce
# the hang; only the old imprecision.
#
# TWO TRAPS, both of which fail silently and are the reason this file has a test.
#
# 1. `SayAllHandler` is a MODULE-LEVEL NAME THAT GETS REBOUND. It starts as None
#    and NVDA's sayAll.initialize() replaces the module attribute during startup.
#    `from speech.sayAll import SayAllHandler` therefore captures None forever,
#    and the check never fires -- no error, no log, just a bridge that quietly
#    went back to guessing. The module is imported and the attribute read at CALL
#    time, and that is not a style preference.
# 2. It is None before initialize() runs, which is a real window: the add-on's
#    global plugin is constructed during NVDA startup. Hence the guard.
#
# THREADING. This runs on the bridge's server thread, not NVDA's main thread, and
# deliberately does not marshal through run_on_main. It is a weakref dereference
# behind an attribute read -- no NVDA API call, no COM, no wx -- and the settle
# loop evaluates it every POLL_INTERVAL, so marshalling each poll onto the main
# thread would cost far more than the read and would put the bridge's waiting in
# the path of the very work it is waiting for. A stale answer is harmless here:
# the next poll is 30ms away.

from __future__ import annotations

from logHandler import log

from ..domain.ports.continuous_read import ContinuousRead


class NvdaContinuousRead(ContinuousRead):
	"""True while NVDA's say all is running, including between its chunks."""

	def in_progress(self) -> bool:
		try:
			from speech import sayAll

			handler = sayAll.SayAllHandler
			if handler is None:
				# Before sayAll.initialize(); no read can be in progress yet.
				return False
			reader = handler._getActiveSayAll()  # pyright: ignore[reportPrivateUsage]
			if reader is None:
				return False
			# Alive is not running: the weakref outlives the read. Ask the reader
			# whether it stopped itself, by the field its own stop() guards on.
			return getattr(reader, "reader", None) is not None or getattr(reader, "walker", None) is not None
		except Exception:
			# Never let this sink a settle. Falling back to False restores the
			# pre-11.21 behaviour -- the heuristic alone -- which is wrong in one
			# direction rather than broken in both.
			log.exception("nvdaMcpBridge: could not read the reader's continuous-read state")
			return False
