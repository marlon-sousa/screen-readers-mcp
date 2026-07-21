# nvdaMcpBridge adapters -- NvdaSynthSwapper: the silent-mode synth swap + restore.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: adapter. IMPLEMENTS the SynthSwapper port -- the whole Decided fail-safe
#       defence of RFC 0001 (spec 0007). On pyright's ignore list (imports NVDA);
#       validated by the 9c live-NVDA checklist (fail-safe items 2-3, 6).
# BUILT BY: adapters/nvda_adapter_factory.py.
# USED BY: the Session, which calls restore() in a finally on EVERY teardown path.
#
# The invariant this file exists to keep (AGENTS.md #3): a crashed harness must
# never leave a blind user mute. So restore() is idempotent and unconditional.
#
# THREAD AFFINITY -- learned from a live-NVDA finding (9c). NVDA loads/unloads
# synths on its MAIN thread; the Session runs on the bridge's server thread. If
# we call setSynth from the server thread while NVDA handles a config-profile
# switch on the main thread (app profiles switch on focus change -- frequent),
# the two race and NVDA is left holding a dead synth: MUTE, even though the
# config name is correct. So every NVDA mutation here runs on the main thread,
# the same way NvdaGestureSender marshals gesture injection:
#   * swap_to_spy is BLOCKING (hello must know NVDA went silent before capture
#     starts, so there is no audio blip); it is only ever called from the server
#     thread with the main thread free, so it cannot deadlock.
#   * restore is FIRE-AND-FORGET (CallAfter, no wait). It must be safe from every
#     teardown trigger -- including panic/terminate, which run ON the main thread
#     and join the server thread -- and a blocking marshal there would deadlock
#     (main waits for server, server waits for main). Fire-and-forget means the
#     server thread never waits on the main thread, and the restore still runs on
#     the main thread, serialized with NVDA's own profile-switch synth handling.
#
# Why three layers, not just setSynth (learned from reading 2026.1 source):
# synthDriverHandler reloads config["speech"]["synth"] on every
# post_configProfileSwitch, and profile switches are frequent. So swapping alone
# (isFallback=True, which leaves config naming the real synth) is self-defeating:
# the first profile switch reconciles config against the loaded synth and rips
# the spy out. Instead, for the session only:
#   1. make config name the spy, so the reconciliation is a no-op;
#   2. guard config SAVE (pre -> real name on disk, post -> spy back in memory),
#      so the spy never persists past the session;
#   3. patch getSynthInstance, so a profile that stores a different synth still
#      loads the spy -- capture survives with no audio blip.
# restore() reverses all three, in the reverse order, and is safe if nothing was
# ever swapped.

from __future__ import annotations

import threading
from typing import Any, Callable, TypeVar

import config
import synthDriverHandler
import wx

from ..domain.ports.synth_swapper import SynthSwapper
from . import spy_sink

_T = TypeVar("_T")

#: How long a blocking marshal to the main thread waits before giving up. Only
#: the reads/swap block, and only when the main thread is momentarily busy.
_MAIN_THREAD_TIMEOUT: float = 10.0


def _run_on_main(func: Callable[[], _T], *, block: bool) -> _T | None:
	"""Run ``func`` on NVDA's wx main thread and return its result.

	Already on the main thread: run inline. Otherwise ``CallAfter`` it -- blocking
	on completion when ``block`` (reads and swap, which need the result / ordering),
	or fire-and-forget when not (restore, so a main-thread teardown trigger like
	panic/terminate cannot deadlock). Because CallAfter is FIFO, a blocking read
	queued after a fire-and-forget restore still observes the post-restore state.
	"""
	if wx.IsMainThread():
		return func()
	if not block:
		try:
			wx.CallAfter(func)
		except Exception:
			# wx is gone (NVDA shutting down): the on-disk config already names
			# the real synth, so the next start is correct regardless.
			pass
		return None
	done = threading.Event()
	box: dict[str, Any] = {}

	def runner() -> None:
		try:
			box["value"] = func()
		except BaseException as exc:  # surfaced to the caller below
			box["error"] = exc
		finally:
			done.set()

	wx.CallAfter(runner)
	if not done.wait(_MAIN_THREAD_TIMEOUT):
		raise TimeoutError("timed out marshaling to NVDA's main thread")
	if "error" in box:
		raise box["error"]
	return box.get("value")


class NvdaSynthSwapper(SynthSwapper):
	"""Installs the spy synth for a silent session and always restores the user's."""

	def __init__(self) -> None:
		self._real_synth: str | None = None
		self._orig_get_synth_instance: Callable[..., Any] | None = None

	def current_synth(self) -> str:
		# Marshalled (blocking) so it reads NVDA's synth on the main thread and,
		# via CallAfter's FIFO order, observes any just-scheduled restore first.
		return _run_on_main(self._current_synth_body, block=True) or ""

	@staticmethod
	def _current_synth_body() -> str:
		synth = synthDriverHandler.getSynth()
		return synth.name if synth is not None else ""

	def swap_to_spy(self) -> str:
		real = self.current_synth()
		self._real_synth = real
		_run_on_main(self._swap_body, block=True)
		return real

	def restore(self) -> None:
		# Fire-and-forget onto the main thread; the body's own guard makes it a
		# no-op if nothing was swapped, so double calls are harmless.
		_run_on_main(self._restore_body, block=False)

	# -- bodies (always run on the main thread) ------------------------------

	def _swap_body(self) -> None:
		# Layer 3 first: patch getSynthInstance BEFORE setSynth, so the load below
		# (and any concurrent profile switch) already resolves to the spy.
		self._orig_get_synth_instance = synthDriverHandler.getSynthInstance
		synthDriverHandler.getSynthInstance = self._patched_get_synth_instance

		# Layer 1: make NVDA load the spy and make config agree, so a later
		# post_configProfileSwitch reconciliation is a no-op rather than a teardown.
		synthDriverHandler.setSynth(spy_sink.SPY_SYNTH_NAME)
		config.conf["speech"]["synth"] = spy_sink.SPY_SYNTH_NAME

		# Layer 2: keep the spy out of any config the user saves mid-session.
		config.pre_configSave.register(self._on_pre_config_save)
		config.post_configSave.register(self._on_post_config_save)

	def _restore_body(self) -> None:
		if self._real_synth is None:
			return  # nothing was swapped; idempotent no-op
		real = self._real_synth
		self._real_synth = None

		config.pre_configSave.unregister(self._on_pre_config_save)
		config.post_configSave.unregister(self._on_post_config_save)

		if self._orig_get_synth_instance is not None:
			synthDriverHandler.getSynthInstance = self._orig_get_synth_instance
			self._orig_get_synth_instance = None

		config.conf["speech"]["synth"] = real
		synthDriverHandler.setSynth(real)

	# -- the guards ----------------------------------------------------------

	def _patched_get_synth_instance(self, name: str, asDefault: bool = False) -> Any:
		# Ignore the requested name: whatever NVDA tries to load, it gets the spy,
		# so a synth-changing profile cannot displace capture mid-session.
		assert self._orig_get_synth_instance is not None
		return self._orig_get_synth_instance(spy_sink.SPY_SYNTH_NAME, asDefault)

	def _on_pre_config_save(self) -> None:
		# Write the user's real synth to the file being saved...
		config.conf["speech"]["synth"] = self._real_synth

	def _on_post_config_save(self) -> None:
		# ...then put the spy back in the live config so capture continues.
		if self._real_synth is not None:
			config.conf["speech"]["synth"] = spy_sink.SPY_SYNTH_NAME
