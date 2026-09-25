# What the Swift wire binding declares, read out of its source.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: a pure reader of bridges/voiceover/Sources/ScreenReaderWire/ into shapes, fields and vocabularies.
# USED BY: scripts/drift.py, which compares them with specs/wire/v1/schema.json.
#
# The shape the binding must keep: `public struct NAME` or `public enum NAME: String` at column 0, each
# stored property on one tab as `public var name: Type` with an optional ` = default`, and a declaration
# closed by `}` at column 0. A line it is responsible for and cannot read raises, never skips.

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path


class BindingParseError(Exception):
	pass


_STRUCT = re.compile(r"^public struct (\w+)\b")
_ENUM = re.compile(r"^public enum (\w+): String\b")
_TOP_LEVEL_PUBLIC = re.compile(r"^public (\w+)")
_PROPERTY = re.compile(r"^\tpublic var (\w+): ([^={\n]+?)(?: = (.+))?$")
_CASE = re.compile(r"^\tcase (\w+)(?: = \"([^\"]*)\")?$")
#: Capability is a struct with static members, so unknown values are retained rather than refused.
_STATIC_VALUE = re.compile(r"^\tpublic static let (\w+) = (\w+)\(rawValue: \"([^\"]*)\"\)$")
_VERSION = re.compile(r"^\tpublic static let current = (\d+)$")


@dataclass
class Field:
	name: str
	type: str
	default: str | None
	file: Path
	line: int

	@property
	def optional(self) -> bool:
		return self.type.endswith("?")

	@property
	def bare_type(self) -> str:
		return self.type[:-1] if self.optional else self.type


@dataclass
class Shape:
	name: str
	file: Path
	fields: list[Field] = field(default_factory=list)

	def field_named(self, name: str) -> Field | None:
		return next((f for f in self.fields if f.name == name), None)


@dataclass
class Vocabulary:
	"""``members`` maps the Swift member name to the string that travels."""

	name: str
	file: Path
	members: dict[str, str] = field(default_factory=dict)

	@property
	def values(self) -> set[str]:
		return set(self.members.values())


@dataclass
class Binding:
	shapes: dict[str, Shape] = field(default_factory=dict)
	vocabularies: dict[str, Vocabulary] = field(default_factory=dict)
	protocol_version: int | None = None

	def vocabularies_with(self, values: set[str]) -> list[str]:
		return sorted(name for name, vocab in self.vocabularies.items() if vocab.values == values)


def read_binding(root: Path) -> Binding:
	binding = Binding()
	for path in sorted(root.rglob("*.swift")):
		_read_file(path, binding)
	if not binding.shapes:
		raise BindingParseError(f"no wire shapes found under {root} -- has the binding moved?")
	return binding


def _read_file(path: Path, binding: Binding) -> None:
	shape: Shape | None = None
	vocabulary: Vocabulary | None = None
	for number, text in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
		if text == "}":
			shape, vocabulary = None, None
			continue

		if text.startswith("public "):
			shape, vocabulary = _open_declaration(text, path, number, binding)
			continue

		version = _VERSION.match(text)
		if version:
			binding.protocol_version = int(version.group(1))
			continue

		if shape is not None:
			_read_shape_line(shape, text, path, number, binding)
		elif vocabulary is not None:
			_read_vocabulary_line(vocabulary, text, path, number)


def _open_declaration(
	text: str, path: Path, number: int, binding: Binding
) -> tuple[Shape | None, Vocabulary | None]:
	struct = _STRUCT.match(text)
	if struct:
		shape = Shape(name=struct.group(1), file=path)
		binding.shapes[shape.name] = shape
		return shape, None

	enum = _ENUM.match(text)
	if enum:
		vocabulary = Vocabulary(name=enum.group(1), file=path)
		binding.vocabularies[vocabulary.name] = vocabulary
		return None, vocabulary

	kind = _TOP_LEVEL_PUBLIC.match(text)
	if kind and kind.group(1) in {"enum", "extension"}:
		# An enum with no raw type is a namespace, and an extension adds no wire shape.
		return None, None
	raise BindingParseError(
		f"{path}:{number}: top-level public declaration the drift gate does not know: {text!r}"
	)


def _read_shape_line(shape: Shape, text: str, path: Path, number: int, binding: Binding) -> None:
	static = _STATIC_VALUE.match(text)
	if static and static.group(2) == shape.name:
		vocabulary = binding.vocabularies.setdefault(shape.name, Vocabulary(name=shape.name, file=path))
		vocabulary.members[static.group(1)] = static.group(3)
		return

	if not text.startswith("\tpublic var "):
		return
	if "{" in text:
		# A computed property; no wire default contains a brace, so this cannot hide a stored one.
		return
	match = _PROPERTY.match(text)
	if match is None:
		raise BindingParseError(
			f"{path}:{number}: property in {shape.name} is not in the shape the drift gate reads: {text!r}"
		)
	shape.fields.append(
		Field(
			name=match.group(1),
			type=match.group(2).strip(),
			default=match.group(3).strip() if match.group(3) else None,
			file=path,
			line=number,
		)
	)


def _read_vocabulary_line(vocabulary: Vocabulary, text: str, path: Path, number: int) -> None:
	if not text.startswith("\tcase "):
		return
	case = _CASE.match(text)
	if case is None:
		raise BindingParseError(f"{path}:{number}: case in {vocabulary.name} is not readable: {text!r}")
	# No explicit raw value means the case name is the wire string.
	vocabulary.members[case.group(1)] = case.group(2) if case.group(2) is not None else case.group(1)
