# Spec 0011 — bridge: control UI + connection config (entry 9.1b)

Implementation contract for ROADMAP lane 1, entry 9.1b (split off entry 9.1,
agreed 2026-07-21). Authored on the entry's branch per process; the spec rides
in the implementing PR.

## Goal

After 9.1a the named pipe is the hardcoded default and `plugin.py` builds a
`NamedPipeListener` unconditionally. A user who wants loopback TCP instead has
no way to choose it — and no UI at all to see whether the bridge is running,
start or stop it, or have it auto-start on NVDA load.

This entry delivers three things that together give the user control:

1. **A bridge dialog** — NVDA menu → Tools → "NVDA MCP Bridge…" — showing the
   current status (Stopped / Listening on `<endpoint>` / Client connected), a
   connection-mode combo (Named pipe / TCP), Start and Stop buttons, and an
   auto-start checkbox.
2. **Config persistence** — the connection mode and auto-start preference are
   saved to a plain `config.ini` file under the NVDA user config directory,
   independent of NVDA's profile-switching `config.conf` (see Decided).
3. **Config-driven listener choice** — `plugin.py` reads the persisted mode on
   load and builds the matching `Listener` (named pipe or loopback TCP), and
   auto-starts only when the user has asked for it.

The pipe is already the default (9.1a); this entry lets a user *override* it
back to loopback TCP and control the server's lifecycle without reloading the
addon or editing code.

## Decided

- **One dialog, not a settings panel.** NVDA settings panels (multi-page
  Preferences) are for static configuration consumed at next load. This dialog
  controls a *running* server — Start and Stop are immediate actions, and the
  status indicator is live — so a standalone dialog reached from the Tools menu
  is the right surface. The two persisted values (mode and auto-start) ride in
  the same dialog because they belong with the thing they control.
- **Profile-independent config: a plain `config.ini`, not NVDA's
  `config.conf`.** NVDA's `config.conf` is profile-aware — switching profiles
  resets it to the active profile's values. The bridge's connection mode and
  auto-start preference are machine-wide settings; they should survive a profile
  switch unchanged. A plain `configparser`-backed `.ini` file under
  `<configPath>\nvdaMcpBridge\config\config.ini` — sibling to the logs directory
  the bridge already owns — achieves profile independence with stdlib only and
  no NVDA config-spec registration.
- **Connection mode is an enum, not a free-form string.** `ConnectionMode` is a
  `StrEnum` in the domain (pure, testable), with two members — `NAMED_PIPE`
  and `LOOPBACK_TCP`. The combo box shows exactly these two as fixed choices.
  `REMOTE_TCP` is defined in the enum for a future security entry.
- **The dialog lives in `views/`, not `adapters/`.** It is not an adapter — it
  does not implement any domain port. It is a **driving actor** that consumes
  ports (the `BridgeConfig` port for persistence, the `EventBus` port for status
  notifications, plus `BridgeServer` directly for lifecycle) the same way a
  domain controller does. It lives at the package root, sibling to `domain/` and
  `adapters/`, because its dependency surface is the full NVDA GUI stack (wx,
  `gui`, `logHandler`) — outside the domain boundary but not behind a seam
  either. `plugin.py` activates it by constructing it with real dependencies and
  showing it from the menu.
- **Port injection, not global imports.** `BridgeDialog.__init__` receives
  `BridgeConfig`, `BridgeServer`, and `EventBus` ports via constructor injection
  — `plugin.py` is the composition root that wires the real ones. This keeps the
  dialog testable against fakes and decoupled from where the config file lives.
- **Push notifications, not polling.** The dialog subscribes to `SERVER_STATUS`
  events on the `EventBus` port. `BridgeServer` emits on every state transition;
  the bus calls subscribers synchronously; the dialog's handler marshals to the
  main thread via `wx.CallAfter`. No timer, no polling.
- **Auto-start is off by default.** `autoStart` defaults to `False` in
  `IniBridgeConfig`. The checkbox in the dialog lets the user opt in; on next
  NVDA load, `plugin.__init__` reads the value and starts the server only if it
  is `True`.
- **Start is a retry path.** If the initial `server.start()` in `plugin.py`
  failed (e.g. pipe name collision), the dialog shows `STOPPED` and the Start
  button lets the user try again.
- **`BridgeServer.start()` accepts an optional new listener.** When switching
  modes, the caller passes a new listener to `start()`; the server closes the old
  one and binds the new one. No full BridgeServer rebuild needed.
