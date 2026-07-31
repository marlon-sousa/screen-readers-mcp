# Generated-artifact drift gates.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     uv run poe gates
#
# Two artifacts in this repo are GENERATED from shared/nvda_mcp_wire/protocol.py
# and committed: the JSON schema both languages are described by, and the Go
# binding the server decodes with. Committing a generated file is only safe if
# something proves it still matches its source -- otherwise the two sides drift
# and the first symptom is a decode failure in the conformance tier, or worse,
# a field that silently stops round-tripping.
#
# Both gates ask the same question: "does regenerating change anything?" A
# non-empty answer is a failure, and the fix is always to regenerate and commit,
# never to edit the artifact.
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

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "specs" / "wire" / "v1" / "schema.json"
BINDING = ROOT / "server" / "adapters" / "wire" / "wire.gen.go"


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
			"import json;from nvda_mcp_wire.schema import build_wire_schema;"
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
	args = parser.parse_args()
	# Neither flag means both, so the bare invocation keeps its old meaning.
	both = not (args.schema or args.binding)

	ok = True
	if both or args.schema:
		ok = schema_gate() and ok
	if both or args.binding:
		ok = binding_gate() and ok
	print()
	if not ok:
		print("Drift detected. A generated artifact no longer matches its source.")
		return 1
	print("No drift: every gate that ran matches its source.")
	return 0


if __name__ == "__main__":
	sys.exit(main())
