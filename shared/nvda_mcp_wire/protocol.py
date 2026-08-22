# nvda-mcp shared wire protocol.
# Copyright (C) 2026 Marlon Brandao de Sousa.
# This file is covered by the GNU General Public License.
# See the file COPYING.txt for more details.
#
# CANONICAL SOURCE. This module is shared *verbatim* by two very different
# hosts:
#
#   * the MCP server (desktop CPython, may also depend on pydantic/mcp), and
#   * the NVDA bridge addon (NVDA's embedded CPython, no third-party deps,
#     shared ``sys.modules`` with every other installed addon).
#
# It must therefore stay **stdlib-only** and have no import side effects. The
# addon build (scons) copies this file into the addon package; the server
# depends on it as an installable package. Because both sides run the exact
# same bytes, the wire contract cannot drift. It is unit-tested once, under
# desktop Python, in ``shared/tests/test_protocol.py``.

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


# --- Constants ---------------------------------------------------------------

#: Bumped on any incompatible change to the wire contract. The ``hello``
#: handshake rejects a mismatched bridge/server pair with a clear error.
PROTOCOL_VERSION: Final = 1

#: Default loopback TCP port the bridge listens on.
DEFAULT_PORT: Final = 8765

#: Default Windows named pipe a bridge may listen on instead of (or alongside,
#: in a config-selectable future) loopback TCP -- spec 0010. Local-machine-only
#: by construction (PIPE_REJECT_REMOTE_CLIENTS + an owner-only DACL on the
#: listener side), the pipe analogue of "never bind a routable interface".
DEFAULT_PIPE_NAME: Final = r"\\.\pipe\nvdaMcpBridge"


class CaptureMode(StrEnum):
	"""Speech-capture modes, chosen per session at ``hello`` time.

	A ``StrEnum`` so members *are* ``str`` — they serialize to plain JSON and
	compare equal to their wire value — while still giving us a closed set that
	:func:`from_dict` validates (an unknown mode raises, it is not silently
	accepted).
	"""

	#: Speech is intercepted before the synth and captured there; the user hears
	#: nothing and the real synth stays loaded and active (spec 0008).
	SILENT = "silent"
	#: Hook ``pre_speechQueued``; the real synth keeps talking.
	LIVE = "live"


class LogLevel(StrEnum):
	"""NVDA logging levels a session may request via ``hello``.

	Exactly NVDA's own valid logging-level values (``logHandler.py``), minus
	``OFF`` -- disabling logging makes no sense to *request* for a debugging
	session. Requesting one temporarily raises NVDA's own log verbosity for
	the session's duration (not just the private capture file -- see
	``specs/wire/v1/protocol.md`` §3), restored at teardown.
	"""

	DEBUG = "debug"
	IO = "io"
	DEBUGWARNING = "debugwarning"
	INFO = "info"
	WARNING = "warning"
	ERROR = "error"


class Capability(StrEnum):
	"""What a connected bridge can do, announced per session in ``hello``.

	One member per command group. A bridge advertises the subset its reader
	supports — spec 0005 anticipates JAWS lacking braille, TalkBack lacking
	config — while the NVDA bridge advertises all of them. A consumer **must
	ignore an unknown capability string** (see ``specs/wire/v1/protocol.md``) so
	the set can grow without breaking an older peer. ``StrEnum`` so members are
	their own wire strings, like :class:`CaptureMode`.
	"""

	SPEECH = "speech"
	BRAILLE = "braille"
	GESTURES = "gestures"
	FOCUS = "focus"
	STATE = "state"
	CONFIG = "config"
	INTERACT = "interact"
	TYPING = "typing"
	LOG = "log"
	#: The bridge has its own written guidance for the session's persona -- what
	#: the ordinary vocabulary IS on this reader, and which of its commands fall
	#: outside it (spec 0029). The first capability that gates a RESOURCE rather
	#: than a tool, so a bridge with nothing reader-specific to say simply omits
	#: it and the agent falls back on the server's reader-agnostic documents.
	GUIDANCE = "guidance"
	#: The reader renders documents into a FLAT TEXT BUFFER the user reads with
	#: the cursor keys -- NVDA's browse mode, and whatever its analogue is
	#: elsewhere -- and can hand that rendering over whole (spec 0026). Gates
	#: ``getDocumentSnapshot``. A reader with no such notion omits it, and the
	#: agent is back to one round trip per line, which is the situation this
	#: capability exists to escape.
	DOCUMENT = "document"


class BrowseMode(StrEnum):
	"""Whether the focus is in a browsable document, and which mode it is in.

	A closed tri-state rather than a nullable bool, because ``"focus"`` and
	``"none"`` are genuinely different answers: ``"focus"`` means "inside a
	browsable document, keys go to the document"; ``"none"`` means the question
	does not arise here at all (a plain Win32 dialog). Collapsing the two to a
	falsy value would make a diff across a gesture read as a mode change when
	nothing changed -- exactly the ambiguity spec 0015 argued against.
	"""

	BROWSE = "browse"
	FOCUS = "focus"
	NONE = "none"


class TruncatedBy(StrEnum):
	"""Why a document snapshot stopped where it did (spec 0026).

	A closed tri-state for :class:`BrowseMode`'s reason: "nothing was truncated"
	IS one of the three answers, so it is a member and not a null. ``truncated:
	true`` was rejected for spec 0021's reason -- capped by line count and capped
	by character budget are different situations, and an agent that asks again
	with a bigger budget is right in one case and wrong in the other.

	``NONE`` is also the answer when a document ends exactly on a bound: the
	bound did not bite, it coincided.
	"""

	NONE = "none"
	MAX_LINES = "maxLines"
	MAX_CHARS = "maxChars"


