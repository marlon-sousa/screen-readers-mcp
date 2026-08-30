# Tests for the generated wire JSON Schema. Stdlib + pytest only, desktop Python.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.

from __future__ import annotations

import dataclasses
from pathlib import Path
from typing import Any

import pytest

from screenreader_wire import protocol as p
from screenreader_wire import schema as s

#: The committed artifact, relative to this test file (repo/shared/tests/unit).
_COMMITTED = Path(__file__).resolve().parents[3] / "specs" / "wire" / "v1" / "schema.json"


def _defs(doc: dict[str, Any]) -> dict[str, Any]:
	defs: dict[str, Any] = doc["$defs"]
	return defs


# --- top-level shape ---------------------------------------------------------


def test_declares_the_2020_12_dialect_and_version() -> None:
	doc = s.build_wire_schema()
	assert doc["$schema"] == "https://json-schema.org/draft/2020-12/schema"
	assert doc["protocolVersion"] == p.PROTOCOL_VERSION


def test_every_command_appears_with_params_and_result() -> None:
	doc = s.build_wire_schema()
	commands: dict[str, Any] = doc["commands"]
	assert set(commands) == {c.value for c in p.Command}
	for name, entry in commands.items():
		assert "params" in entry and "result" in entry, name
		# Result is always a concrete shape (a $ref); params is a $ref or null.
		assert entry["result"].get("$ref"), name


def test_params_are_null_exactly_for_the_paramless_commands() -> None:
	doc = s.build_wire_schema()
	commands: dict[str, Any] = doc["commands"]
	null_params = {name for name, e in commands.items() if e["params"] is None}
	assert null_params == {
		"ping",
		"getLastSpeech",
		"getNextSpeechIndex",
		"getFocusInfo",
		"getState",
		# getLogPosition deliberately takes no params: it marks the present and
		# returns no records, so there is nothing to filter or anchor (spec 0021).
		"getLogPosition",
		# getGuidance deliberately takes no params either: the persona was fixed
		# at hello, and a `persona` argument would let a session consult a stance
		# it is not standing in (spec 0029 4.3).
		"getGuidance",
		"bye",
	}


def test_envelope_references_request_and_response() -> None:
	doc = s.build_wire_schema()
	assert doc["envelope"]["request"] == {"$ref": "#/$defs/Request"}
	assert doc["envelope"]["response"] == {"$ref": "#/$defs/Response"}


# --- per-shape correctness ---------------------------------------------------


def test_closed_enum_becomes_a_string_enum() -> None:
	mode = _defs(s.build_wire_schema())["HelloParams"]["properties"]["mode"]
	assert mode == {"type": "string", "enum": ["silent", "live"]}


def test_hello_result_reader_is_a_ref_and_capabilities_an_enum_array() -> None:
	hello = _defs(s.build_wire_schema())["HelloResult"]["properties"]
	assert hello["reader"] == {"$ref": "#/$defs/ReaderInfo"}
	assert hello["capabilities"] == {
		"type": "array",
		"items": {"type": "string", "enum": [c.value for c in p.Capability]},
	}


def test_optional_field_is_nullable_and_not_required() -> None:
	wait = _defs(s.build_wire_schema())["WaitForSpeechParams"]
	assert wait["properties"]["afterIndex"] == {
		"anyOf": [{"type": "integer"}, {"type": "null"}],
		"default": None,
	}
	# afterIndex and timeout have defaults; only text is required.
	assert wait["required"] == ["text"]


def test_required_lists_only_fields_without_defaults() -> None:
	# AckResult.ok has a default -> no required list at all.
	ack = _defs(s.build_wire_schema())["AckResult"]
	assert "required" not in ack
	# ReaderInfo's two fields have no defaults -> both required.
	assert _defs(s.build_wire_schema())["ReaderInfo"]["required"] == ["name", "version"]


# --- defaults, which are the half of a shape `required` cannot state ---------
#
# Board 13.3. A binding author reading only this document has to reproduce
# `graceMs == 100`, and until these tests existed the document did not say so
# while protocol.md §7.4 claimed it did.


def test_a_field_with_a_default_publishes_it() -> None:
	press = _defs(s.build_wire_schema())["PressGestureParams"]["properties"]
	assert press["graceMs"]["default"] == 100
	assert press["announce"]["default"] == ""


def test_a_required_field_publishes_no_default() -> None:
	press = _defs(s.build_wire_schema())["PressGestureParams"]["properties"]
	assert "default" not in press["gestures"]


def test_a_none_default_is_published_as_null_rather_than_omitted() -> None:
	# The distinction the sentinel exists for: `afterIndex` HAS a default and it
	# is None, which is not the same as having none.
	wait = _defs(s.build_wire_schema())["WaitForSpeechParams"]["properties"]
	assert wait["afterIndex"]["default"] is None


def test_a_default_factory_is_published_as_the_empty_container_it_makes() -> None:
	defs = _defs(s.build_wire_schema())
	assert defs["Request"]["properties"]["params"]["default"] == {}
	assert defs["HelloResult"]["properties"]["normalized"]["default"] == []


def test_an_enum_default_is_published_as_its_wire_string() -> None:
	snapshot = _defs(s.build_wire_schema())["DocumentSnapshotResult"]["properties"]
	assert snapshot["truncatedBy"]["default"] == "none"


def test_a_default_the_schema_cannot_render_raises_rather_than_vanishing() -> None:
	@dataclasses.dataclass
	class Unrenderable:
		trouble: list[int] = dataclasses.field(default_factory=lambda: [1])

	with pytest.raises(TypeError, match="trouble"):
		s._object_schema(Unrenderable, {})  # pyright: ignore[reportPrivateUsage]


def test_any_field_maps_to_the_empty_schema() -> None:
	# EchoParams.payload is Any -> accept anything.
	assert _defs(s.build_wire_schema())["EchoParams"]["properties"]["payload"] == {}


def test_objects_allow_additional_properties_for_forward_compat() -> None:
	# Mirrors from_dict ignoring extra keys: a newer peer's added field is fine.
	assert _defs(s.build_wire_schema())["HelloResult"]["additionalProperties"] is True


# --- determinism + the committed artifact ------------------------------------


def test_generation_is_deterministic() -> None:
	assert s.to_json(s.build_wire_schema()) == s.to_json(s.build_wire_schema())


def test_defs_keys_are_sorted() -> None:
	keys = list(_defs(s.build_wire_schema()))
	assert keys == sorted(keys)


def test_committed_schema_is_up_to_date() -> None:
	# The drift gate, as a test: regenerate and compare to the committed file.
	# read_text normalizes newlines on read, so this is EOL-agnostic; the CI
	# `git diff` step is the byte-level authority.
	generated = s.to_json(s.build_wire_schema())
	assert _COMMITTED.read_text(encoding="utf-8") == generated, (
		"specs/wire/v1/schema.json is stale; regenerate with "
		"`python -m screenreader_wire.schema > ../specs/wire/v1/schema.json`"
	)
