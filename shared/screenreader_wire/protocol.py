# nvda-mcp shared wire protocol.
# Copyright (C) 2026 Marlon Brandao de Sousa.
# This file is covered by the GNU General Public License.
# See the file COPYING.txt for more details.
#
# Canonical source, copied verbatim into the NVDA addon, where it shares ``sys.modules`` with every
# other addon: it must stay stdlib-only and have no import side effects.

from __future__ import annotations

import dataclasses
import enum
import json
from collections.abc import Mapping
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, Final, TypeVar, Union, cast, get_args, get_origin, get_type_hints

_T = TypeVar("_T")


def _empty_dict() -> dict[str, Any]:
	return {}


def _empty_str_list() -> list[str]:
	return []


__all__ = [
	"COMMAND_SHAPES",
	"DEFAULT_GRACE_MS",
	"DEFAULT_PIPE_NAME",
	"DEFAULT_PORT",
	"DEFAULT_TYPE_GRACE_MS",
	"PROTOCOL_VERSION",
	"AckResult",
	"AnnounceParams",
	"AskUserParams",
	"AskUserResult",
	"BrailleResult",
	"BrowseMode",
	"Capability",
	"CaptureMode",
	"Command",
	"CommandShape",
	"ConfigResult",
	"DocumentSnapshotParams",
	"DocumentSnapshotResult",
	"EchoParams",
	"EchoResult",
	"ErrorInfo",
	"FocusInfoResult",
	"GesturePress",
	"GestureResult",
	"GetBrailleParams",
	"GetConfigParams",
	"GetGuidanceResult",
	"GetLogParams",
	"GetSpeechParams",
	"HelloParams",
	"HelloResult",
	"LastSpeechResult",
	"LogLevel",
	"LogLevelResult",
	"LogSliceResult",
	"NextIndexResult",
	"NormalizedSetting",
	"PingResult",
	"PressGestureParams",
	"ReaderInfo",
	"Request",
	"Response",
	"SetConfigParams",
	"SetLogLevelParams",
	"SetStateParams",
	"SetStateResult",
	"SilenceCapInfo",
	"SnapshotLine",
	"SpeechResult",
	"StateResult",
	"TruncatedBy",
	"TypeParams",
	"TypeResult",
	"ValidationError",
	"WaitForSpeechParams",
	"WaitForSpeechResult",
	"WaitForUserReplyParams",
	"WaitForUserReplyResult",
	"WaitToFinishParams",
	"WaitToFinishResult",
	"decode_message",
	"encode_message",
	"from_dict",
	"to_dict",
]


#: Bumped on any incompatible wire change; ``hello`` rejects a mismatched pair.
PROTOCOL_VERSION: Final = 1

DEFAULT_PORT: Final = 8765

#: Local-machine-only: PIPE_REJECT_REMOTE_CLIENTS plus an owner-only DACL on the listener.
DEFAULT_PIPE_NAME: Final = r"\\.\pipe\nvdaMcpBridge"


class CaptureMode(StrEnum):
	#: Speech is captured before the synth; the user hears nothing and the real synth stays loaded.
	SILENT = "silent"
	#: Hook ``pre_speechQueued``; the real synth keeps talking.
	LIVE = "live"


class LogLevel(StrEnum):
	"""NVDA's logging levels minus OFF; requesting one raises NVDA's own verbosity until teardown."""

	DEBUG = "debug"
	IO = "io"
	DEBUGWARNING = "debugwarning"
	INFO = "info"
	WARNING = "warning"
	ERROR = "error"


class Capability(StrEnum):
	"""What a bridge can do, announced in ``hello``; a consumer must ignore an unknown capability."""

	SPEECH = "speech"
	BRAILLE = "braille"
	GESTURES = "gestures"
	FOCUS = "focus"
	STATE = "state"
	CONFIG = "config"
	INTERACT = "interact"
	TYPING = "typing"
	LOG = "log"
	#: Gates the bridge's reader-specific guidance; omitted when it has nothing reader-specific to say.
	GUIDANCE = "guidance"
	#: The reader can hand over its flat browse-mode text buffer whole; gates ``getDocumentSnapshot``.
	DOCUMENT = "document"


class BrowseMode(StrEnum):
	"""Whether the focus is in a browsable document, and which mode; ``"none"`` means no document."""

	BROWSE = "browse"
	FOCUS = "focus"
	NONE = "none"


