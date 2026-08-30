# nvda-mcp shared wire protocol -- JSON Schema generator.
# Copyright (C) 2026 Marlon Brandao de Sousa.
# This file is covered by the GNU General Public License.
# See the file COPYING.txt for more details.
#
# ROLE: supporting construct -- a PURE builder that emits the published JSON
# Schema for the wire contract, DERIVED from ``protocol.py``'s dataclasses and
# ``COMMAND_SHAPES``. It walks the same ``typing`` hints ``from_dict`` validates
# with, run the other direction, so a non-Python bridge author can generate
# their own types from the schema instead of reading Python.
#
# Stdlib-only like its sibling, and it is NEVER synced into the addon
# (``sync_shared.py`` copies ``protocol.py`` only -- the addon never needs to
# emit a schema). The committed artifact ``specs/wire/v1/schema.json`` is this
# module's stdout (``python -m screenreader_wire.schema``); the ``shared`` CI job
# regenerates and diffs it, so the schema can never drift from the code.

from __future__ import annotations

import dataclasses
import enum
import json
from collections.abc import Mapping
from typing import Any, Union, cast, get_args, get_origin, get_type_hints

from .protocol import (
	COMMAND_SHAPES,
	PROTOCOL_VERSION,
	Command,
	Request,
	Response,
)

_NONE_TYPE = type(None)

#: Sentinel for "this field has no default at all", distinct from ``None``,
#: which is itself a default several fields declare.
_NO_DEFAULT: Any = object()

#: JSON Schema dialect the emitted document declares.
_DIALECT = "https://json-schema.org/draft/2020-12/schema"


def _union_args(tp: object) -> tuple[Any, ...] | None:
	"""Return the members of ``tp`` if it is a Union / ``X | Y``, else None.

	Mirrors the same helper in ``protocol.py`` so the schema understands exactly
	the constructs the validator does.
	"""
	origin = get_origin(tp)
	if origin is Union:
		return get_args(tp)
	if origin is not None and origin.__class__.__name__ == "UnionType":
		return get_args(tp)
	if type(tp).__name__ == "UnionType":
		return get_args(tp)
	return None


def _schema_for(tp: Any, defs: dict[str, Any]) -> dict[str, Any]:
	"""Return the JSON Schema fragment for one Python type.

	Nested dataclasses are collected into ``defs`` and referenced with ``$ref``,
	so each shape is defined once. Unknown constructs map to ``{}`` (accept
	anything) exactly as the validator's fall-through does.
	"""
	if tp is Any or tp is object:
		return {}

	union = _union_args(tp)
	if union is not None:
		options: list[dict[str, Any]] = []
		nullable = False
		for arg in union:
			if arg is _NONE_TYPE:
				nullable = True
				continue
			options.append(_schema_for(arg, defs))
		if nullable:
			options.append({"type": "null"})
		return options[0] if len(options) == 1 else {"anyOf": options}

	origin = get_origin(tp)
	if origin in (list, tuple):
		(elem,) = get_args(tp) or (Any,)
		return {"type": "array", "items": _schema_for(elem, defs)}
	if origin is dict:
		_, val = get_args(tp) or (Any, Any)
		return {"type": "object", "additionalProperties": _schema_for(val, defs)}

	if isinstance(tp, type) and dataclasses.is_dataclass(tp):
		name = tp.__name__
		if name not in defs:
			defs[name] = {}  # reserve first, so a self-reference resolves to $ref
			defs[name] = _object_schema(tp, defs)
		return {"$ref": f"#/$defs/{name}"}

	# Enums are all ``StrEnum`` in this contract: a closed set of string values.
	if isinstance(tp, type) and issubclass(tp, enum.Enum):
		return {"type": "string", "enum": [cast("Any", m).value for m in tp]}

	# Scalars. bool before int: bool is an int subclass but a distinct JSON type.
	if tp is bool:
		return {"type": "boolean"}
	if tp is int:
		return {"type": "integer"}
	if tp is float:
		return {"type": "number"}
	if tp is str:
		return {"type": "string"}

	return {}