class Command(StrEnum):
	"""Wire command names (v1).

	``StrEnum`` members double as their wire strings, so dispatch tables can be
	keyed by ``Command`` yet looked up with a raw ``str`` from the wire.
	"""

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


# --- Generic validator -------------------------------------------------------


class ValidationError(ValueError):
	"""Raised by :func:`from_dict` when a payload does not match a dataclass.

	The message names the offending field path so wire faults are diagnosable
	from a log line alone.
	"""


_NONE_TYPE: Final = type(None)


def _union_args(tp: object) -> tuple[Any, ...] | None:
	"""Return the members of ``tp`` if it is a Union / ``X | Y``, else None."""
	origin = get_origin(tp)
	# ``typing.Union[...]`` reports ``typing.Union`` as origin; the PEP 604
	# ``X | Y`` form reports ``types.UnionType``. Both expose members via
	# ``get_args``.
	if origin is Union:
		return get_args(tp)
	# ``types.UnionType`` (3.10+) is not ``typing.Union`` but ``get_origin``
	# returns it for ``int | str``.
	if origin is not None and origin.__class__.__name__ == "UnionType":
		return get_args(tp)
	if type(tp).__name__ == "UnionType":  # bare ``int | None`` value
		return get_args(tp)
	return None


def _coerce(expected: Any, value: Any, path: str) -> Any:
	"""Validate/convert ``value`` against ``expected`` type, or raise."""
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

	# Enums (incl. ``StrEnum``): coerce the wire value to a member, or reject a
	# value outside the closed set with a clear message.
	if isinstance(expected, type) and issubclass(expected, enum.Enum):
		try:
			return expected(value)
		except ValueError as exc:
			raise ValidationError(f"{path}: {value!r} is not a valid {expected.__name__}") from exc

	# Scalars. ``bool`` is a subclass of ``int`` in Python; keep them distinct
	# on the wire so a stray ``true`` is never silently read as ``1``.
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

	# Unknown typing construct: accept rather than reject, so the contract can
	# grow without this validator becoming a bottleneck.
	return value


def from_dict(cls: type[_T], data: Mapping[str, Any]) -> _T:
	"""Build a dataclass instance of ``cls`` from ``data``, validating types.

	Walks ``typing.get_type_hints`` for ``cls`` and coerces each field,
	recursing into nested dataclasses, ``list[...]``, ``dict[...]`` and
	Optionals. Missing required fields and type mismatches raise
	:class:`ValidationError` naming the field path. Extra keys are ignored so
	an older peer tolerates a newer one adding fields.

	``data`` is trusted to be a mapping; every wire entry point
	(:func:`decode_message` and the nested-dataclass branch of ``_coerce``)
	guarantees that before calling here.
	"""
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
	"""Serialize a dataclass instance to a plain ``dict`` (recursively)."""
	if not dataclasses.is_dataclass(obj) or isinstance(obj, type):
		raise ValidationError(f"to_dict expects a dataclass instance, got {type(obj).__name__}")
	return dataclasses.asdict(obj)


# --- JSON-lines framing ------------------------------------------------------


def encode_message(obj: Any) -> bytes:
	"""Encode a dataclass (or plain dict) as one UTF-8 JSON line (``\\n``)."""
	payload: Any = to_dict(obj) if dataclasses.is_dataclass(obj) and not isinstance(obj, type) else obj
	return (json.dumps(payload, separators=(",", ":"), ensure_ascii=False) + "\n").encode("utf-8")


def decode_message(line: bytes | str) -> dict[str, Any]:
	"""Decode one JSON line into a dict, raising :class:`ValidationError`."""
	text = line.decode("utf-8") if isinstance(line, bytes) else line
	try:
		parsed: Any = json.loads(text)
	except (ValueError, UnicodeDecodeError) as exc:
		raise ValidationError(f"malformed JSON line: {exc}") from exc
	if not isinstance(parsed, dict):
		raise ValidationError(f"expected a JSON object, got {type(parsed).__name__}")
	return cast("dict[str, Any]", parsed)


# --- Envelope ----------------------------------------------------------------


@dataclass
class Request:
	"""A client→bridge command frame."""

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


# --- Command params / results ------------------------------------------------


@dataclass
class HelloParams:
	mode: CaptureMode
	protocolVersion: int
	#: Temporarily raise NVDA's own log verbosity for this session (restored at
	#: teardown). Unset leaves NVDA's current level alone; capture still happens
	#: either way (see LogLevel).
	logLevel: LogLevel | None = None
	#: Move the reader's signals that a session CANNOT HEAR into the channel it
	#: can -- today exactly one key, NVDA's ``passThroughAudioIndication``, whose
	#: browse/focus mode change is a wave file by default and words when it is off
	#: (spec 0024).
	#:
	#: The membership test is narrow on purpose: a session may change a setting
	#: only if the change MOVES INFORMATION BETWEEN CHANNELS WITHOUT ADDING OR
	#: REMOVING ANY. Such a change cannot alter what the reader decided to report,
	#: only where the report is delivered, so a finding made under it is still a
	#: finding about the user's own configuration. Anything that changes what
	#: would have been said is refused however convenient.
	#:
	#: ``None`` means "whatever this mode's default is", which is the only honest
	#: default because the two modes differ: SILENT normalises (the human hears no
	#: speech anyway, so moving a signal into the speech channel takes nothing
	#: from them and the agent gains the words), LIVE does not (the human would
	#: hear "Focus mode" spoken instead of the tone they chose, which is theirs to
	#: decide). ``True``/``False`` overrides that per session.
	#:
	#: Every key actually changed comes back in :attr:`HelloResult.normalized`,
	#: and every one is restored at teardown by the same override map ``setConfig``
	#: uses -- nothing is written to the reader's disk.
	normalize: bool | None = None
	#: What the agent is standing in for this session: ``user``, ``validator`` or
	#: ``expert`` (spec 0029). Fixed for the session, like ``mode``.
	#:
	#: A PLAIN ``str`` AND NOT AN ENUM, deliberately. A closed enum here would make
	#: :func:`from_dict` reject a value it did not recognise, and the rejection
	#: would fail the HANDSHAKE -- so the day a fourth persona is added, a newer
	#: server could not connect to any bridge already in the field. A bridge that
	#: does not recognise a persona must degrade (serve its general guidance and
	#: say so), never error; see ``specs/wire/v1/protocol.md`` §4, which states the
	#: same carve-out that already applies to unknown capability strings.
	#:
	#: Defaults to ``""`` so an older SERVER, which does not know about personas,
	#: still handshakes with a newer bridge. Both directions degrade.
	persona: str = ""


