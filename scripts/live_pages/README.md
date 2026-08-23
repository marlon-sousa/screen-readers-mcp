# Live-test pages

Fixtures for the **manual live-NVDA checklists** that ride in pull request
bodies. They are opened in a browser on the machine under test, and then driven
through the MCP exactly as any other application would be — see
[`CONTRIBUTING.md`](../../CONTRIBUTING.md), "Setting up to test against a live
NVDA".

**These are versioned on purpose, and so is the next one somebody makes.** The
rule is in [`AGENTS.md`](../../AGENTS.md) under the workflow section: a page a
live checklist depends on belongs here, in the same PR as the checklist. It is
recorded because the first version of these pages were scratch files in a
session's temp directory, and the PR that cited them was left claiming a
measurement nobody else could reproduce.

## What is here, and which checklist item each page serves

| Page | Serves | Why it looks like that |
|---|---|---|
| `snapshot-test.html` | Spec 0026, items 1–8; spec 0037, item 4 | Heading levels, links, a radio group, and a **five-item list**. Every element is load-bearing; the file's own comment says what each one proves. 0037 reuses it for a different property entirely — its `<title>` is "Snapshot Test Page", so NVDA+t speaks a known phrase and a `run_sequence` plan can wait for a word of it. **Do not rename the title** without fixing that checklist. |
| `dynamic-test.html` | Spec 0026, item 10 | Appends a line every five seconds, so "a snapshot is one instant" can be observed rather than asserted. |
| `make_long_page.py` → `long-test.html` | Spec 0026, item 9 | 600 paragraphs, which browse mode wraps to ~1100 buffer lines. Generated rather than committed: 66 KB of `Paragraph number N` is not a reviewable artefact. Run `py -3.13 scripts/live_pages/make_long_page.py`. |

The list in `snapshot-test.html` is the one to be careful about deleting. It is
what caught the 2026-08-22 defect: the snapshot was welding a list-**exit**
transition onto line 0 whenever the caret sat inside that list, and a page
without a list passes the whole checklist without noticing.

## The limit: these are fixtures, NOT golden files

**Do not commit expected output next to them, and do not compare a snapshot to
a string recorded on another machine.**

What comes back is rendered through the reader's own speech layer, under *that
machine's* locale, verbosity and document-formatting settings. The 2026-08-22
run read `título nível 1`, `botão de opção marcado Portuguese` and `lista com 5
itens`, because that machine runs NVDA in `pt_BR`. The same fixture on an
English machine returns different strings — and that is the feature, not a
defect: "exactly as it appears on the buffer" means *this user's* buffer.

So the comparison that actually holds is the one that never leaves the machine:
**take a snapshot, then arrow through the same lines in the same session, and
check that the words agree.** That is spec 0026's checklist item 2, and it is
locale-independent by construction. Anything you record here about *content*
is a note for a human reader, not an assertion.
