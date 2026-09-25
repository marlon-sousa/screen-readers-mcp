---
name: strip-comments
description: Strip comments from this repo's Go, Python or Swift under the "comments say what the code cannot" rule in AGENTS.md. Use for a lane 4 board entry (14.1 NVDA bridge, 14.2 VoiceOver bridge, 14.3 server, 14.4 scripts), when adding a new code directory (it needs a comment area), when asked to strip or reduce comments in a file or area, when `poe gate-comments` fails, or when reviewing a diff whose comments cite specs, dates or history.
---

# Stripping comments

The rule is in [AGENTS.md](../../../AGENTS.md), "Comments say what the code cannot". Read
it first. This skill is the procedure and the rubric that applies the rule line by line.

## The rubric

Put each comment paragraph (a docstring counts) in exactly one bucket.

Delete:

- N1 citation: "(spec 0032)", "board entry 11.6", "lane 1's", "Decided", "per the
  workflow rule". Delete the citation. If the sentence around it is a K fact, keep the
  sentence without it.
- N2 history: "since 13.25", "until", "used to", "was", "renamed from", a date, "SPEC
  AMENDMENT (rides in 10a)". Delete.
- N3 rejected alternative: "rather than", "not X because", "the other way would have".
  Delete, unless it is the only statement of a hazard; then keep the hazard in one
  sentence, naming no alternative.
- N4 restates the code: a paragraph on a field, parameter, variant, method or import
  that says what its name and type already say.
- N5 architecture justification: why ports are separate, why a controller is thin, why
  one class per file. AGENTS.md says it once.
- N6 rhetoric: capitalised theses, bold, "the point is", "which is the whole reason",
  cross-references to another file's reasoning, a second statement of a fact.
- N7 test narration: a comment above a test that paraphrases its name or walks through
  its assertions. If the name cannot carry the intent, rename the test.

Keep, compressed to one plain sentence each:

- K1 module header: the `ROLE:`, `IMPLEMENTED BY:`, `BUILT BY:`, `USED BY:` lines, one
  sentence each, citations removed. Delete every paragraph after them that is not K2 to
  K4.
- K2 measured fact: what, against which program and version (NVDA 2026.1, macOS 15,
  VoiceOver on macOS 15), and the value. No date, no story of how it was found.
- K3 invariant or hazard the code does not enforce: main-thread rules, the synth
  restore in a `finally`, drop and close order, a reference kept alive on purpose,
  cancellation safety.
- K4 what an absent value, an error or a rejection carries.
- K5 test intent, only when renaming cannot carry it.
- K6 licence, tooling and generated-file headers, `# noqa`, `# pyright:`, `//go:build`,
  `//go:embed`, `//go:generate`, `// swiftlint:` and similar directives: unchanged. They
  are not prose; never touch them.

The tie-break: could a competent engineer with AGENTS.md and the specs work it out from
the code in a few minutes? Then delete. If genuinely unsure, keep the one sentence that
states the fact.

Rewrite capitals used for emphasis ("NIL IS NOT FALSE") in normal case. Keep capitals
that are names: `ROLE:`, `SAFETY:`, `TODO:`, acronyms.

## For each file

1. Read it top to bottom. Name every paragraph's bucket. Do not skip a long paragraph;
   the long ones are the point.
2. Delete N paragraphs whole. Compress K paragraphs to one sentence. A kept fact appears
   once in the repository; a second place says "see" with a path.
3. A comment that contradicts the code: delete it if N, correct it if K. Never change
   code to match a comment. Record it for the PR body under "found while stripping".
4. Change no line that is not a comment or a docstring, with three exceptions: renaming
   a test whose narration you deleted (the name only, and every reference to it);
   `pass` or `...` where deleting a docstring would leave a Python body empty; and what
   `gofmt`, `ruff format` or `swift-format` reflow. Never keep a comment only to hold a
   layout still.
5. Python: a module or function left with no docstring is fine; ruff does not require
   one. Keep a script's module docstring when `argparse` or `--help` prints `__doc__`.
6. Go: exported identifiers need no doc comment here; no linter asks for one.

## Before opening the PR

1. `python scripts/comments.py $(git ls-files <area> | rg '\.(py|go|swift)$')` before and
   after, for the PR body. Only formatter reflow may change the code count.
2. In the root `pyproject.toml`, set the area's `enforced = true` and its `ceiling` to
   the next multiple of 0.05 strictly above the measured ratio, so a few new files do not trip it. If an open PR touches files in the
   area, leave those files unstripped, list them in `pending`, and name the PR.
3. `uv run poe dev`, captured to a log and run once. Red means a non-comment line moved,
   or the gate found a citation; fix it and run again.
4. Flip the entry to Done on the board, in lane 4 only.

## PR body

- The counts before and after, per area.
- "No non-comment line changed", or the list of test renames and of formatter reflows.
- "Found while stripping": each comment that contradicted the code, with file and line,
  or "none".
- Files left in `pending`, and why.