@dataclass(frozen=True)
class ReaderInfo:
	"""Which screen reader answered, announced by ``hello``.

	Reader-neutral by design (spec 0005): the server surfaces this to the MCP
	client so the agent knows *which* reader it is driving — NVDA's browse/focus
	modes and JAWS's forms mode are different mental models. The NVDA bridge
	fills ``name="nvda"``.
	"""

	name: str
	version: str


@dataclass(frozen=True)
class SilenceCapInfo:
	"""Whether this reader bounds how long a silent session may keep the human mute.

	A property of the READER'S MACHINE, reported so an agent can behave well on it,
	and settable only there -- there is no command that changes it. That is
	deliberate: an agent that could raise its own ceiling does not have one.

	It changes what a well-behaved agent does. On a capped machine, narrate before
	any stretch of work that does not drive the reader; on an uncapped one, do not
	spend round trips on narration nobody is there to hear. Without this an agent
	cannot tell the two apart and must either narrate uselessly forever or guess.

	Only a ``silent`` session can be capped, because only a silent session
	suppresses anything.
	"""

	#: Whether the cap is in force on this machine. False on one whose owner
	#: declared it unattended -- an accessibility run on a CI box at 3am has no
	#: human to protect, and un-muting it would be damage rather than a safeguard.
	enabled: bool
	#: Seconds of no audible event after which the reader WARNS its human.
	warnAfterSeconds: float
	#: Seconds after which the reader STOPS SUPPRESSING. Capture is unaffected:
	#: the same entries, the same indices and the same timestamps still reach
	#: ``getSpeech`` -- what changes is only that the words also reach the
	#: speakers.
	liftAfterSeconds: float


@dataclass(frozen=True)
class NormalizedSetting:
	"""One reader setting this session moved from one output channel to another.

	Disclosure, not decoration (spec 0024 Part 3.2): a finding must be
	reproducible from the record, and an agent must never be quietly driving a
	different reader than the user's. An EMPTY list tells the agent it is on the
	user's own configuration; a non-empty one writes the asterisk down.

	``previous``/``current`` rather than the ``from``/``to`` the spec first drew:
	``from`` is a Python keyword and this dataclass is the contract's canonical
	source, so the wire takes the spelling the source can express.

	``why`` is a FIXED string owned by the admitted-set data, never prose
	composed at runtime and never translated: the transcript is read by humans
	who will not have the spec open, and a reason that can drift from the spec is
	worse than none.
	"""

	keyPath: list[str]
	previous: Any
	current: Any
	why: str


def _no_normalized() -> list[NormalizedSetting]:
	"""An empty disclosure list, typed -- ``list`` alone is partially unknown."""
	return []


