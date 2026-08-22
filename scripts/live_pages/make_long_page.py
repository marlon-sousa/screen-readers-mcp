# Generates the long document fixture for spec 0026's live checklist, item 9.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     py -3.13 scripts/live_pages/make_long_page.py
#
# WHY THIS IS GENERATED AND NOT COMMITTED. The page is 66 KB of `Paragraph number
# N`, and a six-line generator is a better artefact than sixty thousand
# characters nobody will read: a reviewer can see what the fixture IS, and a
# tester who wants a different size changes a number instead of a file. The
# output is gitignored.
#
# WHY 600 PARAGRAPHS. It is the smallest size that answers item 9's question
# honestly. The question is whether rendering a WHOLE document holds NVDA's main
# thread long enough to matter, and a page that fits on a screen cannot answer it
# -- the render has to be long enough that, if the cost were linear and
# significant, it would show. Measured on 2026-08-22 this wraps to 1103 buffer
# LINES (browse mode wraps a long paragraph, so lines outnumber paragraphs) and
# 60 KB of result, and the render was not measurably slower than a one-line one.
#
# That 60 KB is itself a finding, and the reason this fixture is worth keeping:
# it is large enough to overflow a calling agent's context budget, which is what
# the tool description's note about `maxLines` exists to warn about. A smaller
# page would hide the one real cost of "the whole document by default".

from __future__ import annotations

from pathlib import Path

#: Enough to make a slow render visible if there were one. See the header.
PARAGRAPHS = 600

#: Long enough that browse mode wraps it, so the fixture exercises the
#: distinction between a paragraph and a BUFFER LINE -- which is what the
#: snapshot reports, and which a one-line-per-paragraph page would never show.
SENTENCE = (
	"Paragraph number {n} of the long document, with enough words in it to make a realistic line of prose."
)


def build() -> str:
	"""Render the whole page as one string."""
	parts = [
		"<!doctype html>",
		'<html lang="en">',
		'<head><meta charset="utf-8"><title>Long Document</title></head>',
		"<body>",
		"<h1>Long Document</h1>",
	]
	parts.extend(f"<p>{SENTENCE.format(n=n)}</p>" for n in range(1, PARAGRAPHS + 1))
	# A distinct final line, so a tester can see the snapshot reached the END
	# rather than stopping somewhere plausible.
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