- **All user-visible strings go through `_()` with translator comments.**
  Every label, button, combo entry, status text, and announcement is wrapped in
  NVDA's `_()` translation function and preceded by a `# Translators:` comment.
- **No new wire command or protocol change.** This is purely local UI + config;
  the bridge's wire surface is unchanged.

## Deliverables

All under `bridgeAddon/` unless noted. Every module carries the mandatory ROLE
header.

### 1. `domain/entities/connection_mode.py` — the pure enum

**Role:** entity. A `StrEnum` the domain, views, and adapters both import (it
lives in `domain/` so it stays pure; `protocol.py` does NOT need it — the wire
does not know about transports).

```python
class ConnectionMode(StrEnum):
    NAMED_PIPE = "namedPipe"
    LOOPBACK_TCP = "loopbackTcp"
    REMOTE_TCP = "remoteTcp"  # defined but unreachable from the UI until its security entry lands

DEFAULT: Final = ConnectionMode.NAMED_PIPE
```

Unit-tested in `tests/unit/domain/entities/test_connection_mode.py`.

### 2. `domain/ports/bridge_config.py` — the persistence port

**Role:** port (`abc.ABC`). The contract the dialog (and `plugin.py`) read/write
persisted preferences through — without knowing they're an `.ini` file.

```python
class BridgeConfig(ABC):
    @abstractmethod
    def get_connection_mode(self) -> ConnectionMode: ...
    @abstractmethod
    def set_connection_mode(self, mode: ConnectionMode) -> None: ...
    @abstractmethod
    def get_auto_start(self) -> bool: ...
    @abstractmethod
    def set_auto_start(self, value: bool) -> None: ...
```

Reads return defaults (`DEFAULT`, `False`) when no file exists yet; writes
create the file on first save.

### 3. `adapters/ports/config_file.py` — the ConfigFile seam

**Role:** adapter seam (`abc.ABC`). Whole-file read/write so `IniBridgeConfig`
is unit-testable against a fake. `read() -> str | None` (None = file absent);
`write(content: str)` (creates parent dirs).

### 4. `adapters/text_config_file.py` — the ConfigFile leaf

**Role:** leaf adapter (implements `ConfigFile`). Real `open()`/read/write.
No decisions — no unit test file (same rule as `text_file_writer.py`).

### 5. `adapters/ini_bridge_config.py` — the configparser adapter

**Role:** adapter (implements `BridgeConfig`). Owns every decision: defaults,
validation, corrupt-file recovery, configparser vocabulary. Takes a `ConfigFile`
via constructor; raw IO is delegated there. Uses `logHandler.log` (NVDA edge)
with a stdlib `logging` fallback so it is importable in headless tests.
Unit-tested against `FakeConfigFile` in `tests/unit/adapters/test_ini_bridge_config.py`.

### 6. `domain/entities/bridge_events.py` — event DTO

**Role:** entity. `BridgeEventType(StrEnum)` (one member: `SERVER_STATUS`) and
`BridgeEvent` (frozen dataclass: `type` + `payload`). Pure, no collaborators.

Unit-tested in `tests/unit/domain/entities/test_bridge_events.py`.

### 7. `domain/ports/event_bus.py` — the pub/sub port

**Role:** port (`abc.ABC`). `subscribe(type, handler) -> SubscriptionToken`,
`unsubscribe(token)`, `emit(event)`. Used by `BridgeServer` (emitter) and
`BridgeDialog` (subscriber).

### 8. `adapters/simple_event_bus.py` — the EventBus leaf

**Role:** leaf adapter (implements `EventBus`). Weakref'd handlers keyed by
event type, dead-ref cleanup on emit. Token-based unsubscribe. No unit test
file (leaf). A `FakeEventBus` exists in `tests/fakes/` for test use.

### 9. `tests/fakes/` — new fakes

| File | Role |
|---|---|
| `fakes/config_file.py` | `FakeConfigFile`: in-memory string backend for `ConfigFile`. |
| `fakes/event_bus.py` | `FakeEventBus`: in-memory handler lists; records emitted events. |
| `fakes/bridge_config.py` | `FakeBridgeConfig`: in-memory dict backend; `auto_start` defaults to `False`. |

### 10. `views/__init__.py` — package doc

**Role:** documentation. Explains the `views/` role: driving actors consuming
ports, activated by the composition root.

### 11. `views/bridge_dialog.py` — the wx dialog

