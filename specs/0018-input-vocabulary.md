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

### Wire and capability

- **New command** `typeText { text: string } → { ok: true }` — type the literal
  text into whatever holds focus, blocking until it has been injected. `text`
  passes through opaquely; it is content, not vocabulary, so there is nothing
  reader-specific about it.
- **New capability** `typing`, advertised in `hello`. The server gates the tool
  on it exactly as `pressGesture` is gated on `gestures`: a bridge that does not
  announce `typing` never gets the tool advertised.
- **Observe-only (spec 0017) withholds it.** `typeText` moves the user's machine,
  so its handler is `mutates_reader = True` and the server withholds the `typing`
  port on an `observe` session — the same machinery that withholds `gestures`.

### Bridge implementation

Inject the text with Win32 **`SendInput` + `KEYEVENTF_UNICODE`**, one synthesized
Unicode code unit per character. This is layout-independent and handles arbitrary
characters, unlike routing each character through `KeyboardInputGesture`. It runs
on NVDA's main thread and blocks until done, mirroring `NvdaGestureSender`'s
`wx.CallAfter` + `Event` marshaling, so "the call returned" means "the text
reached the focused control." Same focus contract as `pressGesture`: the agent
focuses the field first (`control+l`), then `typeText`, then
`pressGesture ["enter"]`.

### Class/file layout

**Shared**

1. **`shared/nvda_mcp_wire/protocol.py`** — `TypeParams` (`text: str`), its entry
   in `COMMAND_SHAPES`, and `Capability.TYPING`.

**Bridge**

2. **`domain/ports/text_typer.py`** — `TextTyper` port (`type_text(text: str)`)
   and its `TypeError`-style failure, beside `gesture_sender.py`.
3. **`domain/controllers/commands/type_text.py`** — `TypeTextHandler`, decodes
   `TypeParams`, calls the port, logs a transcript `("type", text)` entry;
   `mutates_reader = True`.
4. **`domain/controllers/commands/registry.py`** — advertise `Capability.TYPING`
   when the typer is present; register the handler.
5. **`adapters/nvda_text_typer.py`** — the `SendInput`/`KEYEVENTF_UNICODE`
   adapter (NVDA/ctypes; on pyright's ignore list, validated by the live
   checklist).
6. **`adapters/nvda_adapter_factory.py`** — build the `NvdaTextTyper`.
7. **`domain/controllers/session.py`** — no new dispatch, but the observe gate
   already refuses `mutates_reader` handlers, so `typeText` is covered for free.

**Server**

8. **`domain/entities/capability.go`** — the `typing` capability constant + its
   handshake mapping, beside `gestures`.
9. **`domain/ports/…`** + `ToolContext.Text()` — a `TextTyper` port handed over
   only when the reader announced `typing`.
10. **`adapters/bridge/json_lines_client.go`** — a `TypeText(text)` method.
11. **`domain/controllers/tools/type_text.go`** — the `type_text` tool, gated on
    `typing`, description saying it is for literal text (and pointing at
    `press_gesture` for keys).
12. **`domain/controllers/tools/registry.go`** — the registry line.

**Wire binding** — regenerated both sides from `schema.json` (adds `TypeParams`,
the `typeText` command, the `typing` capability); the drift gate keeps them in
step.

**Fakes** — a fake `TextTyper` (bridge) recording typed strings, beside the fake
gesture sender.

### Tests

- **Bridge unit** — `TypeTextHandler` types the string through a fake typer and
  logs it; the handler enumeration test (spec 0017) asserts `mutates_reader` is
  `True`.
- **Wire scenario** — a session typing text end to end over the fake bridge.
- **Server** — `type_text` advertised only when `typing` is announced; withheld
  on an `observe` session.
- **Conformance** — the real Python bridge types a known string into a focused
  control, read back through `getFocusInfo`/`getSpeech`.

### Live-NVDA checklist (the Part B PR's body)

1. Focus a text field, `typeText "hello world"`, read it back — matches.
2. Focus Chrome's address bar (`control+l`), `typeText "www.blindtec.com.br"`,
   `pressGesture ["enter"]` — the page loads.
3. A string with punctuation and an accented character types correctly regardless
   of keyboard layout.
4. On an `observe` session, `type_text` is absent from the tool list and refused
   if called anyway — no character reaches the machine.

### Out of scope

- Clipboard paste, IME composition, and per-keystroke timing control — `typeText`
  is atomic literal insertion.
- Rich key sequences mixing text and chords in one call; compose them from
  `typeText` + `pressGesture`.

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
- **Part B:** the `type` files above, both headless suites and conformance green,
  and its live checklist run with the tester at the keyboard — in its **own** PR
  (entry **E.3**).
