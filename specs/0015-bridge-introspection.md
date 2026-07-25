# Spec 0015 — bridge: introspection (entry 11.1)

Status: **agreed 2026-07-25; ready to implement.** No code written yet. NVDA
APIs below were read from `../nvda/source` (2026.1) before writing, per
AGENTS.md.

Covers board entry 11.1: the four introspection commands the wire has defined
since v1 and the NVDA bridge has never served.

## Goal

Let an agent ask *where it is* and *what mode the reader is in*, not only *what
was said* — and read and write the reader's own configuration.

## The gap is entirely bridge-side

The server half shipped in 10b and is complete: `JSONLinesClient.FocusInfo()`,
`.State()`, `.GetConfig()` and `.SetConfig()` exist; `ports.FocusInspector`,
`.StateInspector` and `.ConfigAccessor` exist; `get_focus_info`, `get_state`,
`get_config` and `set_config` exist and are listed in `BuildRegistry`; the
handshake already hands out the three ports when the reader announces them, and
the capability gate already covers them.

The bridge is where it stops:

- `domain/controllers/commands/registry.py` maps all four commands to
  `NotImplementedHandler`, which raises a clean `CommandError` — "not yet"
  rather than "never", deliberately, so a newer server degrades gracefully.
- `NVDA_CAPABILITIES` is `(SPEECH, BRAILLE, GESTURES, ANNOUNCE)`, so the bridge
  does not advertise `focus`, `state` or `config`, and the server correctly
  never advertises the four tools.

So **this entry is lane 1 only, and it changes no server file and no wire
file.** The last line of it — widening `NVDA_CAPABILITIES` — is what lights up
four already-built, already-tested tools on the other side. That property is
worth preserving as a check on the design: if this entry finds itself editing
`server/`, something has been designed twice.

## Decided

### Three ports, not four handlers reaching NVDA directly

`getConfig` and `setConfig` are one capability group (`config`) and one port;
`getFocusInfo` and `getState` are separate groups and separate ports. That
mirrors the server's port split exactly, and it is the wire's own grouping
(protocol.md §4), so the two sides stay describable in one vocabulary.

### Role and state names cross the wire as stable enum names, not display strings

`controlTypes.Role` and `controlTypes.State` are `DisplayStringIntEnum`, so each
member offers both `.name` (`"BUTTON"`, `"EDITABLETEXT"`, `"CHECKED"`) and
`.displayString` (localized: "button", "botão", …).

**Send `.name`.** The wire says role and state strings are reader-specific and
pass through opaquely, and an agent asserts on them. A localized display string
would make the same assertion pass or fail depending on the tester's NVDA
language, which is exactly the class of flakiness this project exists to remove.
The display string is the *user's* vocabulary; the enum name is the *contract's*.

An unrecognized role (a raw int NVDA has no member for) is sent as its decimal
string rather than dropped — honest, and it cannot raise.

### `browseMode` is derived, and is a tri-state

There is no `browseMode` flag in NVDA. Browse mode is the condition "the focus
object has a tree interceptor that is not passing through": NVDA's own
`browseMode.reportPassThrough` reads `treeInterceptor.passThrough`.

So the value is one of:

- `"browse"` — the focus has a `TreeInterceptor` and `passThrough` is false.
- `"focus"` — the focus has a `TreeInterceptor` and `passThrough` is true (focus
  mode inside a browsable document).
- `"none"` — the focus has no tree interceptor at all, so neither mode applies.
  A plain Win32 dialog is not "not in browse mode"; the question does not arise
  there, and collapsing that to a falsy value would make a diff across a gesture
  read as a mode change when nothing changed.

**Decided: a string enum, not a nullable bool.** `StateResult.browseMode`
becomes `"browse" | "focus" | "none"` rather than `bool | null`. This is a
*wider* wire change than admitting null on the existing bool — but nothing has
shipped either shape yet (no bridge has ever served this field), so "smaller
diff" buys nothing real, and the null-admitting bool has a sharper problem:
`false` would carry the specific meaning "focus mode inside a document",
distinct from `null`'s "no such concept here" — exactly the ambiguity a naive
`if not result.browseMode` collapses, which this project's whole premise
argues against. The enum also matches `speechMode` in the same `StateResult`,
and every role/state string elsewhere in this contract, all sent as named
strings rather than a boolean. This is the one place this entry touches
`shared/nvda_mcp_wire/protocol.py`; it regenerates `schema.json`, so it is the
one part of this entry the drift gate and the conformance job will see.

