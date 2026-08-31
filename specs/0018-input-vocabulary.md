# Spec 0018 — input vocabulary: gestures as command notation, and a `type` primitive

Status: **two parts, two lifetimes.**

- **Part A — gesture vocabulary.** *Decided and shipped (PR #41), validated live
  2026-07-25.* Board entry **E.2**.
- **Part B — the `type` primitive.** *Specified here, awaiting its own PR.* Board
  entry **E.3** (lane 1 + lane 2). No code yet.

Both answer one question: **how does an agent express input to a reader?** There
are two kinds of input, and conflating them is the mistake this spec removes —
*commands* (press a key or chord) and *literal text* (type a URL, a phrase).

## Part A — a gesture is the reader's user-facing command notation

### The problem it fixes

The wire carried gesture ids in NVDA's **inputCore identifier** form, and
`protocol.md`'s example was `"kb:NVDA+f7"`. That `kb:` is an *implementation*
detail — NVDA's internal source-namespace distinguishing a keyboard gesture from
a braille-routing or touch one. **No agent learns `kb:` from user-facing
documentation.** The NVDA User Guide writes `NVDA+F7`, `control+l`, `Escape` — a
prefixless key-combo notation.

This surfaced in the 11b run as two layers:

1. **A bug (E.1).** The bridge fed the `kb:`-prefixed id straight to
   `KeyboardInputGesture.fromName`, which wants the bare combo and raised
   `KeyError` on the `kb:` token. Every `pressGesture` failed.
2. **A design smell (this spec).** The tell: an agent that read only the User
   Guide would have sent `"NVDA+f7"` — and that **would have worked against the
   un-patched bridge**, because `fromName` parses exactly that. A
   source-privileged session (NVDA source checked out, the `kb:` example in the
   contract) reached for the internal form and hit the bug. The contract was
   asking for an identifier the agent's only legitimate source of truth never
   teaches.

### Decided

The reader-specific gesture vocabulary is the reader's **user-facing command
notation, as its own documentation writes it.** For NVDA: the User Guide
key-combo form — `NVDA+f7`, `control+l`, `escape`, `downArrow` — **prefixless.**

- **The server stays reader-agnostic.** It routes the string opaquely (spec 0005,
  principle 3); it neither parses nor understands it. The example it shows an
  agent is deliberately the user-facing form, not an internal id.
- **The reader-specific bridge maps it.** For NVDA that is
  `KeyboardInputGesture.fromName`, which already parses this notation
  (`keyboardHandler.py`: `windows` → `VK_WIN`, `nvda` → the NVDA modifier, single
  chars via `VkKeyScanEx`, the rest via `vkCodes`).
- **No English parser.** This is *not* natural language — "press down arrow"
  stays a job for the agent (the human↔agent layer), which translates intent to
  the reader's notation (the agent↔reader layer). The only residual gap is light
  normalization between how a manual *prints* a key (case, "Down Arrow") and what
  `fromName` accepts (`downArrow`); a deterministic normalizer, documented, never
  NLU.

### Compatibility and the reserved prefix

The bridge **tolerates** a legacy `kb:` inputCore prefix — E.1's pure
`bare_key_name` strips a `kb:` / `kb(layout):` source before `fromName`, so both
`NVDA+f7` and `kb:NVDA+f7` resolve. The **documented, canonical** form is
prefixless.

A source prefix is **reserved, not forbidden**: absent a prefix means *keyboard*,
and if a non-keyboard vocabulary ever arrives (braille cursor routing, touch), it
can carry its own explicit prefix. So the User-Guide form becomes the norm
without closing the door the `kb:` namespace was quietly holding open.

**The reservation was spent on 2026-08-31, by board entry 13.19 — and by the
mirror image of the case anticipated here.** The non-keyboard vocabulary that
arrived is not a new *kind* of gesture but a reader whose **default** vocabulary
is not the keyboard: VoiceOver's unprefixed ids are its own English command
names, so on that reader `h` is a command and `kb:h` is the letter key. Nothing
above changes for NVDA — the prefix stays tolerated and the documented form there
stays prefixless — and `protocol.md` §5 now states both halves.
See [spec 0049](0049-a-key-that-is-not-a-command.md).

### What shipped in PR #41

- `specs/wire/v1/protocol.md` — `pressGesture` wording + example rewritten to the
  prefixless User-Guide form, noting the bridge tolerates a legacy `kb:`.
- `server/domain/controllers/tools/press_gesture.go` — tool description, input
  schema example and the file header example, all prefixless.
- The bridge tolerance is E.1 (`bridge: strip the kb: source prefix before
  fromName`, `adapters/keyboard_gesture_name.py`).

### Validated live (2026-07-25)

Claude drove the desktop end to end in **both `live` and `silent` mode** using
only the prefixless form (`windows+d`, `rightArrow`/`leftArrow`, `windows+tab`,
`enter`): showed the desktop, enumerated icons, opened Task View, walked all
three windows, identified VS Code by "Visual Studio Code" at the **end** of the
title, and switched to it. Every gesture returned `pressed`, zero
`unknown gesture id`.

## Part B — the `type` primitive

### Motivation

Typing literal text is a different primitive from pressing a gesture, and the
project has already felt the gap: to enter `www.blindtec.com.br` the only tool was
`pressGesture`, one call per character. That is wrong on three counts — verbose,
semantically muddled (a URL is not a chord), and unreliable: single-character
gestures go through `VkKeyScanEx`, which fails for any character not on the
*current* keyboard layout (`@`, `.`, accented letters). The well-worn split is
Playwright's `press` (chord) vs `fill`/`type` (text); this adopts it.

The rest of Part B — the `typeText` command and `typing` capability, the Win32
`SendInput` Unicode injection, the observe-only interaction, the full class/file
layout, tests and live checklist — is promoted to its own implementation spec,
**[0019-type-primitive.md](0019-type-primitive.md)** (entry E.3). It lands and is
reviewed there, and rides in E.3's own PR; this section keeps only the motivation.

## Findings recorded from the 11b live runs

These shaped the spec and belong with it:

- **Same-machine feedback loop.** Driving from the same NVDA that is reading the
  Claude Code chat makes captures include the agent's own narration (the Elements
  List opened over the chat webview; `getSpeech` returned NVDA reading prior
  messages). Guidance: focus a real browser page, not the VS Code window running
  the agent. Noted in #41's `capture` checklist item.
- **Batched gestures coalesce speech.** Sending `["leftArrow","leftArrow"]` in one
  `pressGesture` makes NVDA interrupt the intermediate utterance, so only the
  final landing is captured. For reliable enumeration, one gesture per read. This
  is agent/driver guidance, not a bug.

## Definition of done

- **Part A:** done — the files above shipped in PR #41; headless suites, pyright,
  ruff, the schema drift gate and conformance green; validated live. Board entry
  **E.2** marked Done (PR #41).
- **Part B:** specified and delivered in **[spec 0019](0019-type-primitive.md)**,
  entry **E.3**, in its own PR.
