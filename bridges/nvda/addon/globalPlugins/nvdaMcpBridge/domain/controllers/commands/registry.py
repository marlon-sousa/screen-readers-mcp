# nvdaMcpBridge domain -- the command registry: the explicit command -> handler map.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: the composition point for command handlers -- a hand-written map, read
# top to bottom, of every wire command to the one handler that serves it. This is
# deliberately NOT a DI container and NOT reflection/decorator auto-registration
# (AGENTS.md, Decided): the graph is visible here, and a compile-time wiring
# mistake is a pyright error, not a runtime surprise inside NVDA.
# BUILT BY: wiring.py in production (session C); the test builder in unit tests.
# USED BY: the Session, which only ever looks a command up and calls execute.
#
# Handlers are stateless singletons: the per-session state lives in the
# SessionContext handed to execute, so one map serves every session. hello is the
# exception -- it needs the AdapterFactory and NVDA version to build a session --
# so those are this builder's only parameters.

from __future__ import annotations

from typing import TYPE_CHECKING

from .... import protocol
from .announce import AnnounceHandler
from .ask_user import AskUserHandler
from .bye import ByeHandler
from .command_handler import CommandHandler
from .echo import EchoHandler
from .get_braille import GetBrailleHandler
from .get_config import GetConfigHandler
from .get_focus_info import GetFocusInfoHandler
from .get_guidance import GetGuidanceHandler
from .get_last_speech import GetLastSpeechHandler
from .get_log import GetLogHandler
from .get_log_position import GetLogPositionHandler
from .get_next_speech_index import GetNextSpeechIndexHandler
from .get_speech import GetSpeechHandler
from .get_state import GetStateHandler
from .hello import HelloHandler
from .ping import PingHandler
from .press_gesture import PressGestureHandler
from .set_config import SetConfigHandler
from .set_log_level import SetLogLevelHandler
from .type_text import TypeTextHandler
from .wait_for_log import WaitForLogHandler
from .wait_for_speech import WaitForSpeechHandler
from .wait_for_speech_to_finish import WaitForSpeechToFinishHandler
from .wait_for_user_reply import WaitForUserReplyHandler

if TYPE_CHECKING:
	from ...ports.adapter_factory import AdapterFactory

#: The command groups the NVDA bridge serves (spec 0007). All ten groups are
#: live: interact (announce, askUser, waitForUserReply), speech, braille,
#: gestures, focus, state, config, typing, log, and guidance.
NVDA_CAPABILITIES: tuple[protocol.Capability, ...] = (
	protocol.Capability.SPEECH,
	protocol.Capability.BRAILLE,
	protocol.Capability.GESTURES,
	protocol.Capability.FOCUS,
	protocol.Capability.STATE,
	protocol.Capability.CONFIG,
	protocol.Capability.INTERACT,
	protocol.Capability.TYPING,
	protocol.Capability.LOG,
	# Spec 0029: this bridge has written guidance for a persona on NVDA. The
	# first capability that gates a RESOURCE rather than a tool -- a bridge with
	# no reader-specific instruction to give simply leaves it out, and the agent
	# falls back on the server's reader-agnostic documents.
	protocol.Capability.GUIDANCE,
)


def build_command_registry(
	factory: AdapterFactory, nvda_version: str, bridge_version: str = "unknown"
) -> dict[str, CommandHandler]:
	"""Construct the command -> handler map for a bridge (one per process).

	This is the NVDA bridge, so it stamps its reader identity here: name
	``"nvda"``, the version wiring passed, and the capabilities it actually
	serves (:data:`NVDA_CAPABILITIES` -- all ten groups).
	"""
	reader = protocol.ReaderInfo(name="nvda", version=nvda_version)
	capabilities = list(NVDA_CAPABILITIES)
	registry: dict[str, CommandHandler] = {
		protocol.Command.HELLO: HelloHandler(factory, reader, capabilities, bridge_version),
		protocol.Command.BYE: ByeHandler(),
		protocol.Command.PING: PingHandler(),
		protocol.Command.ECHO: EchoHandler(),
		protocol.Command.PRESS_GESTURE: PressGestureHandler(),
		protocol.Command.TYPE_TEXT: TypeTextHandler(),
		protocol.Command.GET_SPEECH: GetSpeechHandler(),
		protocol.Command.GET_LAST_SPEECH: GetLastSpeechHandler(),
		protocol.Command.GET_NEXT_SPEECH_INDEX: GetNextSpeechIndexHandler(),
		protocol.Command.WAIT_FOR_SPEECH: WaitForSpeechHandler(),
		protocol.Command.WAIT_FOR_SPEECH_TO_FINISH: WaitForSpeechToFinishHandler(),
		protocol.Command.GET_BRAILLE: GetBrailleHandler(),
		protocol.Command.ANNOUNCE: AnnounceHandler(),
		protocol.Command.ASK_USER: AskUserHandler(),
		protocol.Command.WAIT_FOR_USER_REPLY: WaitForUserReplyHandler(),
		protocol.Command.GET_FOCUS_INFO: GetFocusInfoHandler(),
		protocol.Command.GET_STATE: GetStateHandler(),
		protocol.Command.GET_CONFIG: GetConfigHandler(),
		protocol.Command.SET_CONFIG: SetConfigHandler(),
		protocol.Command.GET_LOG: GetLogHandler(),
		protocol.Command.GET_LOG_POSITION: GetLogPositionHandler(),
		protocol.Command.WAIT_FOR_LOG: WaitForLogHandler(),
		protocol.Command.SET_LOG_LEVEL: SetLogLevelHandler(),
		protocol.Command.GET_GUIDANCE: GetGuidanceHandler(),
	}
	return registry