class TruncatedBy(StrEnum):
	"""Why a document snapshot stopped; ``NONE`` also when the document ended exactly on a bound."""

	NONE = "none"
	MAX_LINES = "maxLines"
	MAX_CHARS = "maxChars"


class Command(StrEnum):
	HELLO = "hello"
	PING = "ping"
	ECHO = "echo"
	PRESS_GESTURE = "pressGesture"
	TYPE_TEXT = "typeText"
	GET_SPEECH = "getSpeech"
	GET_LAST_SPEECH = "getLastSpeech"
	GET_NEXT_SPEECH_INDEX = "getNextSpeechIndex"
	WAIT_FOR_SPEECH = "waitForSpeech"
	WAIT_FOR_SPEECH_TO_FINISH = "waitForSpeechToFinish"
	GET_BRAILLE = "getBraille"
	GET_FOCUS_INFO = "getFocusInfo"
	GET_STATE = "getState"
	SET_STATE = "setState"
	GET_CONFIG = "getConfig"
	SET_CONFIG = "setConfig"
	ANNOUNCE = "announce"
	ASK_USER = "askUser"
	WAIT_FOR_USER_REPLY = "waitForUserReply"
	GET_LOG = "getLog"
	GET_LOG_POSITION = "getLogPosition"
	WAIT_FOR_LOG = "waitForLog"
	SET_LOG_LEVEL = "setLogLevel"
	GET_GUIDANCE = "getGuidance"
	GET_DOCUMENT_SNAPSHOT = "getDocumentSnapshot"
	BYE = "bye"


class ValidationError(ValueError):
	"""Raised by :func:`from_dict`; the message names the offending field path."""


_NONE_TYPE: Final = type(None)


def _union_args(tp: object) -> tuple[Any, ...] | None:
	origin = get_origin(tp)
	if origin is Union:
		return get_args(tp)
	if origin is not None and origin.__class__.__name__ == "UnionType":
		return get_args(tp)
	if type(tp).__name__ == "UnionType":
		return get_args(tp)
	return None


def _coerce(expected: Any, value: Any, path: str) -> Any:
	if expected is Any or expected is object:
		return value

	union = _union_args(expected)
	if union is not None:
		if value is None and _NONE_TYPE in union:
			return None
		errors: list[str] = []
		for arg in union:
			if arg is _NONE_TYPE:
				continue
			try:
				return _coerce(arg, value, path)
			except ValidationError as exc:
				errors.append(str(exc))
		raise ValidationError(f"{path}: value {value!r} matched none of {union}: {'; '.join(errors)}")

	origin = get_origin(expected)
	if origin in (list, tuple):
		if not isinstance(value, list):
			raise ValidationError(f"{path}: expected a list, got {type(value).__name__}")
		items = cast("list[Any]", value)
		(elem_type,) = get_args(expected) or (Any,)
		return [_coerce(elem_type, item, f"{path}[{i}]") for i, item in enumerate(items)]
	if origin is dict:
		if not isinstance(value, Mapping):
			raise ValidationError(f"{path}: expected an object, got {type(value).__name__}")
		mapping = cast("Mapping[Any, Any]", value)
		key_type, val_type = get_args(expected) or (Any, Any)
		return {
			_coerce(key_type, k, f"{path}.<key>"): _coerce(val_type, v, f"{path}.{k}")
			for k, v in mapping.items()
		}

	if isinstance(expected, type) and dataclasses.is_dataclass(expected):
		if not isinstance(value, Mapping):
			raise ValidationError(f"{path}: expected an object, got {type(value).__name__}")
		nested = cast("Mapping[str, Any]", value)
		return from_dict(expected, nested)

	if isinstance(expected, type) and issubclass(expected, enum.Enum):
		try:
			return expected(value)
		except ValueError as exc:
			raise ValidationError(f"{path}: {value!r} is not a valid {expected.__name__}") from exc

	# bool is an int subclass; keep them distinct so a stray ``true`` is never read as ``1``.
	if expected is bool:
		if isinstance(value, bool):
			return value
		raise ValidationError(f"{path}: expected bool, got {type(value).__name__}")
	if expected is int:
		if isinstance(value, bool) or not isinstance(value, int):
			raise ValidationError(f"{path}: expected int, got {type(value).__name__}")
		return value
	if expected is float:
		if isinstance(value, bool) or not isinstance(value, (int, float)):
			raise ValidationError(f"{path}: expected number, got {type(value).__name__}")
		return float(value)
	if expected is str:
		if not isinstance(value, str):
			raise ValidationError(f"{path}: expected str, got {type(value).__name__}")
		return value

	if isinstance(expected, type):
		if isinstance(value, expected):
			return value
		raise ValidationError(f"{path}: expected {expected.__name__}, got {type(value).__name__}")

	# Unknown typing construct: accept rather than reject.
	return value


