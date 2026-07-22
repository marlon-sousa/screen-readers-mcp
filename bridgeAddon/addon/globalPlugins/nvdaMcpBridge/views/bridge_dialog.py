# nvdaMcpBridge views -- BridgeDialog: the bridge control UI (NVDA Tools menu).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: driving actor (view). A wx.Dialog that shows bridge status, lets the user
#       pick a connection mode, start/stop the server, and toggle auto-start.
#       Receives a BridgeConfig port and a BridgeServer via constructor injection.
# DEPENDS ON: wx, NVDA's gui, BridgeServer (adapter), BridgeConfig (domain port),
#             ConnectionMode (domain entity), and the Listener seam for build_listener.
# BUILT BY: plugin.py (_show_bridge_dialog -- the composition root for the view).
# USED BY: plugin.py's Tools menu item.
#
# Also exports build_listener(mode) -- the single mode→Listener factory, imported
# by plugin.py for the initial construction on load.
#
# This file imports wx and NVDA's GUI stack; it is in pyright's ``ignore`` list
# (see pyproject.toml). It is validated by the live-NVDA checklist.

from __future__ import annotations

from typing import TYPE_CHECKING

from gui import guiHelper
import ui
import wx
from logHandler import log

from ..adapters.bridge_server import BridgeServer, ServerState
from ..adapters.named_pipe_listener import NamedPipeListener
from ..adapters.ports.listener import Listener
from ..adapters.tcp_listener import TcpListener
from ..domain.entities.connection_mode import ConnectionMode
from ..domain.ports.bridge_config import BridgeConfig

if TYPE_CHECKING:
	pass

from .. import protocol

#: How often (ms) the status timer polls BridgeServer.status.
_POLL_MS = 500


def build_listener(mode: ConnectionMode) -> Listener:
	"""The single mode→Listener factory. Pure: neither leaf constructor imports NVDA.

	Lives here so the view owns the mode→transport mapping conceptually;
	plugin.py imports it for the initial load path. Single source of truth.
	"""
	if mode is ConnectionMode.NAMED_PIPE:
		return NamedPipeListener(protocol.DEFAULT_PIPE_NAME)
	if mode is ConnectionMode.LOOPBACK_TCP:
		return TcpListener("127.0.0.1", protocol.DEFAULT_PORT)
	raise ValueError(f"Unsupported connection mode: {mode}")


# -- status text helpers --------------------------------------------------------

def _status_text(state: ServerState, mode: ConnectionMode, endpoint: str | None) -> str:
	"""Compose a translatable status line from the raw server snapshot.

	Each branch returns a complete translatable string (wrapped in ``_()`` with its
	own ``# Translators:`` comment) so translators see the full sentence, not
	fragments to reassemble.
	"""
	if state is ServerState.STOPPED:
		# Translators: Shown in the bridge dialog when the server is stopped.
		return _("Stopped")
	if endpoint is None:
		endpoint = "?"

	if mode is ConnectionMode.NAMED_PIPE:
		if state is ServerState.LISTENING:
			# Translators: Shown in the bridge dialog when listening on the named pipe.
			# {endpoint} is the pipe name.
			return _("Listening — Named pipe ({endpoint})").format(endpoint=endpoint)
		# SESSION_ACTIVE
		# Translators: Shown in the bridge dialog when a session is active on the named pipe.
		# {endpoint} is the pipe name.
		return _("Session active — Named pipe ({endpoint})").format(endpoint=endpoint)

	if mode is ConnectionMode.LOOPBACK_TCP:
		if state is ServerState.LISTENING:
			# Translators: Shown in the bridge dialog when listening on loopback TCP.
			# {endpoint} is the host:port.
			return _("Listening — Loopback TCP ({endpoint})").format(endpoint=endpoint)
		# SESSION_ACTIVE
		# Translators: Shown in the bridge dialog when a session is active on loopback TCP.
		# {endpoint} is the host:port.
		return _("Session active — Loopback TCP ({endpoint})").format(endpoint=endpoint)

	# Fallback for REMOTE_TCP (unreachable today, but the enum member exists).
	if state is ServerState.LISTENING:
		return _("Listening — Remote TCP ({endpoint})").format(endpoint=endpoint)
	return _("Session active — Remote TCP ({endpoint})").format(endpoint=endpoint)