@dataclass
class HelloResult:
	protocolVersion: int
	reader: ReaderInfo
	capabilities: list[Capability]
	mode: CaptureMode
	synth: str
	#: Absolute path to the bridge's own session transcript, on the READER's
	#: disk. A convenience, not a contract an agent should depend on (spec 0021):
	#: the artifact is written for the human at the reader, with capture-time
	#: stamps only the bridge can produce, and for a remote bridge it names a file
	#: the agent cannot open. An agent wanting its own complete record of what was
	#: said calls ``getSpeech(sinceIndex=0)`` -- the ring is unbounded within a
	#: session -- which is why `getTranscript` was considered and rejected.
	#:
	#: (Spec 0009's separate NVDA-log capture FILE is gone: 0020 replaced it with
	#: the in-memory journal, queried through getLog.)
	logPath: str
	#: The BRIDGE's own version -- the add-on's, not the reader's (that is
	#: ``reader.version``). Reported because the bridge is installed separately
	#: from the code under test: a live-NVDA run talks to whatever build was
	#: last installed, and without this a stale one shows up as an inexplicable
	#: capability or behaviour mismatch rather than as "you are running an old
	#: build". ``"unknown"`` when the bridge cannot determine it.
	bridgeVersion: str = "unknown"
	#: THE READER'S OWN GUIDANCE for the persona this session declared, delivered
	#: in the handshake rather than left to be fetched (spec 0022 A.5).
	#:
	#: Exactly what ``getGuidance`` would answer -- the same type, so the two
	#: routes cannot describe the same document differently. ``getGuidance``
	#: remains, for a re-read and for a bridge that would rather answer on
	#: demand; a server that receives this field simply never needs to ask.
	#:
	#: WHY IN THE HANDSHAKE. The persona already travels in ``HelloParams``, so
	#: the bridge knows which document is wanted at the moment it answers, and
	#: the round trip that would otherwise fetch it is one the connection was
	#: making anyway. That matters because a POINTER at this document is a
	#: pointer agents demonstrably do not follow: two external runs (specs 0027
	#: and 0030) each had one and each went elsewhere -- to PowerShell, and to
	#: reading the server's source.
	#:
	#: ``None`` means this bridge publishes no guidance of its own, which is a
	#: supported configuration and not a failure: the agent falls back on the
	#: server's own documents, which carry the rule without the instances.
	guidance: GetGuidanceResult | None = None
	#: Whether this MACHINE bounds how long a silent session may keep its human
	#: unable to hear (spec 0032). ``None`` means this bridge does not say, which a
	#: server reports as unknown rather than as either answer -- an older bridge is
	#: not a protocol error.
	#:
	#: It rides in the handshake for the reason the guidance document does: a fact
	#: an agent must fetch is a fact it does not have, and this reply was already
	#: being sent.
	silenceCap: SilenceCapInfo | None = None
	#: Whether A HUMAN IS EXPECTED AT THE READER'S MACHINE (spec 0035). The fact
	#: the machine's owner DECLARED, carried as itself rather than reconstructed
	#: at the far end from a policy derived from it.
	#:
	#: ``None`` is a third answer and not a default: this bridge does not say,
	#: which is an older build rather than a claim either way. A consumer that
	#: receives it may fall back on inferring attendance from ``silenceCap``, and
	#: a consumer that receives the field MUST NOT -- see protocol.md section 3.
	#:
	#: DELIBERATELY NOT A MEMBER OF ``SilenceCapInfo``, which is one line and the
	#: wrong shape. ``silenceCap`` answers *does this machine bound the silence,
	#: and with what thresholds*; attendance is the machine fact today's policy
	#: happens to be derived FROM, and the two must be able to disagree -- a
	#: bridge with no cap machinery at all still knows whether someone is sitting
	#: there. Nesting the cause inside the effect would teach the next reader they
	#: are one thing.
	#:
	#: The asymmetry that earns it the space: wrong towards attended costs an
	#: agent round trips narrating to an empty room; wrong towards unattended
	#: tells a well-behaved agent to stop narrating to a blind person who is
	#: there, which is the harm spec 0032 exists to prevent.
	#:
	#: READ-ONLY, for 0032's reason: there is no command that sets it. An agent
	#: that could declare the room empty could switch off its own obligation to
	#: narrate.
	attended: bool | None = None
	#: Every setting this session moved between output channels, and why (spec
	#: 0024 Part 3.2). EMPTY means the session is driving the user's own
	#: configuration untouched, which is the answer an agent needs before it
	#: reports a finding; non-empty writes the asterisk down where a human
	#: reading the transcript will find it.
	#:
	#: Reported as data rather than implied by ``normalize``, because what the
	#: session ASKED FOR and what it actually CHANGED are two different facts: a
	#: key already at the wanted value is not listed, so an agent can tell a
	#: reader it reconfigured from one it merely offered to.
	normalized: list[NormalizedSetting] = field(default_factory=_no_normalized)


@dataclass
class EchoParams:
	"""Diagnostic round-trip: whatever ``payload`` is sent comes back unchanged.

	``payload`` is ``Any`` on purpose — echo exists to prove the *whole* stack
	(encode → frame → decode → validate → dispatch → re-encode) survives arbitrary
	JSON: unicode, nesting, floats, long strings. No other command exercises that
	end to end.
	"""

	payload: Any


@dataclass
class EchoResult:
	payload: Any


#: Grace window a mutating command waits, in milliseconds, before reporting the
#: speech that arrived (spec 0025). Chosen against a measurement: NVDA finishes
#: producing a keystroke's speech ~124 ms after the gesture, while an agent's
#: tool round trip is ~2.6 s, so this is where the common case already is and it
#: costs ~4% of a trip the caller was paying anyway.
#:
#: It answers "has speech STARTED?", which is a fact at a stated instant --
#: never "has speech stopped?", which is unanswerable because silence before and
#: silence after are the same observable. That is why no result computed from
#: this window ever claims completeness (spec 0025 Part 2).
DEFAULT_GRACE_MS: int = 100

#: ``typeText``'s default is 0: with "speak typed characters" on, typing emits
#: one utterance per character and none of them is worth a wait. Deliberately
#: unlike :data:`DEFAULT_GRACE_MS` -- the two tools differ in what their speech
#: is worth, and matching them would be consistency in the wrong dimension
#: (spec 0025, settled 2026-08-16).
DEFAULT_TYPE_GRACE_MS: int = 0


@dataclass
class PressGestureParams:
	#: NVDA gesture ids, pressed in order, blocking until each is processed.
	gestures: list[str]
	#: Milliseconds to wait after EACH gesture for the speech it caused, before
	#: moving on. ``0`` opts out and restores the pre-0025 behaviour. Per call
	#: only -- there is no session default, because a knob nobody needed cannot
	#: easily be taken away later, while one that turns out to be wanted can be
	#: added without breaking anything.
	graceMs: int = DEFAULT_GRACE_MS
	#: Spoken to the HUMAN at the reader before the first gesture is dispatched,
	#: through the same side channel as ``announce`` -- audible even in a silent
	#: session. It rides along because narrating each step is what keeps a mute
	#: tester safe, and doing it as its own call roughly doubled the call count:
	#: the thing that protects the human must not be the thing that costs the
	#: most (spec 0025 Part 3.4). Empty means say nothing.
	announce: str = ""


@dataclass
class TypeParams:
	"""Literal text to insert into whatever holds system focus.

	``text`` is opaque content -- routed without interpretation, exactly as a
	gesture id is. It is not a command: control characters, newlines and Enter
	are not interpreted; the agent composes those with ``pressGesture``.
	"""

	text: str
	#: Milliseconds to wait after the text is injected for the speech it caused.
	#: Defaults to 0 -- see :data:`DEFAULT_TYPE_GRACE_MS`.
	graceMs: int = DEFAULT_TYPE_GRACE_MS
	#: Spoken to the human before the text is injected. See
	#: :attr:`PressGestureParams.announce`.
	announce: str = ""


@dataclass
class GetSpeechParams:
	sinceIndex: int


