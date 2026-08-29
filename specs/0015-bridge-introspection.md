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
`shared/screenreader_wire/protocol.py`; it regenerates `schema.json`, so it is
the one part of this entry the drift gate and the conformance job will see.

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

**Decided 2026-07-25; amended 2026-07-26.** The original design wrote through
`config.conf`'s `AggregatedSection` layer — writes landed in the most recently
activated profile — and restored by writing the prior value back through the
same path. That has a profile-switching gap: if a profile is active at `set`
time but a different profile (or none) is active at `restore` time, the restore
writes to the wrong place.

**Revised design (2026-07-26): the session override map.** The bridge holds a
`dict[tuple[str, ...], Any]` — never writes to `config.conf` at all. Instead, it
installs a hook on `AggregatedSection.__getitem__` that checks the map first.
Every consumer in NVDA — not just the bridge's own `get()` — sees the override,
and the map sits *above* the profile stack, so a profile switch mid-session does
not change which value is returned.

The rule: **never call `save()`** (unchanged), **never write to `config.conf`**
(new). On first `set()` the adapter records the effective value from
`config.conf` as the prior, stores the new value in the override map, and
installs the `__getitem__` hook. `get()` checks the map first, then falls
through to `config.conf`. Teardown clears the map and removes the hook; since
nothing was ever written to `config.conf`, restore is just clearing the map —
there is nothing to "restore" to. The prior value is recorded but never written
back; it exists so the `ConfigResult` returned by `set_config` carries the
previous effective value.

This is robust against every exit path:

- **Normal teardown:** clear map, remove hook. No config was ever touched.
- **Abnormal teardown (panic gesture):** same — the hook dies with the bridge
  process and NVDA's own `AggregatedSection.__getitem__` is the original.
- **Hard NVDA kill:** the map and hook are in-process state; they die together.
- **Profile switch mid-session:** the map is above the profile stack, so the
  override is visible regardless of which profile is active. Switching profiles
  does not move the override — it stays at the session-override layer.

The precedent is spec 0008's transparent silent capture: both intercept NVDA at
a core layer (`filter_speechSequence` / `AggregatedSection.__getitem__`), both
are session-scoped, and both are designed so that a crash restores normal
behaviour by the hook dying with the bridge process.

Consequence to state plainly: an agent cannot use `setConfig` to make a durable
change, by design. If a durable change is ever wanted it should be an explicit,
separately-named command, not a side effect of a test tool.

#### Amended 2026-07-26 (second): writes are hooked too, or the override escapes

Hooking only `__getitem__` made the layer **asymmetric — reads went through it
and writes went around it — and that asymmetry is a leak, not a detail.**

`ConfigManager.__getitem__` delegates to `rootSection[key]`, so *every* read in
NVDA resolves through the hooked `AggregatedSection.__getitem__` — including
NVDA's own settings GUI, which reads a value into a control
(`gui/settingsDialogs.py:1801`) and writes every control back on OK
(`gui/settingsDialogs.py:1906`). That write goes through `__setitem__`, which was
*not* hooked: the override landed in the real profile and marked it dirty, and
the next `save()` — `NVDA+control+c`, or save-on-exit — wrote it to disk. Opening
a settings dialog and clicking OK mid-session was therefore enough to
**permanently reconfigure the user's screen reader**, the exact outcome this
section exists to prevent.

So `AggregatedSection.__setitem__` is hooked on the same terms as
`__getitem__`:

- Writing a key **that is in the override map** updates the map. The profile is
  not touched and is not marked dirty, so there is nothing for `save()` to
  persist — which is why `save()` itself needs no hook.
- Writing **any other key** falls through to NVDA's own `__setitem__`,
  unchanged. Settings the session never touched behave exactly as they always
  did, including being saved.
- The short-circuit applies to scalar leaves only; sections, unspecced keys,
  dirty marking and cache maintenance are all left to the original.
- The short-circuit runs the same confspec `validator.check()` the original would
  have (`config/__init__.py:1261-1263`), so a value written through the GUI is
  coerced into the map with the type NVDA would have stored.

**That NVDA's GUI shows overridden values is correct, not a wart.** The dialog
displays what is in effect; editing it edits the effective layer. Documented
consequence: if the tester changes an overridden setting through NVDA's own UI
mid-session, that change goes into the map and is **discarded at teardown**
along with the session's own. The session owns the keys it overrode. Settings
outside the map are unaffected and persist normally.

**Rejected: injecting a synthetic profile** instead of patching. NVDA already
aggregates a stack of profiles, and `_getUpdateSection` writes to
`self.profiles[-1]`, so a profile of ours pushed on top would receive both reads
and writes with no monkey-patching at all. It fails on the one property this
design exists for: `_handleProfileSwitch` rebuilds `rootSection` from
`self.profiles` (`config/__init__.py:542`), and any profile activated *after*
ours sits above it — so the override would lose to a profile switch. Staying on
top would mean hooking the switch handler on every activation: more patching
than two `AggregatedSection` methods, on a hotter path. (Our profile also has no
`filename`, so anything marking it dirty would send `save()` looking for a file.)

**Boundary, stated so it is a decision and not an oversight.** This protects
NVDA's *documented* paths: GUI read and write, `save()`, manual profile
activation, and trigger-driven switches. It does not and cannot protect against
code that bypasses `AggregatedSection` entirely — an add-on writing
`config.conf.profiles[0][...]` directly reaches the profile underneath us. The
goal is correctness against NVDA, not tamper-proofing against arbitrary add-ons.

`keyPath` is opaque to the server and validated only by NVDA: a bad path, or a
value the confspec rejects, becomes a `ConfigError`, which the session survives.
Because the override map never reaches `config.conf`, configobj no longer gets
to vet the value on the way past, so the adapter runs the confspec check itself
— on the `setConfig` path and on the hooked-write path alike.

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
6. **`adapters/nvda_config_accessor.py`** — holds a session override map
   (`dict[tuple[str, ...], Any]`) and installs a hook on
   `AggregatedSection.__getitem__` on first `set()`. `get()` checks the map
   first, falling through to `config.conf`; `set()` records the effective value
   as prior, stores the new value in the map, and never writes to `config.conf`;
   `restore_all` clears the map and removes the hook. The map sits above the
   profile stack, so profile switches mid-session cannot affect it.

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
