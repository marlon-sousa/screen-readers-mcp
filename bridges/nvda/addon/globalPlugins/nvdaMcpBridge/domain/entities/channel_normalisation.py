# nvdaMcpBridge domain -- the admitted channel-shift settings.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: entity, the set of settings a session may normalise, as data.
# USED BY: the HelloHandler, which applies it through the ConfigAccessor.
# A setting is admitted only if changing it moves information between channels without adding or removing any.

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class AdmittedSetting:
	key_path: tuple[str, ...]
	value: Any
	why: str


# NVDA 2026.1 plays a wave file for a browse/focus mode change unless this key is off, and then speaks it.
ADMITTED_SETTINGS: tuple[AdmittedSetting, ...] = (
	AdmittedSetting(
		key_path=("virtualBuffers", "passThroughAudioIndication"),
		value=False,
		why="browse/focus mode changes are a wave file by default",
	),
)