@dataclass
class SpeechEntry:
	"""One captured utterance, placed on the log journal's timeline.

	``logPosition`` is the journal's append position at the moment this sequence
	was captured, and it exists because the ring and the journal answer different
	questions: the ring says *what was said*, the journal says *when it was said
	relative to everything else*. Joining them needs a shared coordinate, not a
	second copy of the text -- which is why the journal never gains speech
	records and this gains an integer instead (spec 0021).

	It matters most in a **silent** session, where the bridge's own
	``filter_speechSequence`` empties the sequence before NVDA reaches its
	``log.io("Speaking %r")`` line, so the journal holds no speech record at all.
	The coordinate still points at the events that surrounded the utterance.
	"""

	text: str
	#: This entry's index in the speech ring (the ``sinceIndex`` coordinate).
	index: int
	#: The journal position when this was captured (the ``getLog`` coordinate).
	logPosition: int
	#: Wall clock at the moment the reader EMITTED this utterance, formatted
	#: ``YYYY-MM-DD HH:MM:SS.mmm`` -- the same shape ``getLogPosition`` returns
	#: and the session transcript writes, so a stamp can be pasted into a search
	#: of the reader's own log (spec 0028).
	#:
	#: **Emitted, not heard.** Live mode captures at ``pre_speechQueued`` and
	#: silent mode at ``filter_speechSequence``; neither is audio, so in live
	#: mode an utterance queued behind a long one can be seconds from audible.
	#: That makes this the right number for "did the application respond
	#: promptly" -- synth queueing belongs to the synth -- and the wrong number
	#: for "when did the user hear it", which this protocol cannot answer.
	emittedAt: str = ""


@dataclass
class SpeechResult:
	"""Captured speech since a bookmark, one entry per utterance.

	A **list, not a joined blob**: the blob welded every utterance into one
	string, so there was nowhere to hang a per-utterance ``logPosition`` and no
	way to map a line back to its index -- ``get_since`` drops empty renders
	while the index range spans everything, so line *i* was never entry
	``fromIndex + i``. One entry per utterance makes "this text, at this index,
	at this journal position" unambiguous, which is the whole point of the
	coordinate (spec 0021).
	"""

	#: One per captured utterance, oldest first. Empty entries are omitted, so
	#: ``len(entries)`` is not ``toIndex - fromIndex``; each entry carries its
	#: own ``index``.
	entries: list[SpeechEntry]
	#: Half-open index range ``[fromIndex, toIndex)`` the read covers.
	fromIndex: int
	toIndex: int


@dataclass
class LastSpeechResult:
	text: str
	index: int
	#: The journal position when this was captured; 0 for the empty sentinel.
	logPosition: int = 0
	#: Wall clock when the reader emitted it; see :class:`SpeechEntry`. Empty
	#: for the sentinel, which was never emitted at all.
	emittedAt: str = ""


@dataclass
class NextIndexResult:
	#: The index the next captured speech sequence will occupy.
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
	#: Journal position of the match -- the coordinate for "show me what NVDA was
	#: doing when it said that". On a miss this is the journal's *current*
	#: position, so it is still a usable "from here" mark (spec 0021).
	logPosition: int = 0
	#: Wall clock when the match was emitted; see :class:`SpeechEntry`. Empty on
	#: a miss -- unlike ``index`` and ``logPosition``, which stay useful as a
	#: "from here" mark, there is no instant to report for speech that never
	#: arrived, and inventing "now" would read as a match that happened.
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
	"""One braille update, placed on the log journal's timeline.

	The braille counterpart of :class:`SpeechEntry`, for the same reason and with
	the same rule: :class:`BrailleBuffer` is an ``IndexedBuffer`` addressed by
	index and dead at teardown, so it has the same join problem and takes the
	same fix. The buffer receives the position as a **value** and never learns
	the journal exists (spec 0021).
	"""

	text: str
	#: This entry's index in the braille ring (the ``sinceIndex`` coordinate).
	index: int
	#: The journal position when this was captured (the ``getLog`` coordinate).
	logPosition: int
	#: Wall clock when the reader emitted this update; see :class:`SpeechEntry`
	#: for the format and for why it is named for emission (spec 0028).
	emittedAt: str = ""


@dataclass
class BrailleResult:
	"""Captured braille since a bookmark, one entry per update.

	A list rather than a joined blob, for the reason given on
	:class:`SpeechResult`. It matters more here than for speech: ``getBraille``
	is the *only* braille fetch -- there is no ``getLastBraille`` -- so this is
	the sole route to a braille entry's coordinate.
	"""

	#: One per captured update, oldest first. Consecutive identical writes are
	#: already dropped by the buffer, so these are genuine changes.
	entries: list[BrailleEntry]
	#: Half-open index range ``[fromIndex, toIndex)`` the read covers.
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
	"""Queryable NVDA state that may be signalled by sound rather than speech.

	Diff two snapshots across a gesture to assert a toggle (e.g. NVDA+space
	flipping ``browseMode`` between ``"browse"`` and ``"focus"``).
	"""

	#: From the focus object's ``treeInterceptor.passThrough``; ``NONE`` when
	#: there is no browse document. A closed set -- see :class:`BrowseMode`.
	browseMode: BrowseMode
	#: ``"talk"`` / ``"beeps"`` / ``"off"`` / ``"onDemand"``.
	speechMode: str
	sleepMode: bool
	inputHelp: bool


