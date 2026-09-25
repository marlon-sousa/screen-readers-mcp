# Wire-contract drift gates.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe gates
#
# Each gate asks whether one binding of the wire contract still says what the schema says.
# schema.json is compared as parsed JSON, so a BOM or line ending is not drift.

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from swift_wire_binding import Binding, BindingParseError, Field, read_binding

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "specs" / "wire" / "v1" / "schema.json"
BINDING = ROOT / "server" / "adapters" / "wire" / "wire.gen.go"
SWIFT_BINDING = ROOT / "bridges" / "voiceover" / "Sources" / "ScreenReaderWire"


def _run(args: list[str], cwd: Path | None = None) -> tuple[int, str, str]:
	done = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
	return done.returncode, done.stdout.strip(), done.stderr.strip()


def schema_gate() -> bool:
	# Parse stdout only: uv writes its progress to stderr.
	code, out, err = _run(
		[
			"uv",
			"run",
			"--directory",
			str(ROOT / "shared"),
			"python",
			"-c",
			"import json;from screenreader_wire.schema import build_wire_schema;"
			"print(json.dumps(build_wire_schema()))",
		]
	)
	if code != 0:
		print("  FAIL  schema        could not generate:", err.splitlines()[-1] if err else code)
		return False
	try:
		generated = json.loads(out)
	except json.JSONDecodeError as exc:
		print(f"  FAIL  schema        generator did not emit JSON: {exc}")
		return False

	committed = json.loads(SCHEMA.read_text(encoding="utf-8-sig"))
	if generated == committed:
		print("  PASS  schema        committed schema.json matches protocol.py")
		return True
	print("  FAIL  schema        schema.json is stale")
	print("        -> regenerate it from protocol.py and commit the result")
	for key in sorted(set(generated) | set(committed)):
		if generated.get(key) != committed.get(key):
			print(f"           differs at top-level key: {key}")
	return False


def binding_gate() -> bool:
	before = BINDING.read_bytes()
	before_stat = BINDING.stat()
	code, _out, err = _run(["go", "-C", str(ROOT / "server"), "generate", "./adapters/wire"])
	if code != 0:
		print("  FAIL  wire binding  go generate failed:", err.splitlines()[-1] if err else code)
		return False
	after = BINDING.read_bytes()
	if before == after:
		# `go generate` always rewrites the file; a newer mtime would make the doctor call the binary stale.
		os.utime(BINDING, (before_stat.st_atime, before_stat.st_mtime))
		print("  PASS  wire binding  go generate is a no-op")
		return True
	print("  FAIL  wire binding  wire.gen.go was stale and has just been regenerated")
	print("        -> review `git diff server/adapters/wire/wire.gen.go` and commit it")
	return False


class _Unmappable(Exception):
	"""A schema fragment this gate does not know how to render in Swift."""


def _scalars() -> dict[str, str]:
	return {"string": "String", "integer": "Int", "number": "Double", "boolean": "Bool"}


def _expected_type(node: dict[str, Any], binding: Binding, where: str) -> tuple[str, bool]:
	shape = {key: value for key, value in node.items() if key != "default"}

	if "anyOf" in shape:
		options = [option for option in shape["anyOf"] if option != {"type": "null"}]
		nullable = len(options) != len(shape["anyOf"])
		if len(options) != 1:
			raise _Unmappable(f"{where}: a union of {len(options)} non-null options is not bound")
		inner, already_optional = _expected_type(options[0], binding, where)
		return inner, nullable or already_optional

	if "$ref" in shape:
		return str(shape["$ref"]).rsplit("/", 1)[-1], False

	if not shape:
		return "JSONValue", False

	kind = shape.get("type")
	if "enum" in shape:
		values = set(shape["enum"])
		names = binding.vocabularies_with(values)
		if not names:
			raise _Unmappable(f"{where}: no Swift vocabulary has exactly the values {sorted(values)}")
		if len(names) > 1:
			raise _Unmappable(f"{where}: {names} all carry the values {sorted(values)}; which one is meant?")
		return names[0], False
	if kind == "array":
		inner, optional = _expected_type(shape["items"], binding, where)
		return f"[{inner}{'?' if optional else ''}]", False
	if kind == "object":
		inner, optional = _expected_type(shape.get("additionalProperties", {}), binding, where)
		return f"[String: {inner}{'?' if optional else ''}]", False
	if kind in _scalars():
		return _scalars()[str(kind)], False
	raise _Unmappable(f"{where}: schema fragment {shape!r} is not bound")


def _expected_default(value: Any, field: Field, binding: Binding) -> str:
	if isinstance(value, bool):
		return "true" if value else "false"
	if isinstance(value, (int, float)):
		return repr(value)
	if isinstance(value, list):
		return "[]"
	if isinstance(value, dict):
		return "[:]"
	vocabulary = binding.vocabularies.get(field.bare_type)
	if vocabulary is not None:
		members = [name for name, member in vocabulary.members.items() if member == value]
		if members:
			# `.none` needs its type spelled out, or it reads as Optional.none.
			return f"{field.bare_type}.{members[0]} or .{members[0]}"
	return json.dumps(value)


