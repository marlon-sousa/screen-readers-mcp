# nvdaMcpBridge domain -- the SynthSwapper port.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

from abc import ABC, abstractmethod


class SynthSwapper(ABC):
	"""Owns the silent-mode synth swap *and* the full fail-safe restoration.

	``swap_in`` installs the spy as the configured synth plus the three defence
	layers (config agreement, the ``pre_configSave`` guard, the
	``getSynthInstance`` patch). ``restore`` reverses all of it and MUST be safe
	on every teardown path -- idempotent, never raising past a best-effort
	attempt to put the user's real synth back. In live mode the factory supplies
	a no-op swapper so the session's teardown stays uniform.
	"""

	@property
	@abstractmethod
	def real_synth_name(self) -> str: ...

	@property
	@abstractmethod
	def swapped(self) -> bool: ...

	@abstractmethod
	def swap_in(self) -> None: ...

	@abstractmethod
	def restore(self) -> None: ...