def from_dict(cls: type[_T], data: Mapping[str, Any]) -> _T:
	"""Build a ``cls`` instance from ``data``, validating types; extra keys are ignored."""
	if not dataclasses.is_dataclass(cls):
		raise ValidationError(f"{getattr(cls, '__name__', cls)!r} is not a dataclass")

	hints = get_type_hints(cls)
	kwargs: dict[str, Any] = {}
	for f in dataclasses.fields(cls):
		if f.name not in data:
			has_default = f.default is not dataclasses.MISSING or f.default_factory is not dataclasses.MISSING
			if has_default:
				continue
			raise ValidationError(f"{cls.__name__}: missing required field {f.name!r}")
		kwargs[f.name] = _coerce(hints[f.name], data[f.name], f"{cls.__name__}.{f.name}")
	return cls(**kwargs)


def to_dict(obj: Any) -> dict[str, Any]:
	if not dataclasses.is_dataclass(obj) or isinstance(obj, type):
		raise ValidationError(f"to_dict expects a dataclass instance, got {type(obj).__name__}")
	return dataclasses.asdict(obj)


def encode_message(obj: Any) -> bytes:
	"""Encode a dataclass (or plain dict) as one UTF-8 JSON line (``\\n``)."""
	payload: Any = to_dict(obj) if dataclasses.is_dataclass(obj) and not isinstance(obj, type) else obj
	return (json.dumps(payload, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def decode_message(line: bytes | str) -> dict[str, Any]:
	text = line.decode("utf-8") if isinstance(line, bytes) else line
	try:
		parsed: Any = json.loads(text)
	except (ValueError, UnicodeDecodeError) as exc:
		raise ValidationError(f"malformed JSON line: {exc}") from exc
	if not isinstance(parsed, dict):
		raise ValidationError(f"expected a JSON object, got {type(parsed).__name__}")
	return cast("dict[str, Any]", parsed)


@dataclass
class Request:
	id: int
	cmd: str
	params: dict[str, Any] = field(default_factory=_empty_dict)


@dataclass
class ErrorInfo:
	message: str


@dataclass
class Response:
	"""A bridge→client reply frame. Exactly one of ``result``/``error`` is set."""

	id: int
	result: Any = None
	error: ErrorInfo | None = None


@dataclass
class HelloParams:
	mode: CaptureMode
	protocolVersion: int
	#: Unset leaves NVDA's current level alone; capture happens either way.
	logLevel: LogLevel | None = None
	#: Moves reader signals a session cannot hear into a channel it can, adding and removing nothing.
	#: ``None`` means the mode's default (silent normalises, live does not); changed keys come back in
	#: :attr:`HelloResult.normalized` and are restored at teardown.
	normalize: bool | None = None
	#: A plain ``str``, not an enum: an unknown persona must degrade, never fail the handshake.
	persona: str = ""


@dataclass(frozen=True)
class ReaderInfo:
	name: str
	version: str


@dataclass(frozen=True)
class SilenceCapInfo:
	"""Whether this reader bounds how long a silent session may keep the human mute; set only there."""

	#: False on a machine its owner declared unattended.
	enabled: bool
	#: Seconds of no audible event before the reader warns its human.
	warnAfterSeconds: float
	#: Seconds before the reader stops suppressing; capture is unaffected.
	liftAfterSeconds: float


@dataclass(frozen=True)
class NormalizedSetting:
	"""One reader setting this session moved between output channels; ``why`` is fixed, untranslated."""

	keyPath: list[str]
	previous: Any
	current: Any
	why: str


def _no_normalized() -> list[NormalizedSetting]:
	return []


@dataclass
class HelloResult:
	protocolVersion: int
	reader: ReaderInfo
	capabilities: list[Capability]
	mode: CaptureMode
	synth: str
	#: The bridge's session transcript on the reader's disk; a convenience, not a contract.
	logPath: str
	#: The add-on's own version, not the reader's; "unknown" when the bridge cannot determine it.
	bridgeVersion: str = "unknown"
	#: The reader's guidance for the declared persona, as ``getGuidance`` answers it; ``None`` means
	#: this bridge publishes none.
	guidance: GetGuidanceResult | None = None
	#: Whether this machine bounds the silence; ``None`` means this bridge does not say.
	silenceCap: SilenceCapInfo | None = None
	#: Whether a human is expected at the reader's machine, as its owner declared; ``None`` means this
	#: bridge does not say. A consumer that receives the field must not infer it from ``silenceCap``.
	attended: bool | None = None
	#: Every setting this session actually changed; empty means the user's own configuration.
	normalized: list[NormalizedSetting] = field(default_factory=_no_normalized)


@dataclass
class EchoParams:
	payload: Any


@dataclass
class EchoResult:
	payload: Any


#: Grace a mutating command waits, in ms, for the speech it caused; NVDA 2026.1 finishes a
#: keystroke's speech about 124 ms after the gesture.
DEFAULT_GRACE_MS: int = 100

#: ``typeText``'s default: with "speak typed characters" on, no per-character utterance is worth a wait.
DEFAULT_TYPE_GRACE_MS: int = 0


@dataclass
class PressGestureParams:
	#: NVDA gesture ids, pressed in order, blocking until each is processed.
	gestures: list[str]
	#: Milliseconds to wait after each gesture for the speech it caused; ``0`` opts out.
	graceMs: int = DEFAULT_GRACE_MS
	#: Spoken to the human before the first gesture, audible even in a silent session; empty says nothing.
	announce: str = ""


@dataclass
class TypeParams:
	"""Literal text to insert into whatever holds system focus; control characters are not interpreted."""

	text: str
	#: Defaults to 0; see :data:`DEFAULT_TYPE_GRACE_MS`.
	graceMs: int = DEFAULT_TYPE_GRACE_MS
	announce: str = ""


@dataclass
class GetSpeechParams:
	sinceIndex: int


@dataclass
class SpeechEntry:
	"""One captured utterance, placed on the log journal's timeline.

	In a silent session the journal holds no speech record, so ``logPosition`` is the only link.
	"""

	text: str
	index: int
	logPosition: int
	#: Wall clock when the reader emitted this, not when it was heard, as ``YYYY-MM-DD HH:MM:SS.mmm``.
	emittedAt: str = ""


@dataclass
class SpeechResult:
	#: Oldest first; empty entries are omitted, so ``len(entries)`` is not ``toIndex - fromIndex``.
	entries: list[SpeechEntry]
	fromIndex: int
	toIndex: int


@dataclass
class LastSpeechResult:
	text: str
	index: int
	#: The journal position when this was captured; 0 for the empty sentinel.
	logPosition: int = 0
	#: Wall clock when emitted; empty for the sentinel.
	emittedAt: str = ""


@dataclass
class NextIndexResult:
	index: int


@dataclass
class WaitForSpeechParams:
	text: str
	afterIndex: int | None = None
	timeout: float = 5.0


@dataclass
class WaitForSpeechResult:
	found: bool
	#: Index of the matching sequence, or the next index if not found.
	index: int
	text: str
	#: Journal position of the match; on a miss, the current position.
	logPosition: int = 0
	#: Wall clock of the match; empty on a miss.
	emittedAt: str = ""


@dataclass
class WaitToFinishParams:
	timeout: float = 5.0


@dataclass
class WaitToFinishResult:
	finished: bool


@dataclass
class GetBrailleParams:
	sinceIndex: int


@dataclass
class BrailleEntry:
	"""One braille update, placed on the log journal's timeline; see :class:`SpeechEntry`."""

	text: str
	index: int
	logPosition: int
	#: Wall clock when the reader emitted this update; see :class:`SpeechEntry`.
	emittedAt: str = ""


@dataclass
class BrailleResult:
	#: Oldest first; consecutive identical writes are already dropped.
	entries: list[BrailleEntry]
	fromIndex: int
	toIndex: int


@dataclass
class FocusInfoResult:
	name: str
	role: str
	states: list[str]
	value: str | None
	appModule: str | None


@dataclass
class StateResult:
	#: ``NONE`` when there is no browse document.
	browseMode: BrowseMode
	#: ``"talk"`` / ``"beeps"`` / ``"off"`` / ``"onDemand"``.
	speechMode: str
	sleepMode: bool
	inputHelp: bool


@dataclass
class SetStateParams:
	"""Which modes to arrive at; every field optional.

	``"none"`` is readable but not settable, and ``speechMode``, ``sleepMode`` and ``inputHelp`` are
	refused by name: the first two can leave a human unable to hear, the last disarms every gesture.
	"""

	browseMode: BrowseMode | None = None


@dataclass
class SetStateResult:
	"""The state after the write; ``changed`` names the fields moved, empty when already there."""

	state: StateResult
	changed: list[str] = field(default_factory=_empty_str_list)


@dataclass
class GesturePress:
	"""One dispatched gesture and its half-open slice ``[speechFrom, speechTo)`` of the speech ring.

	Attribution is by dispatch-time coordinate, not causation: speech from gesture n can land after n+1.
	"""

	gesture: str
	speechFrom: int
	speechTo: int


@dataclass
class GestureResult:
	"""What ``pressGesture`` observed within its grace window; it never claims that is all there is."""

	pressed: list[GesturePress]
	#: Every non-empty utterance across the whole call, not repeated per press.
	speech: list[SpeechEntry]
	#: ``speechTo`` is the ``sinceIndex`` to pass next.
	speechFrom: int
	speechTo: int
	#: ``getState``'s fields at the close of the last grace window; ``None`` without the state capability.
	state: StateResult | None = None


@dataclass
class TypeResult:
	"""What ``typeText`` observed; ``typed`` is the length sent, never the text."""

	typed: int
	speech: list[SpeechEntry]
	speechFrom: int
	speechTo: int
	state: StateResult | None = None


@dataclass
class GetConfigParams:
	keyPath: list[str]


@dataclass
class SetConfigParams:
	keyPath: list[str]
	value: Any


@dataclass
class ConfigResult:
	value: Any


@dataclass
class AnnounceParams:
	"""Speak ``text`` to the human at the keyboard, even in silent mode, without touching the synth."""

	text: str


@dataclass
class AckResult:
	ok: bool = True


@dataclass
class PingResult:
	"""``ping``'s reply: the peer is alive, plus what it is doing to speech."""

	ok: bool = True
	#: Whether words are withheld from the human right now; ``None`` from a bridge that does not say.
	suppressing: bool | None = None


@dataclass
class AskUserParams:
	"""Present a prompt to the human and suspend speech suppression; returns a ticket at once."""

	prompt: str


@dataclass
class AskUserResult:
	ticket: str


@dataclass
class WaitForUserReplyParams:
	"""Poll for the human's answer; ``timeout`` bounds this poll, not the window's 300 s deadline."""

	ticket: str
	timeout: float = 30.0


@dataclass
class WaitForUserReplyResult:
	answered: bool
	#: Always empty while the acknowledgement is a gesture, which carries no text.
	text: str = ""


@dataclass
class GetLogParams:
	"""Parameters for ``getLog``.

	``sincePosition``, ``lastSeconds`` and ``commandId`` are mutually exclusive anchors, the last the
	default; ``windows`` alongside either of the others is rejected.
	"""

	#: Defaults to the most recently marked command.
	commandId: int | None = None
	windows: int = 1
	#: A position below the ring's oldest survivor reports ``truncated: true``.
	sincePosition: int | None = None
	lastSeconds: float | None = None
	minLevel: LogLevel | None = None
	contains: list[str] | None = None
	exclude: list[str] | None = None
	#: Which fields to render per record. Default: time, level, module, message.
	fields: list[str] | None = None
	maxEntries: int = 200


@dataclass
class SetLogLevelParams:
	level: LogLevel


@dataclass
class LogLevelResult:
	level: LogLevel
	previous: LogLevel


@dataclass
class LogSliceResult:
	text: str
	entries: int
	#: Number of records that passed the filters, before ``maxEntries``.
	matched: int
	#: True when ``matched > entries``, or the slice had aged out of the ring.
	truncated: bool
	#: Just past the last record considered; pass back as ``sincePosition`` to continue the tail.
	nextPosition: int
	#: Exact for a command anchor; for a position or time anchor, the level in force now.
	capturedAtLevel: LogLevel
	#: ``None`` when anchored by position or time.
	fromCommandId: int | None = None
	#: The farthest command id included, or ``None``, for the same reason.
	toCommandId: int | None = None


@dataclass
class LogPositionResult:
	position: int
	time: str


@dataclass
class WaitForLogParams:
	timeout: float = 5.0
	minLevel: LogLevel | None = None
	contains: list[str] | None = None


@dataclass
class GetGuidanceResult:
	"""The bridge's guidance for the session's persona, as markdown the server never parses."""

	#: Echoed as received, even when unrecognised.
	persona: str
	#: ``False`` with the general text when the bridge has nothing for that persona.
	recognised: bool
	text: str


@dataclass
class DocumentSnapshotParams:
	"""How much of the browse document to render; no fields means the whole document.

	Two bounded calls are two moments, so a document that changes between them yields a stitched read.
	"""

	#: Lines keep their absolute ordinals in the result.
	fromLine: int = 0
	#: Stop after this many lines; ``0`` means no limit.
	maxLines: int = 0
	#: ``0`` means no limit; a budget smaller than the first line still returns that line.
	maxChars: int = 0


@dataclass
class SnapshotLine:
	line: int
	#: As the reader presents it, roles and states included, under the user's own verbosity.
	text: str


def _no_snapshot_lines() -> list[SnapshotLine]:
	return []


@dataclass
class DocumentSnapshotResult:
	#: ``False`` for a dialog, a native app or the desktop: other fields are empty, ``capturedAt`` is set.
	hasDocument: bool
	#: Wall clock at the read, in ``emittedAt``'s format.
	capturedAt: str
	#: The document's own title, best-effort; empty when it has none.
	title: str = ""
	lines: list[SnapshotLine] = field(default_factory=_no_snapshot_lines)
	fromLine: int = 0
	toLine: int = 0
	truncatedBy: TruncatedBy = TruncatedBy.NONE


@dataclass
class WaitForLogResult:
	"""Whether a matching record appeared, and where; a miss is ``found: false``, not an error."""

	found: bool
	#: Where the match landed; on a miss, the journal's current position.
	position: int
	#: The matching record, formatted; empty when not found.
	text: str = ""


@dataclass(frozen=True)
class CommandShape:
	"""The payload types for one wire command; ``params`` is ``None`` when it carries none."""

	params: type | None
	result: type


#: Every wire command's param and result types; the JSON Schema is generated from this.
COMMAND_SHAPES: Final[Mapping[Command, CommandShape]] = {
	Command.HELLO: CommandShape(HelloParams, HelloResult),
	Command.PING: CommandShape(None, PingResult),
	Command.ECHO: CommandShape(EchoParams, EchoResult),
	Command.PRESS_GESTURE: CommandShape(PressGestureParams, GestureResult),
	Command.TYPE_TEXT: CommandShape(TypeParams, TypeResult),
	Command.GET_SPEECH: CommandShape(GetSpeechParams, SpeechResult),
	Command.GET_LAST_SPEECH: CommandShape(None, LastSpeechResult),
	Command.GET_NEXT_SPEECH_INDEX: CommandShape(None, NextIndexResult),
	Command.WAIT_FOR_SPEECH: CommandShape(WaitForSpeechParams, WaitForSpeechResult),
	Command.WAIT_FOR_SPEECH_TO_FINISH: CommandShape(WaitToFinishParams, WaitToFinishResult),
	Command.GET_BRAILLE: CommandShape(GetBrailleParams, BrailleResult),
	Command.GET_FOCUS_INFO: CommandShape(None, FocusInfoResult),
	Command.GET_STATE: CommandShape(None, StateResult),
	Command.SET_STATE: CommandShape(SetStateParams, SetStateResult),
	Command.GET_CONFIG: CommandShape(GetConfigParams, ConfigResult),
	Command.SET_CONFIG: CommandShape(SetConfigParams, ConfigResult),
	Command.ANNOUNCE: CommandShape(AnnounceParams, AckResult),
	Command.ASK_USER: CommandShape(AskUserParams, AskUserResult),
	Command.WAIT_FOR_USER_REPLY: CommandShape(WaitForUserReplyParams, WaitForUserReplyResult),
	Command.GET_LOG: CommandShape(GetLogParams, LogSliceResult),
	Command.GET_LOG_POSITION: CommandShape(None, LogPositionResult),
	Command.WAIT_FOR_LOG: CommandShape(WaitForLogParams, WaitForLogResult),
	Command.SET_LOG_LEVEL: CommandShape(SetLogLevelParams, LogLevelResult),
	Command.GET_GUIDANCE: CommandShape(None, GetGuidanceResult),
	Command.GET_DOCUMENT_SNAPSHOT: CommandShape(DocumentSnapshotParams, DocumentSnapshotResult),
	Command.BYE: CommandShape(None, AckResult),
}