@dataclass
class SetStateParams:
	"""Which modes to arrive at. Every field optional: set the ones present.

	MIRRORS :class:`StateResult` rather than taking one command per toggle, so a
	reader that gains a switch costs a field and not a tool, a gate and a
	document (spec 0033 Part 2).

	**The set-domain is narrower than the get-domain**, and only ``browseMode``
	carries the asymmetry.

	``"none"`` is READABLE and NOT SETTABLE: it means the focus has no
	``treeInterceptor`` at all, which cannot be conjured. It is refused before
	anything is attempted, so the tri-state is honoured rather than quietly
	widened.

	Even ``"browse"``/``"focus"`` fails when the focused object is not a browsable
	document, and that failure says so IN THOSE TERMS -- never a bare error and
	never a silent no-op, because ``changed: []`` already means "it was already
	so", and a third meaning inside the one field designed to separate two
	situations is the defect this contract keeps removing.

	``speechMode``, ``sleepMode`` and ``inputHelp`` are absent DELIBERATELY, so a
	client sending one is refused by name rather than silently ignored (spec 0033
	Part 2, "Applying it"): ``inputHelp`` would disarm every gesture sent after
	it, and ``speechMode``/``sleepMode`` are the two settings that can leave a
	human unable to hear their own machine -- 0032 caps suppression, and it does
	not count a speech mode an agent switched off.
	"""

	browseMode: BrowseMode | None = None


@dataclass
class SetStateResult:
	"""The state AFTER the write, plus which fields this call actually moved.

	It answers with the state rather than with ``ok: true``: the caller's next
	question is always "am I there now", and a question answered in the same
	round trip costs nothing (spec 0025). That also makes the command
	self-verifying -- a caller that reads the result never needs the re-check
	that a toggle forces.

	``changed`` NAMES THE FIELDS this call moved, and an empty list means the
	reader was already in the asked-for state. One observable, two situations is
	the defect (``capturedAtLevel``, ``ok: true``, ``announced``); "you flipped
	it" and "it was already so" are the two here.

	Names rather than before/after pairs, decided 2026-08-20: the "after" is
	already in ``state`` on this very result, so a pair would republish half of
	it -- and with a two-value settable domain the "before" carries no
	information a caller cannot derive. The question reopens honestly the day a
	field with more than two settable values is admitted.
	"""

	state: StateResult
	changed: list[str] = field(default_factory=_empty_str_list)


@dataclass
class GesturePress:
	"""One dispatched gesture and the slice of the speech ring it is credited with.

	``speechFrom``/``speechTo`` are the ring's ``sinceIndex`` coordinate, taken
	either side of this key's dispatch: the half-open range ``[speechFrom,
	speechTo)``. An EMPTY range (``speechFrom == speechTo``) is the useful case
	as often as not -- it is how a silent key becomes visible instead of
	inferred, which is exactly what a batched ``{"pressed": ["h","h","h"]}`` used
	to hide.

	**Attribution is by dispatch-time coordinate, not by causation** (spec 0025,
	Honest limits). Speech caused by gesture *n* can land after gesture *n+1*
	went out and will be credited to *n+1*. The reliable readings are the
	aggregate window and "this key's span was empty"; a per-key span in a fast
	batch is a useful approximation, not a proof.
	"""

	gesture: str
	speechFrom: int
	speechTo: int


@dataclass
class GestureResult:
	"""What ``pressGesture`` observed within its grace window.

	**It says what had arrived by a stated instant, and where to resume. It never
	says that is all there is** (spec 0025 Part 2) -- which is why there is no
	``complete`` or ``finished`` field and never will be. An empty ``speech``
	means "nothing had arrived by then", a fact; it does not mean the gesture did
	nothing. The caller resumes from ``speechTo``: wait a little and read again,
	or ``waitForSpeech`` for a specific phrase.

	This collapses the act/settle/listen loop into ONE round trip in the common
	case. The rare case -- a browser window opening, a page loading -- still
	costs a second call, which is what it costs today.
	"""

	#: One entry per gesture, in dispatch order, each with its own span.
	pressed: list[GesturePress]
	#: Every non-empty utterance captured across the whole call, deduplicated
	#: into one list rather than repeated inside each press's span.
	speech: list[SpeechEntry]
	#: The aggregate half-open window ``[speechFrom, speechTo)`` this call
	#: covered. ``speechTo`` is exactly the ``sinceIndex`` to pass next.
	speechFrom: int
	speechTo: int
	#: The reader's mode-state sampled at the CLOSE of the last grace window --
	#: an instant the caller knows. It is ``getState``'s four fields and
	#: deliberately NOT focus information: a browse/focus toggle is synchronous
	#: with the script that performed it and is already complete here, while
	#: focus movement is asynchronous and a sample taken now is still probably
	#: pre-effect (spec 0023, upheld by 0025 Part 3.3). It answers 0024's
	#: question -- did something happen that this session cannot HEAR -- not
	#: 0023's. ``None`` when the reader serves no ``state`` capability.
	state: StateResult | None = None


@dataclass
class TypeResult:
	"""What ``typeText`` observed. Same contract as :class:`GestureResult`.

	One span rather than per-key spans: the text goes in as one injection, so
	there is nothing to attribute between. ``typed`` is the length of what was
	SENT -- never the text, because this is exactly how a secret would be
	entered (spec 0019).
	"""

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
	"""Speak ``text`` aloud to the human at the keyboard, even in silent mode.

	A bridge->human hint channel (not agent-facing data): the bridge voices this
	on a side channel that never touches the reader's configured synth, so the
	spy stays transparent to NVDA and other add-ons. Acknowledged with
	:class:`AckResult`.
	"""

	text: str


@dataclass
class AckResult:
	"""Generic acknowledgement for commands with no payload (ping, bye, ...)."""

	ok: bool = True


@dataclass
class PingResult:
	"""``ping``'s reply: the peer is alive, plus what it is doing to speech.

	``ok`` is the acknowledgement ``ping`` has always carried. ``suppressing``
	rides along because ``status`` -- the one ungated tool that answers with proof
	rather than memory -- makes its round trip with this command, so a silence-cap
	lift becomes discoverable by asking without costing a trip of its own.

	Its own type rather than :class:`AckResult`, which ``bye`` also uses: a
	session-specific fact does not belong on the generic acknowledgement.
	"""

	ok: bool = True
	#: Whether words are being withheld from the human RIGHT NOW. ``False`` in
	#: ``live`` mode, ``False`` while an ``askUser`` window is open, and ``False``
	#: after the silence cap has lifted -- so this answers "can the person at that
	#: machine hear it?", not "was this session opened silent". ``None`` from a
	#: bridge that does not say.
	suppressing: bool | None = None


