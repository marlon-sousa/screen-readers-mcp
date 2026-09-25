# Generates the long document fixture for the document snapshot's live check.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     py -3.13 scripts/live_pages/make_long_page.py
# The check asks whether rendering a whole document holds NVDA's main thread, so the page must be long,
# and its paragraphs must wrap so browse-mode lines outnumber paragraphs. The output is gitignored.

from __future__ import annotations

from pathlib import Path

PARAGRAPHS = 600

SENTENCE = (
	"Paragraph number {n} of the long document, with enough words in it to make a realistic line of prose."
)


def build() -> str:
	parts = [
		"<!doctype html>",
		'<html lang="en">',
		'<head><meta charset="utf-8"><title>Long Document</title></head>',
		"<body>",
		"<h1>Long Document</h1>",
	]
	parts.extend(f"<p>{SENTENCE.format(n=n)}</p>" for n in range(1, PARAGRAPHS + 1))
	# A distinct final line shows the snapshot reached the end.
	parts.append("<p>The end of the long document.</p>")
	parts.append("</body>")
	parts.append("</html>")
	return "\n".join(parts) + "\n"


def main() -> None:
	target = Path(__file__).resolve().parent / "long-test.html"
	target.write_text(build(), encoding="utf-8")
	print(f"wrote {target} ({target.stat().st_size} bytes, {PARAGRAPHS} paragraphs)")


if __name__ == "__main__":
	main()