def _default_of(f: dataclasses.Field[Any]) -> Any:
	"""Return ``f``'s default rendered as JSON, or :data:`_NO_DEFAULT`.

	Enum defaults become their wire string, and a ``default_factory`` is CALLED
	-- every factory in this contract exists to hand out a fresh empty container,
	and the empty container is the thing a binding author has to reproduce.
	Anything else raises: a default this cannot render is one the schema would
	silently omit, which is the failure this whole function exists to remove.
	"""
	if f.default is not dataclasses.MISSING:
		value: Any = f.default
	elif f.default_factory is not dataclasses.MISSING:
		value = f.default_factory()
	else:
		return _NO_DEFAULT
	if isinstance(value, enum.Enum):
		value = cast("Any", value).value
	if value is None or isinstance(value, (bool, int, float, str)):
		return value
	if isinstance(value, (list, dict)) and not cast("Any", value):
		return cast("Any", value)
	raise TypeError(f"field {f.name!r} has a default the schema cannot render: {value!r}")


def _object_schema(tp: type[Any], defs: dict[str, Any]) -> dict[str, Any]:
	"""Build the object schema for a dataclass type.

	A field is ``required`` when it has no default (mirrors ``from_dict``), and
	when it HAS one the value is published as ``default``;
	``additionalProperties`` is ``true`` because the validator ignores extra
	keys for forward compatibility.

	Why the defaults are published, given that ``default`` is an annotation JSON
	Schema validators ignore: this document's whole purpose is that a non-Python
	bridge author binds the contract WITHOUT reading Python (see this module's
	header), and a default is part of the shape they must reproduce -- ``graceMs``
	is 100 ms and ``timeout`` is 5 s whether or not the caller sends the key.
	``protocol.md`` §7.2 already told them "defaults live in schema.json"; until
	board entry 13.3 they did not, and the Swift binding was the first reader to
	need them.
	"""
	if not dataclasses.is_dataclass(tp):
		return {}
	hints = get_type_hints(tp)
	properties: dict[str, Any] = {}
	required: list[str] = []
	for f in dataclasses.fields(tp):
		properties[f.name] = _schema_for(hints[f.name], defs)
		default = _default_of(f)
		if default is _NO_DEFAULT:
			required.append(f.name)
		else:
			properties[f.name]["default"] = default
	schema: dict[str, Any] = {"type": "object", "properties": properties}
	if required:
		schema["required"] = required
	schema["additionalProperties"] = True
	return schema


def build_wire_schema() -> dict[str, Any]:
	"""Assemble the whole published wire schema as a plain dict.

	Deterministic: ``$defs`` keys are sorted, properties follow field-definition
	order, and commands follow :class:`Command` declaration order, so the
	committed ``schema.json`` diffs cleanly.
	"""
	defs: dict[str, Any] = {}
	envelope = {
		"request": _schema_for(Request, defs),
		"response": _schema_for(Response, defs),
	}
	commands: dict[str, Any] = {}
	for command in Command:
		shape = COMMAND_SHAPES[command]
		commands[command.value] = {
			"params": None if shape.params is None else _schema_for(shape.params, defs),
			"result": _schema_for(shape.result, defs),
		}
	return {
		"$schema": _DIALECT,
		"title": "nvda-mcp wire protocol",
		"protocolVersion": PROTOCOL_VERSION,
		"$defs": {name: defs[name] for name in sorted(defs)},
		"envelope": envelope,
		"commands": commands,
	}


def to_json(schema: Mapping[str, Any]) -> str:
	"""Render the schema as canonical, newline-terminated JSON text."""
	return json.dumps(schema, indent=2, ensure_ascii=False) + "\n"


if __name__ == "__main__":
	import sys

	# Write bytes with explicit LF: on Windows a text-mode stdout would translate
	# "\n" to "\r\n", making the committed artifact platform-dependent and the
	# drift gate flaky.
	sys.stdout.buffer.write(to_json(build_wire_schema()).encode("utf-8"))
