# nvdaMcpBridge adapters -- NvdaContinuousRead: is a say all in progress?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the ContinuousRead port for NVDA, whose continuous
#       read is "say all". On pyright's ignore list (imports NVDA).
# BUILT BY: adapters/nvda_adapter_factory.py, in every capture mode.
# COLLABORATORS: speech.sayAll.SayAllHandler.isRunning(), which NVDA itself
#                consults in five places (browseMode, inputCore, NVDAHelper,
#                NVDAObjects/UIA and speech.speak) -- a load-bearing public API,
#                not an internal we are reaching into.
#
# WHY isRunning IS THE RIGHT SIGNAL. It is `bool(self._getActiveSayAll())`, a
# weakref to the reader object driving the read. That object is alive for the
# WHOLE run, including while it sits waiting for the synth to report it reached
# the previous chunk, and it dies only when finish() runs. So it is True across
# exactly the gap the buffer's elapsed-time heuristic misreads as silence:
#
#     say all is done              -> no speech arriving, isRunning False
#     say all is between chunks    -> no speech arriving, isRunning TRUE
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
			return bool(handler.isRunning())
		except Exception:
			# Never let this sink a settle. Falling back to False restores the
			# pre-11.21 behaviour -- the heuristic alone -- which is wrong in one
			# direction rather than broken in both.
			log.exception("nvdaMcpBridge: could not read the reader's say-all state")
			return False