### The other three state values

- `speechMode` — `speech.getState().speechMode.name`, one of `off`, `beeps`,
  `talk`, `onDemand` (`speech/speech.py:114`, re-exported from
  `speech/__init__.py`). Sent as the member name for the same reason as roles.
- `sleepMode` — `api.getFocusObject().sleepMode` (`NVDAObjects/__init__.py:1573`,
  derived from `appModule.sleepMode`). A bool.
- `inputHelp` — `inputCore.manager.isInputHelpActive` (`inputCore.py:624`). A
  bool. This one earns its place: with input help on, every gesture is *described*
  instead of *performed*, so an agent whose `pressGesture` calls have silently
  stopped doing anything can find out why in one call.

### `setConfig` never persists to disk, and is restored at teardown

**Decided.** This was flagged as the decision most worth arguing about; it
stands as proposed, unchanged.

`config.conf` is NVDA's live `ConfigManager`. Writing to it changes the running
reader immediately; calling `.save()` would change the tester's NVDA
permanently.

The rule: **never call `save()`**, and record each key's prior value on first
write so that session teardown restores every key this session touched, on every
exit path. The precedent is exact — spec 0009's `logLevel` raises NVDA's own log
verbosity for the session and restores it at teardown, for the same reason:
an agent's session is an experiment, and an experiment that permanently
reconfigures a blind person's screen reader because it crashed halfway is not
acceptable. This is the same family as the invariant that a crashed harness must
never leave a user mute.

Never calling `save()` is also what makes the restore robust against the case
restoration *can't* run at all: a hard kill of the NVDA process itself needs no
cleanup code, because the unsaved in-memory change dies with the process.
Restore-at-teardown only has to cover the case this entry actually targets —
the session ending while NVDA keeps running — which is exactly what the
session's existing teardown machinery already handles for other state.

Consequence to state plainly: an agent cannot use `setConfig` to make a durable
change, by design. If a durable change is ever wanted it should be an explicit,
separately-named command, not a side effect of a test tool.

`keyPath` is opaque to the server and validated only by NVDA: a bad path or a
value the confspec rejects becomes a `CommandError`, which the session survives.

### Everything touching NVDA is marshalled to the main thread

`api.getFocusObject()`, `config.conf` and the `controlTypes` reads all run on
NVDA's main thread via the existing `adapters/nvda_main_thread.run_on_main`,
blocking, as `NvdaAnnouncer.current_synth()` already does. The session runs on
the server thread; reading a live NVDA object from it is the same class of
mistake that the 9c pivot was about.

## Class/file layout

All under `bridges/nvda/addon/globalPlugins/nvdaMcpBridge/`.

### Ports (domain, strict-checked)

1. **`domain/ports/focus_inspector.py`** — port. `focus_info() -> FocusInfo`,
   with a frozen `FocusInfo` dataclass DTO (`name`, `role`, `states`, `value`,
   `app_module`) beside it, per the convention that a port's DTOs live with the
   port. Implemented by `NvdaFocusInspector`; used by `GetFocusInfoHandler`.
2. **`domain/ports/state_inspector.py`** — port. `state() -> ReaderState`, with
   a frozen `ReaderState` DTO (`browse_mode: str`, one of `"browse"` /
   `"focus"` / `"none"`; `speech_mode: str`, `sleep_mode: bool`,
   `input_help: bool`). Implemented by
   `NvdaStateInspector`; used by `GetStateHandler`.
3. **`domain/ports/config_accessor.py`** — port. `get(key_path) -> Any`,
   `set(key_path, value) -> Any`, `restore_all() -> None`. Implemented by
   `NvdaConfigAccessor`; used by both config handlers and by session teardown.

### Adapters (NVDA edge, pyright-ignored)

4. **`adapters/nvda_focus_inspector.py`** — reads `api.getFocusObject()` on the
   main thread; maps `Role`/`State` members to their `.name`; a null focus
   yields an empty `FocusInfo` rather than raising.