**Role:** driving actor (view). A `wx.Dialog` subclass. Receives `BridgeConfig`,
`BridgeServer`, and `EventBus` via constructor injection. Also exports
`build_listener(mode)` — the single mode→Listener factory, imported by
`plugin.py`.

```python
def build_listener(mode: ConnectionMode) -> Listener: ...

class BridgeDialog(wx.Dialog):
    def __init__(
        self,
        parent: wx.Window,
        server: BridgeServer,
        config: BridgeConfig,
        event_bus: EventBus,
    ) -> None: ...
```

**Layout** (top to bottom, single column):

1. **Status** — a `wx.StatusBar` (NVDA+End reads it). Updated on every
   `SERVER_STATUS` event via the `EventBus`. Exactly three strings:
   - `_("Stopped")`
   - `_("Listening on {endpoint}").format(endpoint=...)`
   - `_("Client connected")`

2. **Connection mode** — `_("Connection mode:")` + `wx.Choice` with two entries:
   `_("Named pipe")` → `NAMED_PIPE`, `_("TCP")` → `LOOPBACK_TCP`.
   Enabled only when the server is `STOPPED`.

3. **Auto-start** — `_("Start bridge automatically when NVDA loads")` checkbox.
   Persisted immediately on toggle.

4. **Buttons** — `_("&Start")` (enabled when `STOPPED`), `_("St&op")` (enabled
   when not `STOPPED`), `_("&Close")` (always enabled; closes without stopping).

**State machine:**

| State | Combo | Start | Stop |
|---|---|---|---|
| Stopped | enabled | enabled | disabled |
| Listening | disabled | disabled | enabled |
| Client connected | disabled | disabled | enabled |

**Dismiss:** Close button, ESC (`_on_char_hook` catches `WXK_ESCAPE`), and
Alt+F4 all funnel through `_dismiss()` → unsubscribe + `EndModal(wx.ID_CANCEL)`.