def _default_matches(value: Any, field: Field, binding: Binding) -> bool:
	if field.default is None:
		return False
	expected = _expected_default(value, field, binding)
	if " or " in expected:
		return field.default in expected.split(" or ")
	if isinstance(value, float) and field.default.rstrip("0").rstrip(".") == expected.rstrip("0").rstrip("."):
		return True
	return field.default == expected


def _check_shape(name: str, body: dict[str, Any], binding: Binding) -> list[str]:
	problems: list[str] = []
	shape = binding.shapes.get(name)
	if shape is None:
		return [f"{name}: the schema defines it and the Swift binding has no `public struct {name}`"]

	required = set(body.get("required", []))
	properties: dict[str, Any] = body.get("properties", {})
	for property_name, node in properties.items():
		where = f"{name}.{property_name}"
		field = shape.field_named(property_name)
		if field is None:
			problems.append(f"{where}: in the schema, missing from {shape.file.name}")
			continue
		try:
			expected_type, optional = _expected_type(node, binding, where)
		except _Unmappable as unmappable:
			problems.append(str(unmappable))
			continue
		# A default of null makes the field Optional, to tell "sent as null" from "not sent".
		optional = optional or (property_name not in required and node.get("default", ...) is None)
		if field.bare_type != expected_type or field.optional != optional:
			wanted = expected_type + ("?" if optional else "")
			problems.append(
				f"{where}: schema says {wanted}, {shape.file.name}:{field.line} says {field.type}"
			)
		if property_name in required:
			if field.default is not None:
				problems.append(
					f"{where}: required by the schema, but {shape.file.name}:{field.line} "
					f"defaults it to {field.default}"
				)
			continue
		default = node.get("default", ...)
		if default is ...:
			problems.append(f"{where}: not required by the schema and carries no default -- regenerate it")
		elif default is None:
			if not field.optional or field.default is not None:
				problems.append(
					f"{where}: schema default is null, so {shape.file.name}:{field.line} must be an "
					f"Optional with no initializer, and it is {field.type}"
					f"{'' if field.default is None else ' = ' + field.default}"
				)
		elif not _default_matches(default, field, binding):
			problems.append(
				f"{where}: schema default is {_expected_default(default, field, binding)}, "
				f"{shape.file.name}:{field.line} says {field.default or 'nothing'}"
			)

	for field in shape.fields:
		if field.name not in properties:
			problems.append(f"{name}.{field.name}: in {shape.file.name}:{field.line}, not in the schema")
	return problems


def swift_gate() -> bool:
	committed = json.loads(SCHEMA.read_text(encoding="utf-8-sig"))
	try:
		binding = read_binding(SWIFT_BINDING)
	except BindingParseError as unreadable:
		print("  FAIL  swift binding  cannot be read:", unreadable)
		print("        -> see scripts/swift_wire_binding.py for the shape it reads")
		return False

	problems: list[str] = []
	if binding.protocol_version != committed["protocolVersion"]:
		problems.append(
			f"protocolVersion: schema says {committed['protocolVersion']}, "
			f"ProtocolVersion.swift says {binding.protocol_version}"
		)

	commands = set(committed["commands"])
	bound = binding.vocabularies["Command"].values if "Command" in binding.vocabularies else set()
	for missing in sorted(commands - bound):
		problems.append(f"command {missing!r}: in the schema, missing from Command.swift")
	for extra in sorted(bound - commands):
		problems.append(f"command {extra!r}: in Command.swift, not in the schema")

	for name, body in sorted(committed["$defs"].items()):
		problems.extend(_check_shape(name, body, binding))

	if not problems:
		print(f"  PASS  swift binding  {len(committed['$defs'])} shapes match specs/wire/v1/schema.json")
		return True
	print(f"  FAIL  swift binding  {len(problems)} difference(s) from specs/wire/v1/schema.json")
	print(f"        -> {SWIFT_BINDING.relative_to(ROOT)} is hand-written: fix the SOURCE, not the schema")
	for problem in problems:
		print(f"           {problem}")
	return False


def main() -> int:
	parser = argparse.ArgumentParser(description="Check generated artifacts against their sources.")
	parser.add_argument("--schema", action="store_true", help="only the JSON schema gate (needs uv)")
	parser.add_argument("--binding", action="store_true", help="only the Go wire-binding gate (needs go)")
	parser.add_argument("--swift", action="store_true", help="only the Swift binding gate (needs neither)")
	args = parser.parse_args()
	both = not (args.schema or args.binding or args.swift)

	ok = True
	if both or args.schema:
		ok = schema_gate() and ok
	if both or args.binding:
		ok = binding_gate() and ok
	if both or args.swift:
		ok = swift_gate() and ok
	print()
	if not ok:
		print("Drift detected. A binding no longer matches the contract it renders.")
		return 1
	print("No drift: every gate that ran matches its source.")
	return 0


if __name__ == "__main__":
	sys.exit(main())
