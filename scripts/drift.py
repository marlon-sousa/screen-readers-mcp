# Wire-contract drift gates.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe gates
#
# THREE BINDINGS, ONE CONTRACT, AND NO LANGUAGE SERVER CROSSES BETWEEN THEM. The
# schema is the only index the Python, Go and Swift renderings share, so each
# gate here asks whether one of them still says what the schema says.
#
# Two of the three are GENERATED from shared/screenreader_wire/protocol.py and
# committed: the JSON schema both other languages are described by, and the Go
# binding the server decodes with. Committing a generated file is only safe if
# something proves it still matches its source -- otherwise the two sides drift
# and the first symptom is a decode failure in the conformance tier, or worse, a
# field that silently stops round-tripping. Both ask the same question, "does
# regenerating change anything?", and the fix is always to regenerate and commit,
# never to edit the artifact.
#
# The third, the SWIFT binding, is hand-written (spec 0043), so there is nothing
# to regenerate and the question is different: does what the source DECLARES
# still match the schema, field by field? scripts/swift_wire_binding.py reads the
# declarations; this file decides whether the difference is drift, and names the
# schema, the binding and the field -- a drift an agent cannot locate is a drift
# it will paper over.
#
# Note on the comparison: schema.json is compared as PARSED JSON, not as text.
# Comparing bytes makes this gate fail on a BOM or a line ending that no
# consumer can observe -- a false alarm that costs more than the gate saves.

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
	"""The committed schema must equal what protocol.py generates right now."""
	# stdout ONLY: uv writes its own progress to stderr, and folding the two
	# together turns a working generator into "did not emit JSON".
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
	"""`go generate` must be a no-op against the committed binding."""
	before = BINDING.read_bytes()
	before_stat = BINDING.stat()
	code, _out, err = _run(["go", "-C", str(ROOT / "server"), "generate", "./adapters/wire"])
	if code != 0:
		print("  FAIL  wire binding  go generate failed:", err.splitlines()[-1] if err else code)
		return False
	after = BINDING.read_bytes()
	if before == after:
		# Restore the ORIGINAL mtime. `go generate` rewrites the file whether or
		# not the content changed, and the doctor decides the MCP server binary
		# is stale by comparing it against the newest server/*.go -- so running
		# this gate would make the binary look stale and fail the very next task.
		# A gate that manufactures work for another gate is worse than no gate.
		os.utime(BINDING, (before_stat.st_atime, before_stat.st_mtime))
		print("  PASS  wire binding  go generate is a no-op")
		return True
	print("  FAIL  wire binding  wire.gen.go was stale and has just been regenerated")
	print("        -> review `git diff server/adapters/wire/wire.gen.go` and commit it")
	return False


class _Unmappable(Exception):
	"""A schema fragment this gate does not know how to render in Swift."""


def _scalars() -> dict[str, str]:
	# The four JSON scalars, and nothing else: an unmapped construct must reach
	# _Unmappable rather than fall through to a guess.
	return {"string": "String", "integer": "Int", "number": "Double", "boolean": "Bool"}


def _expected_type(node: dict[str, Any], binding: Binding, where: str) -> tuple[str, bool]:
	"""The Swift type a schema fragment calls for, and whether it is optional."""
	# `default` is an annotation, not part of the type -- see schema.py's header.
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
		# The contract's open value: `Any` in Python, `{}` in the schema.
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
	"""How the Swift source must spell a schema default."""
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
			# Either spelling is honest Swift; `.none` needs its type spelled out
			# to avoid reading as Optional.none, and the binding does that.
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
	"""Every difference between one `$defs` entry and its Swift struct."""
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
		# A default of null makes a field Optional in Swift whatever its type says
		# -- `Response.result` is the contract's open value defaulting to null, and
		# an Optional is the only way to tell "sent as null" from "not sent".
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
	"""The hand-written Swift binding must still say what the schema says."""
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
	# Selectable because the two gates need different toolchains, and CI splits
	# its jobs along exactly that line: the schema gate needs only Python, the
	# binding gate needs Go. Running both in the `shared` job would drag a Go
	# toolchain into it for one command; running both in `server` would drag in
	# uv. Each job asks for the half it is already equipped for, and a developer
	# with everything installed just runs `poe gates` and gets both.
	parser = argparse.ArgumentParser(description="Check generated artifacts against their sources.")
	parser.add_argument("--schema", action="store_true", help="only the JSON schema gate (needs uv)")
	parser.add_argument("--binding", action="store_true", help="only the Go wire-binding gate (needs go)")
	parser.add_argument("--swift", action="store_true", help="only the Swift binding gate (needs neither)")
	args = parser.parse_args()
	# Neither flag means all of them, so the bare invocation keeps its old meaning.
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
