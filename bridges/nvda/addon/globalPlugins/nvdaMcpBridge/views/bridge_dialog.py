# nvdaMcpBridge views -- BridgeDialog: the bridge control UI (NVDA Tools menu).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: view; a wx.Dialog that shows bridge status and edits the connection mode, auto-start and silence cap.
# BUILT BY: plugin.py.
# USED BY: plugin.py's Tools menu item.

from __future__ import annotations

from typing import TYPE_CHECKING

import ui
import wx
from gui import guiHelper
from logHandler import log

from ..adapters.bridge_server import BridgeServer, ServerState
from ..domain.entities.bridge_events import BridgeEvent, BridgeEventType
from ..domain.entities.connection_mode import ConnectionMode
from ..domain.ports.bridge_config import BridgeConfig
from ..domain.ports.event_bus import EventBus

if TYPE_CHECKING:
	# Importing plugin.py at runtime would be circular.
	from ..plugin import GlobalPlugin


#: Below ten seconds the cap would fire in the gap between an announce being emitted and heard;
#: see specs/wire/v1/protocol.md section 7.1.
_MIN_SECONDS = 10
_MAX_SECONDS = 900


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


class BridgeDialog(wx.Dialog):
	def __init__(
		self,
		parent: wx.Window,
		server: BridgeServer,
		config: BridgeConfig,
		event_bus: EventBus,
	) -> None:
		# Translators: Title of the NVDA MCP Bridge dialog.
		super().__init__(parent, title=_("NVDA MCP Bridge"))

		self._server = server
		self._config = config
		self._event_bus = event_bus

		self._plugin: GlobalPlugin | None = None

		self._last_state: ServerState | None = None

		self._build_ui()
		self._init_combo_from_config()
		self._refresh()

		self._sub_token = self._event_bus.subscribe(BridgeEventType.SERVER_STATUS, self._on_server_status)

		self.Bind(wx.EVT_CHAR_HOOK, self._on_char_hook)
		self.Bind(wx.EVT_CLOSE, self._on_close)

	def set_plugin(self, plugin: GlobalPlugin) -> None:
		self._plugin = plugin

	def _build_ui(self) -> None:
		main_helper = guiHelper.BoxSizerHelper(self, orientation=wx.VERTICAL)

		# addLabeledControl associates the label, so NVDA reads it with the combo.
		choices = [
			# Translators: Connection mode option: named pipe.
			_("Named pipe"),
			# Translators: Connection mode option: loopback TCP.
			_("TCP"),
		]
		# Translators: Label above the connection mode combo box.
		self._mode_combo = main_helper.addLabeledControl(_("Connection mode:"), wx.Choice, choices=choices)
		self._mode_combo.Bind(wx.EVT_CHOICE, self._on_mode_changed)

		# Translators: Checkbox in the bridge dialog to start the bridge automatically when NVDA loads.
		self._auto_start_cb = main_helper.addItem(
			wx.CheckBox(self, label=_("Start bridge automatically when NVDA loads"))
		)
		self._auto_start_cb.Bind(wx.EVT_CHECKBOX, self._on_auto_start_changed)

		# Kept off the wire so the agent cannot raise its own ceiling.
		# Translators: Checkbox in the bridge dialog declaring that nobody is sitting
		# at this machine, so a silent session is never interrupted to restore speech.
		self._unattended_cb = main_helper.addItem(
			wx.CheckBox(self, label=_("This machine is &unattended (no speech time limit)"))
		)
		self._unattended_cb.Bind(wx.EVT_CHECKBOX, self._on_unattended_changed)

		# Translators: Label for the spin control setting how many seconds of silence
		# pass before the reader warns the person at the keyboard.
		self._warn_spin = main_helper.addLabeledControl(
			_("&Warn after (seconds):"),
			wx.SpinCtrl,
			min=_MIN_SECONDS,
			max=_MAX_SECONDS,
		)
		self._warn_spin.Bind(wx.EVT_SPINCTRL, self._on_thresholds_changed)
		# Translators: Label for the spin control setting how many seconds of silence
		# pass before the reader stops suppressing speech.
		self._lift_spin = main_helper.addLabeledControl(
			_("&Restore speech after (seconds):"),
			wx.SpinCtrl,
			min=_MIN_SECONDS,
			max=_MAX_SECONDS,
		)
		self._lift_spin.Bind(wx.EVT_SPINCTRL, self._on_thresholds_changed)

		button_helper = guiHelper.ButtonHelper(wx.HORIZONTAL)

		# Translators: Button in the bridge dialog to start the server.
		self._start_btn = button_helper.addButton(self, label=_("&Start"))
		self._start_btn.Bind(wx.EVT_BUTTON, self._on_start)

		# Translators: Button in the bridge dialog to stop the server.
		self._stop_btn = button_helper.addButton(self, label=_("St&op"))
		self._stop_btn.Bind(wx.EVT_BUTTON, self._on_stop)

		# Translators: Button in the bridge dialog to close the dialog.
		close_btn = button_helper.addButton(self, label=_("&Close"))
		close_btn.Bind(wx.EVT_BUTTON, lambda evt: self._dismiss())

		main_helper.addItem(button_helper)

		# NVDA+End reads the status bar.
		self._status_bar = wx.StatusBar(self)
		main_helper.addItem(self._status_bar, flag=wx.EXPAND)

		main_sizer = wx.BoxSizer(wx.VERTICAL)
		main_sizer.Add(main_helper.sizer, border=10, flag=wx.ALL)
		main_sizer.Fit(self)
		self.SetSizer(main_sizer)

	def _init_combo_from_config(self) -> None:
		"""Called once at open; _refresh never resets these, which belong to the user while open."""
		mode = self._config.get_connection_mode()
		self._mode_combo.SetSelection(_mode_to_combo_index(mode))
		self._warn_spin.SetValue(int(self._config.get_silence_warn_seconds()))
		self._lift_spin.SetValue(int(self._config.get_silence_lift_seconds()))

	def _refresh(self, *, announce: bool = True) -> None:
		status = self._server.status
		new_state = status.state
		stopped = new_state is ServerState.STOPPED

		if announce:
			self._announce_transition(self._last_state, new_state)
			self._last_state = new_state

		if new_state is ServerState.STOPPED:
			# Translators: Shown in the bridge dialog status bar when stopped.
			self._status_bar.SetStatusText(_("Stopped"))
		elif new_state is ServerState.LISTENING:
			endpoint = status.endpoint or "?"
			# Translators: Shown in the bridge dialog status bar when listening.
			# {endpoint} is the pipe name or host:port.
			self._status_bar.SetStatusText(_("Listening on {endpoint}").format(endpoint=endpoint))
		else:  # SESSION_ACTIVE
			# Translators: Shown in the bridge dialog status bar when a client is connected.
			self._status_bar.SetStatusText(_("Client connected"))

		self._mode_combo.Enable(stopped)

		self._start_btn.Enable(stopped)
		self._stop_btn.Enable(not stopped)

		self._auto_start_cb.SetValue(self._config.get_auto_start())

		unattended = self._config.get_unattended()
		self._unattended_cb.SetValue(unattended)
		self._warn_spin.Enable(not unattended)
		self._lift_spin.Enable(not unattended)

	@staticmethod
	def _announce_transition(old: ServerState | None, new: ServerState) -> None:
		if old is None:
			return
		if old is ServerState.STOPPED and new is ServerState.LISTENING:
			# Translators: Announced when the bridge starts listening.
			ui.message(_("Bridge started"))
		elif old is not ServerState.STOPPED and new is ServerState.STOPPED:
			# Translators: Announced when the bridge stops.
			ui.message(_("Bridge stopped"))
		elif new is ServerState.SESSION_ACTIVE:
			# Translators: Announced when a client connects.
			ui.message(_("Client connected"))
		elif old is ServerState.SESSION_ACTIVE and new is ServerState.LISTENING:
			# Translators: Announced when a client disconnects.
			ui.message(_("Client disconnected"))

	def _on_server_status(self, event: BridgeEvent) -> None:
		"""Called on an arbitrary thread; marshal to the main thread before touching wx."""
		wx.CallAfter(self._handle_status_change, event)

	def _handle_status_change(self, event: BridgeEvent) -> None:
		old = self._last_state
		new = event.payload.state
		self._refresh()

		if old is ServerState.STOPPED and new is ServerState.LISTENING:
			self._stop_btn.SetFocus()
		elif old is not ServerState.STOPPED and new is ServerState.STOPPED:
			self._mode_combo.SetFocus()

	def _on_mode_changed(self, evt: wx.CommandEvent) -> None:
		pass

	def _on_auto_start_changed(self, evt: wx.CommandEvent) -> None:
		self._config.set_auto_start(self._auto_start_cb.GetValue())

	def _on_unattended_changed(self, evt: wx.CommandEvent) -> None:
		unattended = self._unattended_cb.GetValue()
		self._config.set_unattended(unattended)
		self._warn_spin.Enable(not unattended)
		self._lift_spin.Enable(not unattended)

	def _on_thresholds_changed(self, evt: wx.SpinEvent) -> None:
		"""Nudge rather than refuse: a spin control passes through crossed-over values."""
		warn = self._warn_spin.GetValue()
		lift = self._lift_spin.GetValue()
		if lift <= warn:
			if evt.GetEventObject() is self._warn_spin:
				lift = min(warn + 1, _MAX_SECONDS)
				warn = min(warn, lift - 1)
				self._lift_spin.SetValue(lift)
				self._warn_spin.SetValue(warn)
			else:
				warn = max(lift - 1, _MIN_SECONDS)
				lift = max(lift, warn + 1)
				self._warn_spin.SetValue(warn)
				self._lift_spin.SetValue(lift)
		self._config.set_silence_warn_seconds(float(warn))
		self._config.set_silence_lift_seconds(float(lift))

	def _on_start(self, evt: wx.CommandEvent) -> None:
		new_mode = _combo_index_to_mode(self._mode_combo.GetSelection())
		if self._plugin is not None:
			try:
				self._plugin.start_server(new_mode)
			except Exception:
				log.error("nvdaMcpBridge: could not start the bridge server", exc_info=True)
				return

	def _on_stop(self, evt: wx.CommandEvent) -> None:
		self._server.stop()

	def _dismiss(self) -> None:
		"""The single teardown path for Close, Escape and Alt+F4; it does not stop the server."""
		self._event_bus.unsubscribe(self._sub_token)
		self.EndModal(wx.ID_CANCEL)

	def _on_char_hook(self, evt: wx.KeyEvent) -> None:
		if evt.GetKeyCode() == wx.WXK_ESCAPE:
			self._dismiss()
		else:
			evt.Skip()

	def _on_close(self, evt: wx.CloseEvent) -> None:
		self._dismiss()
		evt.Skip()