**Announcements and focus:** The event bus callback (`_handle_status_change`) is
the single place that refreshes controls, announces transitions ("Bridge
started", "Bridge stopped", "Client connected", "Client disconnected"), and
steers focus (Start → Stop button; Stop → combo). Button handlers only trigger
actions; they do not call `_refresh()` or announce directly.

### 12. `plugin.py` changes

- Constructs `TextConfigFile` + `IniBridgeConfig` for config persistence.
- Constructs `SimpleEventBus` and hands it to both `BridgeServer` and the dialog.
- Builds the initial listener via `build_listener(mode)` from persisted config.
- Auto-starts only when `config.get_auto_start()` is `True` (off by default).
- Registers a Tools menu item `_("NVDA MCP &Bridge…")`.
- Exposes `start_server(mode)` — persists the mode, calls
  `server.start(build_listener(mode))`. Called by the dialog's Start button.
- `script_panic` and `terminate()` are unchanged.

### 13. `BridgeServer` changes

- `start()` now accepts an optional `listener: Listener | None` parameter. If
  given, closes the old listener and uses the new one — no full rebuild needed.
- Emits a `BridgeEvent(SERVER_STATUS, payload=ServerStatus)` on every state
  transition via an optional `EventBus` injected at construction.

### 14. Test updates

| File | What |
|---|---|
| `tests/unit/domain/entities/test_connection_mode.py` | Existing (from 9.1a branch). |
| `tests/unit/domain/entities/test_bridge_events.py` | New: asserts members, frozen, hashable, equality. |
| `tests/unit/adapters/test_ini_bridge_config.py` | New: 10 tests against `FakeConfigFile` — defaults, read, write, corrupt, round-trip. |
| `tests/unit/adapters/test_bridge_server.py` | 5 new tests: event emission on start/stop/connect/disconnect, `start(listener)` override. |
| `tests/fakes/config_file.py` | New. |
| `tests/fakes/event_bus.py` | New. |
| `tests/fakes/bridge_config.py` | Updated: `auto_start` defaults to `False`. |

### 15. Packaging

No new dependencies; `configparser` and `io` are stdlib; wx comes from NVDA.

## Class/file layout summary

| File | Role | Collaborators |
|---|---|---|
| `domain/entities/connection_mode.py` | entity | `ConnectionMode(StrEnum)`: `NAMED_PIPE`, `LOOPBACK_TCP`, `REMOTE_TCP` + `DEFAULT`. |
| `domain/entities/bridge_events.py` | entity | `BridgeEventType(StrEnum)`, `BridgeEvent` frozen dataclass. |
| `domain/ports/bridge_config.py` | port (`abc.ABC`) | `BridgeConfig`: four abstract methods for mode + auto-start persistence. |
| `domain/ports/event_bus.py` | port (`abc.ABC`) | `EventBus`: `subscribe`, `unsubscribe`, `emit`. |
| `adapters/ports/config_file.py` | adapter seam (`abc.ABC`) | `ConfigFile`: `read()`, `write()`. |
| `adapters/text_config_file.py` | leaf adapter | Real file IO. No tests. |
| `adapters/ini_bridge_config.py` | adapter (implements `BridgeConfig`) | `IniBridgeConfig`: configparser decisions, delegates IO to `ConfigFile`. Unit-tested. |
| `adapters/simple_event_bus.py` | leaf adapter (implements `EventBus`) | Weakref'd handlers, dead-ref cleanup. |
| `views/__init__.py` | documentation | Package docstring. |
| `views/bridge_dialog.py` | driving actor (view) | `BridgeDialog(wx.Dialog)` + `build_listener()`. Receives `BridgeConfig` + `BridgeServer` + `EventBus`. |
| `tests/fakes/config_file.py` | fake | `FakeConfigFile`: in-memory string. |
| `tests/fakes/event_bus.py` | fake | `FakeEventBus`: records events. |
| `tests/fakes/bridge_config.py` | fake | `FakeBridgeConfig`: in-memory dict; `auto_start=False`. |
| `tests/unit/domain/entities/test_connection_mode.py` | unit test | Existing. |
| `tests/unit/domain/entities/test_bridge_events.py` | unit test (new) | 5 tests. |
| `tests/unit/adapters/test_ini_bridge_config.py` | unit test (new) | 10 tests. |
| `tests/unit/adapters/test_bridge_server.py` | unit test (updated) | +5 event/start-listener tests. |
| `plugin.py` (modified) | the NVDA edge | Wires `TextConfigFile` → `IniBridgeConfig`, `SimpleEventBus`, `build_listener`, auto-start, Tools menu, `start_server()`. |
| `adapters/bridge_server.py` (modified) | adapter-layer controller | `start(listener)`, `EventBus` injection, `_notify()` on transitions. |

## Acceptance criteria

Automated (CI, `bridge` job):

1. All 140 unit + integration tests green, including 10 `test_ini_bridge_config`,
   5 `test_bridge_events`, 5 new `test_bridge_server` event tests.
2. pyright strict clean on the domain; new adapters covered by the ignore list.
3. The `no unchecked checkboxes` gate stays green.

Manual live-NVDA checklist (this PR's body, per AGENTS.md):

1. **Dialog opens:** NVDA → Tools → "NVDA MCP Bridge…" opens. Status shows
   "Stopped" (auto-start is off by default). Combo and Start are enabled;
   Stop is disabled.
2. **Start:** pick a mode, press Start — status shows "Listening on …"; combo
   and Start disable, Stop enables. Focus moves to Stop. "Bridge started"
   announced.
3. **Client connect:** connect a client — status shows "Client connected".
   Combo/Start stay disabled. Announcement: "Client connected".
4. **Stop:** press Stop — status shows "Stopped"; combo/Start enable, Stop
   disables. Focus moves to combo. "Bridge stopped" announced.
5. **Mode switch:** Stop → choose TCP → Start → client connects over TCP.
   Stop → choose Named pipe → Start → client connects over pipe.
6. **Auto-start on:** check auto-start, close dialog, restart NVDA — bridge
   listens on the last mode. Uncheck and restart — bridge is stopped.
7. **Panic gesture:** `NVDA+control+shift+b` stops the server; dialog status
   updates to "Stopped" if open. "Bridge stopped" announced.
8. **Mode persists:** restart NVDA — bridge listens on the last mode.
9. **Profile independence:** switching NVDA profiles does not change the
   connection mode or auto-start preference.
10. **First run:** no `config.ini` → defaults: named pipe, auto-start off.

## Out of scope

- Remote TCP — deferred behind its own security entry.
- A settings panel in NVDA Preferences — this is a live control dialog.
- Server-level access control, authentication, remote security model.
- Lane 2 (`BridgeClient`) learning to dial a named pipe.
- Any wire protocol or schema change.

## Definition of done

Merged with green CI; ROADMAP entry 9.1b flipped to Done by this PR; the manual
checklist above completed in the PR body.
