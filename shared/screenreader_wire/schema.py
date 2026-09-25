# nvda-mcp shared wire protocol -- JSON Schema generator.
# Copyright (C) 2026 Marlon Brandao de Sousa.
# This file is covered by the GNU General Public License.
# See the file COPYING.txt for more details.
#
# ROLE: supporting construct, a pure builder that emits the wire contract's JSON Schema from
# ``protocol.py``'s dataclasses and ``COMMAND_SHAPES``.
#
# Stdlib-only and never synced into the addon; its stdout is the committed ``specs/wire/v1/schema.json``.

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

#: Sentinel for "no default at all", distinct from ``None``, which several fields declare as a default.
_NO_DEFAULT: Any = object()

_DIALECT = "https://json-schema.org/draft/2020-12/schema"


def _union_args(tp: object) -> tuple[Any, ...] | None:
	"""Return the members of ``tp`` if it is a Union / ``X | Y``, else None; mirrors ``protocol.py``."""
	origin = get_origin(tp)
	if origin is Union:
		return get_args(tp)
	if origin is not None and origin.__class__.__name__ == "UnionType":
		return get_args(tp)
	if type(tp).__name__ == "UnionType":
		return get_args(tp)
	return None


def _schema_for(tp: Any, defs: dict[str, Any]) -> dict[str, Any]:
	"""Return the JSON Schema fragment for one type; unknown constructs map to ``{}``, as in the validator."""
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
	"""Return ``f``'s default rendered as JSON, or :data:`_NO_DEFAULT`; raise on one it cannot render."""
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
	"""Build a dataclass's object schema; a field with a default publishes it, one without is required."""
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
	"""Assemble the published wire schema, deterministically so ``schema.json`` diffs cleanly."""
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

	# Explicit LF bytes: a Windows text-mode stdout would write CRLF.
	sys.stdout.buffer.write(to_json(build_wire_schema()).encode("utf-8"))