@dataclass
class AskUserParams:
	"""Present a prompt to the human and suspend speech suppression.

	Returns a ticket immediately so the handler does not block past the
	heartbeat window. Pair with :class:`WaitForUserReplyParams`.
	"""

	prompt: str


@dataclass
class AskUserResult:
	"""The ticket the agent polls with ``waitForUserReply``."""

	ticket: str


@dataclass
class WaitForUserReplyParams:
	"""Poll for the human's answer to a prompt identified by ``ticket``.

	``timeout`` (default 30 s) bounds *this poll*, not the whole window.
	The window's own deadline (300 s from ``askUser``) is the bridge's
	business; the agent re-polls until ``answered`` is ``true`` or the
	bridge returns an error for an expired ticket.
	"""

	ticket: str
	timeout: float = 30.0


@dataclass
class WaitForUserReplyResult:
	"""Whether the human answered, and what they said (always empty in stage 1)."""

	answered: bool
	#: Always empty in stage 1 (the acknowledgement gesture carries no text).
	#: Ships so stage 2 (a dialog) populates it without a wire break.
	text: str = ""


@dataclass
class GetLogParams:
	"""Parameters for ``getLog``: anchor, window count, filters and projection.

	**Three anchors, mutually exclusive.** Supplying more than one is an error
	rather than a precedence puzzle (spec 0021). ``sincePosition`` reads forwards
	from a position and is the polling anchor, paired with the previous result's
	``nextPosition``. ``lastSeconds`` reads back from now -- the "it just
	happened" anchor, for when the human noticed the bug *after* it happened and
	no mark was taken. ``commandId``/``windows`` is 0020's command-span anchor,
	and the default when none is given.

	``windows`` belongs to the command anchor and is REJECTED alongside either of
	the other two: they already say how far back to read, so accepting it there
	would answer a different question from the one asked and leave the caller no
	way to tell -- the same reason an unknown field name is refused rather than
	dropped.

	Reads never consume: re-issuing the same ``sincePosition`` with a different
	``exclude`` returns the same records, re-filtered.
	"""

	#: The request id whose window to anchor on. Defaults to the most recently
	#: marked command.
	commandId: int | None = None
	#: How many command windows to include, counting back from the anchor.
	windows: int = 1
	#: Read forwards from this journal position (from ``getLogPosition`` or a
	#: previous result's ``nextPosition``). A position below the ring's oldest
	#: surviving record reports ``truncated: true`` -- which is how a poll loop
	#: learns it fell behind.
	sincePosition: int | None = None
	#: ...or read back this many seconds from now. Relative deliberately: it
	#: needs no agreement on a clock format and no tolerance for skew, and "the
	#: last ten seconds" is what a human actually says.
	lastSeconds: float | None = None
	minLevel: LogLevel | None = None
	contains: list[str] | None = None
	exclude: list[str] | None = None
	#: Which fields to render per record. Default: time, level, module, message.
	fields: list[str] | None = None
	maxEntries: int = 200


@dataclass
class SetLogLevelParams:
	"""Raise NVDA's own logging floor for the rest of the session."""

	level: LogLevel


@dataclass
class LogLevelResult:
	"""The level now in force, and what it replaced."""

	level: LogLevel
	previous: LogLevel


@dataclass
class LogSliceResult:
	"""A bounded slice of the log journal, however it was anchored."""

	#: Formatted text, one record per line, like a slice of nvda.log.
	text: str
	#: Number of records in ``text``.
	entries: int
	#: Number of records that passed the filters, before ``maxEntries``.
	matched: int
	#: True when ``matched > entries``, or the slice had aged out of the ring.
	truncated: bool
	#: The journal position just past the last record considered. Pass it back as
	#: ``sincePosition`` to continue the tail: a poll loop driven by this neither
	#: repeats nor skips. Always present, whichever anchor was used -- it is the
	#: cursor the CALLER owns, which is why a read never consumes (spec 0021).
	nextPosition: int
	#: The floor in force for this slice. Exact for a command anchor -- a span has
	#: one level by construction, since ``setLogLevel`` is itself a command and so
	#: closes the span -- but only the level *currently* in force for a
	#: position/time anchor, which may straddle a change.
	capturedAtLevel: LogLevel
	#: The anchor command's id, or ``None`` when anchored by position or time:
	#: such a read spans whatever commands happen to fall in it and is not
	#: attributable to one.
	fromCommandId: int | None = None
	#: The farthest command id included, or ``None``, for the same reason.
	toCommandId: int | None = None


@dataclass
class LogPositionResult:
	"""Where the journal is right now -- the F1 marker ritual, made programmatic.

	Returns **no records**, deliberately: at the moment you decide to start
	observing you specifically do not want the backlog, and paying for a large
	slice to learn a single integer defeats the purpose. Same shape, and same
	reason, as ``getNextSpeechIndex`` (spec 0021).
	"""

	#: The journal's current append position; pass to ``getLog.sincePosition``.
	position: int
	#: Wall clock, for lining a slice up against the session transcript, the
	#: user's own nvda.log, and the human saying "around then".
	time: str


@dataclass
class WaitForLogParams:
	"""Block until a matching record is journalled, or ``timeout`` elapses.

	The journal's answer to ``waitForSpeech``, and **pull, not push**: the agent
	asks and waits, so nothing in this protocol tails or pushes. For "observe me,
	a bug is about to happen", block at ``minLevel: "error"`` and get the moment
	it happens instead of choosing a poll cadence and hoping.
	"""

	#: Bounds THIS call, caller-supplied, as ``waitForSpeech``'s does.
	timeout: float = 5.0
	minLevel: LogLevel | None = None
	contains: list[str] | None = None


