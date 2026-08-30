# What the Swift wire binding DECLARES, read out of its source.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: supporting construct -- a pure reader. It parses
# bridges/voiceover/Sources/ScreenReaderWire/ into shapes, fields and
# vocabularies; scripts/drift.py is what compares those with
# specs/wire/v1/schema.json and decides whether the difference is drift.
#
# WHY THIS IS PARSED RATHER THAN GENERATED OR REFLECTED:
#   * Generated is refused by spec 0043 -- the Swift binding is HAND-WRITTEN, and
#     spec 0046 records the alternative and declines it: a second generator is a
#     second thing to maintain.
#   * Reflected would need a Swift toolchain, and this gate runs in the `shared`
#     CI job, on a host that has none. A gate that can only run on macOS is a
#     gate that reports after the fact for everyone else.
# So it reads the text, and the price is that the binding must be written in a
# predictable shape. That price is paid once, here, and stated out loud:
#
# THE STYLE CONTRACT THIS READER DEPENDS ON, all of it already the house style:
#   1. A wire shape is `public struct NAME` starting at column 0.
#   2. A closed vocabulary is `public enum NAME: String` at column 0.
#   3. A stored property is ONE TAB, then `public var name: Type`, with an
#      optional ` = default`. Anything more deeply indented is inside a nested
#      type or a function body and is not a wire field.
#   4. A declaration ends at a line that is exactly `}` at column 0.
#
# AND THE RULE THAT MAKES IT SAFE: this reader NEVER shrugs at the lines it is
# responsible for. A `public var` inside a shape that it cannot split, a `case`
# inside a vocabulary that it cannot read, or a top-level `public` declaration of
# a kind it does not know -- each RAISES. A drift gate that silently skips what
# it does not understand reports green about the half it managed to read, which
# is worse than no gate at all, because somebody believes it.

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path


class BindingParseError(Exception):
	"""The binding is not in the shape this reader can read. Never swallowed."""


#: `public struct Foo: Codable, Equatable, Sendable {` at column 0.
_STRUCT = re.compile(r"^public struct (\w+)\b")
#: `public enum Foo: String, Codable, ... {` at column 0 -- a raw-value enum, so
#: a closed wire vocabulary. An enum with no raw type declares none.
_ENUM = re.compile(r"^public enum (\w+): String\b")
#: Any other top-level public declaration, which this reader refuses rather than
#: passes over -- including `public typealias`, the re-export facade the repo
#: bans outright.
_TOP_LEVEL_PUBLIC = re.compile(r"^public (\w+)")
#: One tab, then a stored property.
_PROPERTY = re.compile(r"^\tpublic var (\w+): ([^={\n]+?)(?: = (.+))?$")
#: One tab, then `case name` or `case name = "wire"`.
_CASE = re.compile(r"^\tcase (\w+)(?: = \"([^\"]*)\")?$")
#: One tab, then a static member of a vocabulary that is a STRUCT rather than an
#: enum -- Capability, whose unknown values must be retained rather than refused.
_STATIC_VALUE = re.compile(r"^\tpublic static let (\w+) = (\w+)\(rawValue: \"([^\"]*)\"\)$")
#: `public static let current = 1`, the version the binding was written against.
_VERSION = re.compile(r"^\tpublic static let current = (\d+)$")


@dataclass
class Field:
	"""One stored property of a wire shape, exactly as the source declares it."""

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
	"""A `public struct` that renders one `$defs` entry of the contract."""

	name: str
	file: Path
	fields: list[Field] = field(default_factory=list)

	def field_named(self, name: str) -> Field | None:
		return next((f for f in self.fields if f.name == name), None)


@dataclass
class Vocabulary:
	"""A closed (or, for Capability, a known) set of wire strings.

	``members`` maps the Swift member name to the string that travels, because a
	default is written as ``.memberName`` while the schema states the string.
	"""

	name: str
	file: Path
	members: dict[str, str] = field(default_factory=dict)

	@property
	def values(self) -> set[str]:
		return set(self.members.values())


@dataclass
class Binding:
	"""Everything the drift gate needs to know about the Swift source."""

	shapes: dict[str, Shape] = field(default_factory=dict)
	vocabularies: dict[str, Vocabulary] = field(default_factory=dict)
	protocol_version: int | None = None

	def vocabularies_with(self, values: set[str]) -> list[str]:
		"""Names of the vocabularies whose members are exactly ``values``."""
		return sorted(name for name, vocab in self.vocabularies.items() if vocab.values == values)


def read_binding(root: Path) -> Binding:
	"""Parse every Swift file under ``root`` into a Binding, or raise."""
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
		# `public enum` with no raw type is a namespace (ProtocolVersion), and a
		# `public extension` adds no wire shape. Both carry nothing to compare.
		return None, None
	raise BindingParseError(
		f"{path}:{number}: top-level public declaration the drift gate does not know: {text!r}"
	)


def _read_shape_line(shape: Shape, text: str, path: Path, number: int, binding: Binding) -> None:
	static = _STATIC_VALUE.match(text)
	if static and static.group(2) == shape.name:
		# A vocabulary whose members are static values of its own struct type.
		vocabulary = binding.vocabularies.setdefault(shape.name, Vocabulary(name=shape.name, file=path))
		vocabulary.members[static.group(1)] = static.group(3)
		return

	if not text.startswith("\tpublic var "):
		return
	if "{" in text:
		# A computed property (`public var isKnown: Bool { ... }`) stores nothing
		# and travels nowhere; it is not a wire field. No wire default contains a
		# brace, so this cannot hide a stored one.
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
	# No explicit raw value means the case name IS the wire string -- Swift's own
	# rule, and the reason the binding writes the common case that way.
	vocabulary.members[case.group(1)] = case.group(2) if case.group(2) is not None else case.group(1)
