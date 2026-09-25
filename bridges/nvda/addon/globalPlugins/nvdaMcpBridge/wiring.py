# nvdaMcpBridge -- wiring.py: the composition root.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: the composition root; stacks the pure adapters and hands the Session its ports, and must not import
# NVDA, so pyright type-checks the whole graph.
# USED BY: plugin.py, once per accepted connection.

from __future__ import annotations

from typing import TYPE_CHECKING

from .adapters.file_transcript import create_session_log
from .adapters.json_lines_channel import JsonLinesChannel
from .adapters.real_clock import RealClock
from .domain.controllers.commands.registry import build_command_registry
from .domain.controllers.session import Session, SessionConfig
from .domain.entities.silence_cap import ATTENDED_DEFAULT, SilenceCapPolicy

if TYPE_CHECKING:
	import os

	from .adapters.ports.transport import Transport
	from .domain.ports.adapter_factory import AdapterFactory
	from .domain.ports.announcer import Announcer
	from .domain.ports.gesture_resolver import GestureResolver
	from .domain.ports.log_capture import LogCapture
	from .domain.ports.session_signals import SessionSignals
	from .domain.ports.user_prompter import UserPrompter


def build_session(
	transport: Transport,
	factory: AdapterFactory,
	logs_dir: str | os.PathLike[str],
	nvda_version: str,
	signals: SessionSignals,
	announcer: Announcer,
	log_capture: LogCapture,
	user_prompter: UserPrompter,
	gesture_resolver: GestureResolver,
	*,
	bridge_version: str = "unknown",
	heartbeat_timeout: float = 30.0,
	inactivity_timeout: float = 120.0,
	silence_cap: SilenceCapPolicy | None = None,
	attended: bool = True,
) -> Session:
	transcript = create_session_log(logs_dir)
	channel = JsonLinesChannel(transport)
	clock = RealClock()
	registry = build_command_registry(factory, nvda_version, bridge_version)
	config = SessionConfig(
		nvda_version=nvda_version,
		heartbeat_timeout=heartbeat_timeout,
		inactivity_timeout=inactivity_timeout,
		# None means capped on the shipped thresholds: an unconfigured machine is not assumed empty.
		silence_cap=silence_cap if silence_cap is not None else ATTENDED_DEFAULT,
		attended=attended,
	)
	return Session(
		channel,
		transcript,
		clock,
		config,
		registry,
		signals,
		announcer,
		log_capture,
		user_prompter,
		gesture_resolver,
	)