@dataclass
class GetGuidanceResult:
	"""The bridge's own written guidance for the session's persona (spec 0029).

	**Takes no parameters.** The persona is fixed at ``hello``, and this answers
	for the session's persona and nothing else: a ``persona`` argument would let an
	agent fetch one stance's instructions from a session standing in another,
	which quietly undoes the thing the declaration is for.

	The text is **opaque markdown**. The server transports and frames it and never
	parses it, which is what lets a bridge author write for their own reader
	without negotiating a schema -- and is why a TalkBack bridge can enumerate
	swipes where NVDA's enumerates keystrokes.
	"""

	#: The persona this text answers for, echoed as received. An unrecognised one
	#: comes back unchanged rather than normalised: the field says what was ASKED.
	persona: str
	#: Whether the bridge had persona-specific instruction for that value. ``False``
	#: with the general text is a real answer -- and a necessary one, since silence
	#: would leave the agent believing it had been instructed when it had not.
	recognised: bool
	#: The document: whatever this bridge says about holding that stance on this
	#: reader, composed as one markdown text. There is no second call and no
	#: structure for the server to reassemble.
	text: str


@dataclass
class DocumentSnapshotParams:
	"""How much of the browse document to render (spec 0026).

	**Every field is optional and the ordinary call carries none of them**, which
	returns the WHOLE document. That is the point of the command: reading a page
	line by line costs one round trip per line, and a snapshot that is bounded by
	default is incomplete by default -- an agent would read the first screenful
	of a long page and believe it had the page.

	The bounds exist for the agent who has decided it wants less, and they carry
	a cost the shape cannot express: **two calls are two moments.** A document
	that changes between them -- an infinite scroll, a live region, a page still
	loading -- yields a read stitched from states that never coexisted, and
	nothing in the result can detect it. Only the unbounded call returns a
	coherent picture.
	"""

	#: First buffer line to include. Lines keep their ABSOLUTE ordinals in the
	#: result, so line 14 is line 14 whether or not the read started at 0.
	fromLine: int = 0
	#: Stop after this many lines; ``0`` means no limit.
	maxLines: int = 0
	#: Stop once the rendered text reaches this many characters; ``0`` means no
	#: limit. A budget smaller than the first line still returns that line --
	#: coming back with nothing would read as an empty document.
	maxChars: int = 0


@dataclass
class SnapshotLine:
	"""One line of the document, as the reader renders it.

	A **list of these, not a joined blob**, for spec 0021's reason: a line needs
	a coordinate, so an agent can say "the third result is at line 14" and act
	from there.
	"""

	#: The buffer's own line ordinal.
	line: int
	#: The line as the reader PRESENTS it -- roles and states included, in the
	#: reader's own words and under the user's own verbosity settings. This is
	#: the flat text the user arrows through, not a structural read: a heading
	#: carries its level, a link says it is one, a radio button says whether it
	#: is checked.
	text: str


def _no_snapshot_lines() -> list[SnapshotLine]:
	"""An empty line list, typed -- ``list`` alone is partially unknown."""
	return []


@dataclass
class DocumentSnapshotResult:
	"""The browse document at one instant, as lines (spec 0026).

	**A still frame, not a description of the page.** Whatever the document did
	after ``capturedAt`` is not in here, and nothing in this shape can tell you
	whether it did anything: to see change, take another snapshot and compare.
	"""

	#: Whether the focus is in a document the reader renders into a flat buffer
	#: at all. ``False`` for a dialog, a native application, the desktop -- which
	#: is a real answer and NOT an empty document, the distinction this protocol
	#: has now drawn four times (specs 0020, 0021, 0023, 0024). When it is
	#: ``False`` every other field is empty and ``capturedAt`` is still stamped:
	#: the bridge did look, at a time, and found nothing.
	hasDocument: bool
	#: Wall clock at the read, in ``getLogPosition``'s and ``emittedAt``'s format
	#: so it joins to the reader's log and the session transcript by paste.
	capturedAt: str
	#: The document's own title, best-effort; empty when it has none.
	title: str = ""
	#: The lines, in document order.
	lines: list[SnapshotLine] = field(default_factory=_no_snapshot_lines)
	#: First line included.
	fromLine: int = 0
	#: One past the last line included, so ``[fromLine, toLine)`` is the span.
	toLine: int = 0
	#: Which bound stopped the read, or ``"none"``. See :class:`TruncatedBy`.
	truncatedBy: TruncatedBy = TruncatedBy.NONE


@dataclass
class WaitForLogResult:
	"""Whether a matching record appeared, and where it landed.

	Not finding one is ``found: false``, **not** an error -- ``waitForSpeech``'s
	established manners, for the same reason: a wait that expires is an ordinary
	outcome an agent branches on, not a fault.
	"""

	found: bool
	#: Where the match landed, to widen around with ``getLog``. On a miss, the
	#: journal's current position -- still a usable mark.
	position: int
	#: The matching record, formatted; empty when not found.
	text: str = ""


# --- Command shapes: the contract's own command -> payload-types table --------


@dataclass(frozen=True)
class CommandShape:
	"""The payload types for one wire command: its ``params`` and ``result``.

	Contract **data**, not just prose: :data:`COMMAND_SHAPES` makes the
	command→types mapping explicit so the JSON Schema can be *generated* from it
	(``schema.py``) and so a new command cannot be added without declaring its
	shapes. ``params`` is ``None`` for a command that carries no parameters.
	"""

	params: type | None
	result: type


#: Every wire command's param/result types. A test asserts this covers every
#: :class:`Command` member, so the schema and the contract can never disagree
#: about which commands exist.
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