# -- mode <-> combo index helpers -----------------------------------------------

# The combo has two entries in this order. Remote TCP is deliberately absent
# — it is defined in the enum for the future security entry, but unreachable
# from the UI until that entry lands.
_COMBO_ENTRIES: tuple[ConnectionMode, ...] = (
	ConnectionMode.NAMED_PIPE,
	ConnectionMode.LOOPBACK_TCP,
)


def _mode_to_combo_index(mode: ConnectionMode) -> int:
	try:
		return _COMBO_ENTRIES.index(mode)
	except ValueError:
		return 0  # fallback: named pipe


def _combo_index_to_mode(index: int) -> ConnectionMode:
	if 0 <= index < len(_COMBO_ENTRIES):
		return _COMBO_ENTRIES[index]
	return ConnectionMode.NAMED_PIPE


# -- the dialog ----------------------------------------------------------------


class BridgeDialog(wx.Dialog):
	"""NVDA Tools → NVDA MCP Bridge… dialog.

	Shows the current bridge status in a status bar (NVDA+End reads it),
	lets the user change the connection mode, start/stop the server, and
	toggle auto-start. Receives its dependencies (BridgeServer, BridgeConfig)
	through constructor injection so plugin.py is the composition root.
	"""

	def __init__(
		self,
		parent: wx.Window,
		server: BridgeServer,
		config: BridgeConfig,
	) -> None:
		# Translators: Title of the NVDA MCP Bridge dialog.
		super().__init__(parent, title=_("NVDA MCP Bridge"))

		self._server = server
		self._config = config

		# Hold a reference to the plugin for rebuild_server() and so we can
		# always read the current server (rebuild_server creates a new one).
		self._plugin: "GlobalPlugin | None" = None

		self._build_ui()
		self._refresh()

		# Poll server status so the display stays live (client connecting changes
		# LISTENING → SESSION_ACTIVE, panic gesture changes it to STOPPED, etc.).
		self._timer = wx.Timer(self)
		self.Bind(wx.EVT_TIMER, self._on_timer, self._timer)
		self._timer.Start(_POLL_MS)

		self.Bind(wx.EVT_CLOSE, self._on_close)

	# -- plugin back-reference --------------------------------------------------

	def set_plugin(self, plugin: "GlobalPlugin") -> None:
		"""Give the dialog a back-reference to the plugin so Start can call
		``plugin.rebuild_server(mode)`` and the dialog always reads the
		current server (rebuild_server replaces the instance)."""
		self._plugin = plugin

	# -- current server ---------------------------------------------------------

	def _current_server(self) -> BridgeServer:
		"""The plugin's current BridgeServer instance.

		rebuild_server() creates a new BridgeServer and assigns it to
		self._plugin._server, so the dialog's snapshot can become stale.
		Always read through the plugin when available.
		"""
		if self._plugin is not None:
			return self._plugin._server
		return self._server

	# -- UI construction --------------------------------------------------------

	def _build_ui(self) -> None:
		main_helper = guiHelper.BoxSizerHelper(self, orientation=wx.VERTICAL)

		# 1. Connection mode — use addLabeledControl so NVDA reads the combo
		#    items when arrowing (the label is properly associated for a11y).
		choices = [
			# Translators: Connection mode option: local named pipe.
			_("Local: named pipe (recommended)"),
			# Translators: Connection mode option: local loopback TCP.
			_("Local: loopback TCP"),
		]
		# Translators: Label above the connection mode combo box.
		self._mode_combo = main_helper.addLabeledControl(
			_("Accept connections via:"), wx.Choice, choices=choices
		)
		self._mode_combo.Bind(wx.EVT_CHOICE, self._on_mode_changed)

		# 2. Auto-start checkbox
		# Translators: Checkbox in the bridge dialog to start the bridge automatically when NVDA loads.
		self._auto_start_cb = main_helper.addItem(
			wx.CheckBox(self, label=_("Start bridge automatically when NVDA loads"))
		)
		self._auto_start_cb.Bind(wx.EVT_CHECKBOX, self._on_auto_start_changed)

		# 3. Button row (Start, Stop, Close)
		button_helper = guiHelper.ButtonHelper(wx.HORIZONTAL)

		# Translators: Button in the bridge dialog to start the server.
		self._start_btn = button_helper.addButton(self, label=_("&Start"))
		self._start_btn.Bind(wx.EVT_BUTTON, self._on_start)

		# Translators: Button in the bridge dialog to stop the server.
		self._stop_btn = button_helper.addButton(self, label=_("St&op"))
		self._stop_btn.Bind(wx.EVT_BUTTON, self._on_stop)

		# Translators: Button in the bridge dialog to close the dialog.
		close_btn = button_helper.addButton(self, label=_("&Close"))
		close_btn.Bind(wx.EVT_BUTTON, self._on_close_button)

		main_helper.addItem(button_helper)

		# 4. Status bar — NVDA+End reads this, following the TimerForNVDA pattern.
		self._status_bar = wx.StatusBar(self)
		main_helper.addItem(self._status_bar, flag=wx.EXPAND)

		main_sizer = wx.BoxSizer(wx.VERTICAL)
		main_sizer.Add(main_helper.sizer, border=10, flag=wx.ALL)
		main_sizer.Fit(self)
		self.SetSizer(main_sizer)

	# -- refresh ----------------------------------------------------------------

	def _refresh(self) -> None:
		"""Read server status and config, then update every control.

		Called on every timer tick and after Start/Stop so the UI always reflects
		the current state."""
		server = self._current_server()
		status = server.status
		mode = self._config.get_connection_mode()

		# Status bar: the text NVDA+End reads.
		self._status_bar.SetStatusText(_status_text(status.state, mode, status.endpoint))

		# Combo: show the persisted mode. Freeze the whole combo while a session
		# is active — the transport cannot change under a live connection.
		active = status.state is ServerState.SESSION_ACTIVE
		self._mode_combo.SetSelection(_mode_to_combo_index(mode))
		self._mode_combo.Enable(not active)

		# Buttons: Start enabled only when stopped; Stop enabled otherwise.
		stopped = status.state is ServerState.STOPPED
		self._start_btn.Enable(stopped)
		self._stop_btn.Enable(not stopped)

		# Auto-start checkbox
		self._auto_start_cb.SetValue(self._config.get_auto_start())

	# -- event handlers ---------------------------------------------------------

	def _on_timer(self, evt: wx.TimerEvent) -> None:
		self._refresh()

	def _on_mode_changed(self, evt: wx.CommandEvent) -> None:
		# The combo records the user's *preference*; the actual listener rebuild
		# and server restart happen only when Start is pressed. This avoids
		# tearing down a running session because the user browsed the combo.
		pass

	def _on_auto_start_changed(self, evt: wx.CommandEvent) -> None:
		self._config.set_auto_start(self._auto_start_cb.GetValue())

	def _on_start(self, evt: wx.CommandEvent) -> None:
		new_mode = _combo_index_to_mode(self._mode_combo.GetSelection())
		if self._plugin is not None:
			try:
				self._plugin.rebuild_server(new_mode)
			except Exception:
				log.error("nvdaMcpBridge: could not start the bridge server", exc_info=True)
				self._refresh()
				return
		# rebuild_server creates a new BridgeServer; sync our reference.
		self._server = self._current_server()
		self._refresh()
		# Voice confirmation so the user hears the result without navigating.
		# Translators: Announced after starting the bridge from the dialog.
		wx.CallAfter(ui.message, _("Bridge started"))

	def _on_stop(self, evt: wx.CommandEvent) -> None:
		self._current_server().stop()
		self._refresh()
		# Voice confirmation so the user hears the result without navigating.
		# Translators: Announced after stopping the bridge from the dialog.
		wx.CallAfter(ui.message, _("Bridge stopped"))

	def _on_close_button(self, evt: wx.CommandEvent) -> None:
		# Close does NOT stop the server -- the bridge keeps running.
		self.Close()

	def _on_close(self, evt: wx.CloseEvent) -> None:
		self._timer.Stop()
		evt.Skip()
