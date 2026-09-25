# Comment gate: counts comment lines against code lines, and fails on what AGENTS.md keeps out of code.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     python scripts/comments.py [path ...]    one line per file, then the total
#     python scripts/comments.py --check       enforce every enforced area in pyproject.toml
#
# A Python docstring counts as comment. A line holding both code and a comment counts as code.

from __future__ import annotations

import ast
import io
import re
import subprocess
import sys
import tokenize
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUFFIXES = (".py", ".go", ".swift")
GENERATED = (".gen.go",)

FORBIDDEN = [
	(re.compile(r"\b(?:specs?|rfc)\s*/?\s*0\d{3}\b", re.IGNORECASE), "cites a spec"),
	(re.compile(r"\bspec amendment\b", re.IGNORECASE), "cites a spec"),
	(re.compile(r"\b(?:board|roadmap)\b", re.IGNORECASE), "cites the board"),
	(re.compile(r"\bentr(?:y|ies) \d+(?:\.\d+)?[a-z]?\b", re.IGNORECASE), "cites a board entry"),
	(re.compile(r"\blane \d\b", re.IGNORECASE), "cites a board lane"),
	(re.compile(r"\bmilestone\b", re.IGNORECASE), "cites a milestone"),
	(re.compile(r"\bdecision \d+", re.IGNORECASE), "cites a decision"),
	(re.compile(r"\bDecided\b"), "cites a decision"),
	(re.compile(r"\b20\d\d-\d\d-\d\d\b"), "carries a date"),
	(re.compile(r"\*\*\S"), "uses bold"),
]


@dataclass
class Count:
	comment: int = 0
	code: int = 0
	comments: list[tuple[int, str]] = field(default_factory=lambda: [])


def count_python(source: str) -> Count:
	lines = source.splitlines()
	comment_text: dict[int, list[str]] = {}
	code_lines: set[int] = set()
	docstring_lines: set[int] = set()
	tree = ast.parse(source)
	for node in ast.walk(tree):
		if isinstance(node, ast.Module | ast.ClassDef | ast.FunctionDef | ast.AsyncFunctionDef) and node.body:
			first = node.body[0]
			if (
				isinstance(first, ast.Expr)
				and isinstance(first.value, ast.Constant)
				and isinstance(first.value.value, str)
				and first.end_lineno is not None
			):
				for number in range(first.lineno, first.end_lineno + 1):
					docstring_lines.add(number)
					comment_text.setdefault(number, []).append(lines[number - 1])
	ignored = {tokenize.NL, tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT, tokenize.ENDMARKER}
	for token in tokenize.generate_tokens(io.StringIO(source).readline):
		if token.type == tokenize.COMMENT:
			comment_text.setdefault(token.start[0], []).append(token.string)
		elif token.type not in ignored and token.start[0] not in docstring_lines:
			code_lines.update(range(token.start[0], token.end[0] + 1))
	return _tally(lines, comment_text, code_lines)


def count_c_like(source: str, *, go: bool) -> Count:
	lines = source.splitlines()
	comment_text: dict[int, list[str]] = {}
	code_lines: set[int] = set()
	line = 1
	i = 0
	n = len(source)
	while i < n:
		ch = source[i]
		if ch == "\n":
			line += 1
			i += 1
		elif ch in " \t\r":
			i += 1
		elif source.startswith("//", i):
			end = source.find("\n", i)
			end = n if end == -1 else end
			comment_text.setdefault(line, []).append(source[i:end])
			i = end
		elif source.startswith("/*", i):
			end = source.find("*/", i + 2)
			end = n if end == -1 else end + 2
			for offset, text in enumerate(source[i:end].split("\n")):
				comment_text.setdefault(line + offset, []).append(text)
			line += source.count("\n", i, end)
			i = end
		else:
			start_line = line
			if not go and source.startswith('"""', i):
				end = source.find('"""', i + 3)
				end = n if end == -1 else end + 3
			elif go and ch == "`":
				end = source.find("`", i + 1)
				end = n if end == -1 else end + 1
			elif ch == '"' or (go and ch == "'"):
				end = i + 1
				while end < n and source[end] != ch and source[end] != "\n":
					end += 2 if source[end] == "\\" else 1
				end = min(end + 1, n)
			else:
				end = i + 1
			line += source.count("\n", i, end)
			code_lines.update(range(start_line, line + 1))
			i = end
	return _tally(lines, comment_text, code_lines)


def _tally(lines: list[str], comment_text: dict[int, list[str]], code_lines: set[int]) -> Count:
	result = Count()
	for number, text in enumerate(lines, 1):
		if not text.strip():
			continue
		if number in code_lines:
			result.code += 1
		elif number in comment_text:
			result.comment += 1
	for number in sorted(comment_text):
		result.comments.append((number, " ".join(comment_text[number])))
	return result


def count(path: Path) -> Count:
	source = path.read_text(encoding="utf-8", errors="replace")
	if path.suffix == ".py":
		return count_python(source)
	return count_c_like(source, go=path.suffix == ".go")


def tracked() -> list[str]:
	files = subprocess.check_output(["git", "ls-files"], text=True, cwd=ROOT).split()
	return [f for f in files if f.endswith(SUFFIXES) and not f.endswith(GENERATED)]


def ratio(comment: int, code: int) -> float:
	return comment / max(code, 1)


def summary(label: str, result: Count) -> str:
	per_line = ratio(result.comment, result.code)
	return f"{label}: {result.comment} comment, {result.code} code, {per_line:.2f} per code line"


def report(paths: list[str]) -> None:
	total = Count()
	for path in paths:
		result = count(ROOT / path)
		total.comment += result.comment
		total.code += result.code
		print(summary(path, result))
	print(summary("TOTAL", total))


def check() -> int:
	config = tomllib.loads((ROOT / "pyproject.toml").read_text(encoding="utf-8"))
	areas = config["tool"]["screen-readers-mcp"]["comments"]
	files = tracked()
	failures: list[str] = []
	for name, area in areas.items():
		if not area.get("enforced", False):
			print(f"SKIP {name}: not stripped yet")
			continue
		pending = set(area.get("pending", []))
		members = [f for f in files if any(f.startswith(p.rstrip("/") + "/") for p in area["paths"])]
		total = Count()
		for path in members:
			result = count(ROOT / path)
			total.comment += result.comment
			total.code += result.code
			if path in pending:
				continue
			for number, text in result.comments:
				for pattern, reason in FORBIDDEN:
					if pattern.search(text):
						failures.append(f"{path}:{number}: comment {reason}: {text.strip()[:100]}")
		value = ratio(total.comment, total.code)
		verdict = "OK" if value <= area["ceiling"] else "FAIL"
		print(f"{verdict} {name}: {value:.3f} comment lines per code line, ceiling {area['ceiling']}")
		if verdict == "FAIL":
			failures.append(f"{name}: {value:.3f} is above its ceiling of {area['ceiling']}")
	for failure in failures:
		print(failure)
	if failures:
		print("See AGENTS.md, 'Comments say what the code cannot'.")
	return 1 if failures else 0


def main(argv: list[str]) -> int:
	if argv == ["--check"]:
		return check()
	report(argv or tracked())
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
