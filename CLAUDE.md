@AGENTS.md

## Claude Code

Everything above is [`AGENTS.md`](AGENTS.md), shared with every contributor and
every other agent, and it is the manual. Claude Code does not read `AGENTS.md`
on its own, so this file imports it — that import is the only reason the manual
reaches a Claude session at all, and it must stay at the top.

The manual is split by project: `shared/`, `server/` and `bridges/nvda/` each
carry their own `AGENTS.md`, and each is imported by a one-line `CLAUDE.md`
beside it, for exactly the reason this file exists. Those nested files load on
demand when you read something in that directory, so a session working on the
bridge picks up the bridge's rules without carrying the server's. The root
[`AGENTS.md`](AGENTS.md) stays self-contained, and its index names every one of
them — nothing is only reachable through a nested file.

Below is only what is specific to *this* client. The repository facts about
language servers — the three `pyrightconfig.json` files and which one wins, the
Go↔Python boundary, the cold-start truncation, pyright's missing "go to
implementation" — live in `AGENTS.md` under "Gotchas learned the hard way",
because they are true for any agent or editor and not just this one.

### If the `LSP` tool is available: navigate by symbol, not by grep

Ask the language server anything about a *symbol*: `goToDefinition`,
`findReferences`, `hover`, `workspaceSymbol`, `goToImplementation`,
`documentSymbol`, and `prepareCallHierarchy` / `incomingCalls` /
`outgoingCalls`. Keep Grep for *text* — log strings, config keys, Markdown,
build tags, `go:generate` lines.

**Before changing any exported name, signature or port interface, run
`findReferences` first.** That is the blast radius. This repo's ports are
implemented by hand-written stateful fakes as well as by real adapters, so a
grep that looks complete routinely misses the doubles — verified: the bridge's
`SpeechBuffer` has 69 references across 14 files, including `tests/fakes/` and
`tests/support/`.

**There is no `rename` operation** — the tool navigates, it does not edit. Every
call site is changed by hand, which is exactly why `findReferences` has to come
first, and why the three failure modes listed in `AGENTS.md` matter.

**If the tool is not in your session, stop here — Grep is the fallback and
nothing else in this repo changes.** Installing it is a personal choice; Go and
Python are all this repo needs:

```
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin install gopls-lsp@claude-plugins-official
claude plugin install pyright-lsp@claude-plugins-official
```

These require `gopls` and `pyright-langserver` on `PATH`. They are never a
build, test or CI dependency, and must not become one.