5. **`adapters/nvda_state_inspector.py`** — the four reads above, plus the
   tri-state browse-mode derivation.
6. **`adapters/nvda_config_accessor.py`** — walks `config.conf` by key path;
   holds the `dict[tuple[str, ...], Any]` of prior values for `restore_all`;
   never calls `save()`.

### Handlers (domain, strict-checked)

7. **`domain/controllers/commands/get_focus_info.py`** — `GetFocusInfoHandler`.
8. **`domain/controllers/commands/get_state.py`** — `GetStateHandler`.
9. **`domain/controllers/commands/get_config.py`** — `GetConfigHandler`.
10. **`domain/controllers/commands/set_config.py`** — `SetConfigHandler`.

Each maps its port's DTO to the wire result and nothing else, exactly as
`GetBrailleHandler` does.

### Wiring changes

11. **`domain/ports/adapter_factory.py`** — `AdapterSet` gains
    `focus_inspector`, `state_inspector` and `config_accessor`. These are
    mode-independent (unlike the speech source), so the factory builds the same
    three whichever capture mode `hello` chose.
12. **`adapters/nvda_adapter_factory.py`** — builds the three real adapters.
13. **`domain/controllers/commands/session_context.py`** — reaches the three
    through `ctx.adapters`, like the existing sources. No new context field.
14. **`domain/controllers/commands/registry.py`** — the four `not_implemented`
    entries become the four real handlers; `NotImplementedHandler` and its test
    are **deleted** (nothing else uses it); `NVDA_CAPABILITIES` widens to all
    seven.
15. **`domain/controllers/session.py`** — teardown gains a guarded
    `ctx.adapters.config_accessor.restore_all()`, placed with the other
    restoration steps.

### Test updates

16. **`tests/fakes/`** — `focus_inspector.py`, `state_inspector.py`,
    `config_accessor.py`: hand-written stateful fakes. The config fake really
    stores and really restores, so the teardown-restores-config test asserts
    behaviour rather than a call record.
17. **`tests/unit/domain/controllers/commands/`** — one test file per handler,
    mirroring the source tree.
18. **`tests/unit/domain/controllers/test_session.py`** — teardown restores
    touched config keys; restoration still runs when an earlier teardown step
    raised.
19. **`tests/integration/test_wire_session_roundtrip.py`** — the four commands
    over the loopback transport, and `hello` now announcing seven capabilities.
20. **`tests/support/conformance_bridge.py`** — must announce the widened set,
    or the cross-language conformance job's view of the bridge drifts from the
    real one.

## Live-NVDA checklist (11.1's PR body)

1. `get_focus_info` on a known control returns its name, `role` as a stable enum
   name, its states, and the owning app module.
2. Moving focus changes the answer; the role name is the same string under a
   non-English NVDA language.
3. `get_state` in a browser reports `browseMode: "browse"`; NVDA+space flips it
   to `"focus"`; in a Win32 dialog it is `"none"`.
4. `speechMode` tracks NVDA+s through `talk` → `off` → `beeps`.
5. `inputHelp` reads true with input help on, and gestures are described rather
   than performed while it is.
6. `get_config` reads a known key; `set_config` changes the reader's behaviour
   immediately.
7. **After the session ends, every key `set_config` touched is back to its
   original value, and `nvda.ini` on disk is unchanged** — checked by comparing
   the file's mtime and contents across the session.
8. The same holds after an abnormal end (panic gesture mid-session, and a killed
   client).
9. `list_tools` from the agent now advertises `get_focus_info`, `get_state`,
   `get_config` and `set_config`, with **no server change** — the check that the
   capability gate really is structural.

## Out of scope

- Any server-side change. See above; needing one is a design smell.
- Object navigation (parent/child/next), review cursor, and text-range reads.
  `getFocusInfo` answers "where am I", not "let me walk the tree". If the 11b run
  shows the tree is needed, that is a new entry and a new wire command, not a
  wider `FocusInfoResult`.
- Durable config writes — see the teardown decision above.

## Definition of done

The files above; headless suites, pyright strict and ruff green; `schema.json`
regenerated for the `browseMode` enum, with the drift gate and the conformance
job green; and the live-NVDA checklist run with the tester at the keyboard,
results in the PR body.
