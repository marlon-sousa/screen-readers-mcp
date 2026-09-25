# nvdaMcpBridge -- the NVDA global plugin (the NVDA edge).
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: the NVDA edge; loads the persisted config, builds the listener, starts the bridge, and stops it
# on unload or the panic gesture.

from __future__ import annotations

import os

import buildVersion
import globalPluginHandler
import globalVars
import gui
import ui
import wx
from logHandler import log
from scriptHandler import script

from .adapters.bridge_server import BridgeServer
from .adapters.build_listener import build_listener
from .adapters.ini_bridge_config import IniBridgeConfig
from .adapters.nvda_adapter_factory import NvdaAdapterFactory
from .adapters.nvda_announcer import NvdaAnnouncer
from .adapters.nvda_gesture_resolver import NvdaGestureResolver
from .adapters.nvda_log import NvdaLog
from .adapters.nvda_log_capture import NvdaLogCapture
from .adapters.nvda_session_signals import NvdaSessionSignals
from .adapters.nvda_user_prompter import ACK_GESTURE, NvdaUserPrompter
from .adapters.simple_event_bus import SimpleEventBus
from .adapters.text_config_file import TextConfigFile
from .domain.entities.connection_mode import ConnectionMode
from .domain.entities.silence_cap import SilenceCapPolicy
from .views.bridge_dialog import BridgeDialog
from .wiring import build_session


def _addon_version() -> str:
	"""Never raises: a bridge that fails to start is worse than an unknown version."""
	try:
		import addonHandler

		return str(addonHandler.getCodeAddon().manifest["version"])
	except Exception:
		return "unknown"


def _bridge_logs_dir() -> str:
	return os.path.join(globalVars.appArgs.configPath, "nvdaMcpBridge")


class GlobalPlugin(globalPluginHandler.GlobalPlugin):
	scriptCategory = _("NVDA MCP Bridge")

	def __init__(self) -> None:
		super().__init__()

		config_path = os.path.join(_bridge_logs_dir(), "config", "config.ini")
		self._log = NvdaLog()
		self._config = IniBridgeConfig(TextConfigFile(config_path), self._log)

		factory = NvdaAdapterFactory()
		listener = build_listener(self._config.get_connection_mode())
		logs_dir = _bridge_logs_dir()
		nvda_version = buildVersion.version
		bridge_version = _addon_version()
		signals = NvdaSessionSignals()
		announcer = NvdaAnnouncer()
		log_capture = NvdaLogCapture()
		user_prompter = NvdaUserPrompter()
		gesture_resolver = NvdaGestureResolver()
		self._event_bus = SimpleEventBus()

		def make_session(transport):
			# Re-read on every connection, so a dialog change takes effect on the next session.
			# attended and silence_cap come from one read so they cannot drift apart.
			unattended = self._config.get_unattended()
			silence_cap = SilenceCapPolicy.from_settings(
				unattended=unattended,
				warn_after=self._config.get_silence_warn_seconds(),
				lift_after=self._config.get_silence_lift_seconds(),
			)
			return build_session(
				transport,
				factory,
				logs_dir,
				nvda_version,
				signals,
				announcer,
				log_capture,
				user_prompter,
				gesture_resolver,
				bridge_version=bridge_version,
				silence_cap=silence_cap,
				attended=not unattended,
			)

		self._server = BridgeServer(listener, make_session, event_bus=self._event_bus)
		self._tools_menu_item: wx.MenuItem | None = None

		self._register_tools_menu_item()

		if self._config.get_auto_start():
			try:
				self._server.start()
				log.info(f"nvdaMcpBridge: listening on {self._server.status.endpoint}")
			except Exception:
				# A bind failure must not break add-on load.
				log.error("nvdaMcpBridge: could not start the bridge server", exc_info=True)

	def _register_tools_menu_item(self) -> None:
		if self._tools_menu_item is not None:
			return  # already registered (reload)
		try:
			tools_menu = gui.mainFrame.sysTrayIcon.toolsMenu
		except Exception:
			return
		# Translators: Menu item in NVDA's Tools menu to open the NVDA MCP Bridge dialog.
		self._tools_menu_item = tools_menu.Append(
			wx.ID_ANY,
			_("NVDA MCP &Bridge…"),
		)
		gui.mainFrame.sysTrayIcon.Bind(
			wx.EVT_MENU, lambda evt: self._show_bridge_dialog(), self._tools_menu_item
		)

	def _remove_tools_menu_item(self) -> None:
		item = self._tools_menu_item
		if item is None:
			return
		try:
			tools_menu = gui.mainFrame.sysTrayIcon.toolsMenu
		except Exception:
			return
		tools_menu.Remove(item)
		self._tools_menu_item = None

	def _show_bridge_dialog(self) -> None:
		dlg = BridgeDialog(gui.mainFrame, self._server, self._config, self._event_bus)
		dlg.set_plugin(self)
		dlg.ShowModal()
		dlg.Destroy()

	def start_server(self, mode: ConnectionMode) -> None:
		"""Called only while the server is stopped, so there is nothing to tear down."""
		self._config.set_connection_mode(mode)
		self._server.start(build_listener(mode))

	@script(
		# Translators: Input help message for the NVDA MCP bridge panic command.
		description=_("Stop the NVDA MCP bridge: end any active session and resume NVDA's speech"),
		gesture="kb:NVDA+control+shift+b",
	)
	def script_panic(self, gesture) -> None:
		# stop() joins the server thread, so speech flows again before the confirmation is queued.
		self._server.stop()
		# Translators: Announced after the panic gesture stops the bridge.
		wx.CallAfter(ui.message, _("NVDA MCP bridge stopped"))

	@script(
		# Translators: Input help message for the NVDA MCP bridge acknowledgement command.
		description=_(
			"Acknowledge a prompt from the NVDA MCP bridge: tell the agent you are done and hand control back"
		),
		gesture=f"kb:{ACK_GESTURE}",
	)
	def script_acknowledge(self, gesture) -> None:
		# Runs on NVDA's main thread, while the session thread polls the UserPrompt entity.
		session = self._server.current_session_context()
		if session is None:
			# Translators: Announced when the acknowledgement gesture is pressed
			# but no session is active.
			wx.CallAfter(ui.message, _("No bridge session to acknowledge"))
			return
		prompt = session.get_outstanding_prompt()
		if prompt is None:
			# Translators: Announced when the acknowledgement gesture is pressed
			# but no prompt is outstanding.
			wx.CallAfter(ui.message, _("No prompt to acknowledge"))
			return
		prompt.answer()
		# Translators: Announced when the acknowledgement gesture answers a prompt.
		wx.CallAfter(ui.message, _("Acknowledged"))

	def terminate(self) -> None:
		self._server.stop()
		self._remove_tools_menu_item()
		super().terminate()
