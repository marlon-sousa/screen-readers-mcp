# nvdaMcpBridge tests -- a real bridge, started from outside pytest.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
# ROLE: test scaffolding; a real headless bridge with a fake NVDA, startable as a process.
# USED BY: server/tests/conformance/, which launches this script and drives it with the real MCP server.
#
# The driver starts it with --transport, reads one JSON line naming the endpoint from stdout, and closes
# stdin to stop it; nothing else is ever written to stdout.

from __future__ import annotations

import argparse
import importlib.util
import json
import sys
import tempfile
import uuid
from collections.abc import Sequence
from pathlib import Path

_SUPPORT_DIR = Path(__file__).resolve().parent
_TESTS_DIR = _SUPPORT_DIR.parent
_BRIDGE_ROOT = _TESTS_DIR.parent
_GLOBAL_PLUGINS = _BRIDGE_ROOT / "addon" / "globalPlugins"


def _bootstrap() -> None:
	"""Self-contained, because the driver is a Go test with no conftest to run first."""
	spec = importlib.util.spec_from_file_location("_sync_shared", _BRIDGE_ROOT / "sync_shared.py")
	assert spec is not None and spec.loader is not None
	module = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(module)
	module.sync()
	for path in (_GLOBAL_PLUGINS, _TESTS_DIR):
		if str(path) not in sys.path:
			sys.path.insert(0, str(path))


_bootstrap()

from fakes.adapter_factory import FakeAdapterFactory  # noqa: E402
from fakes.announcer import FakeAnnouncer  # noqa: E402
from fakes.gesture_resolver import FakeGestureResolver  # noqa: E402
from fakes.log_capture import FakeLogCapture  # noqa: E402
from fakes.session_signals import FakeSessionSignals  # noqa: E402
from fakes.user_prompter import FakeUserPrompter  # noqa: E402
from nvdaMcpBridge.adapters.bridge_server import BridgeServer, SessionFactory  # noqa: E402
from nvdaMcpBridge.adapters.ports.listener import Listener  # noqa: E402
from nvdaMcpBridge.adapters.ports.transport import Transport  # noqa: E402
from nvdaMcpBridge.adapters.tcp_listener import TcpListener  # noqa: E402
from nvdaMcpBridge.domain.controllers.session import Session  # noqa: E402
from nvdaMcpBridge.domain.entities.silence_cap import SilenceCapPolicy  # noqa: E402
from nvdaMcpBridge.wiring import build_session  # noqa: E402

#: Attended but uncapped: the one pair a server that derived attendance from enabled would get wrong.
CONFORMANCE_CAP = SilenceCapPolicy(enabled=False)

#: Deliberately not a real NVDA version, so matching it against a live NVDA cannot pass by accident.
READER_VERSION = "2026.1.0-conformance"

SCRIPTED_SPEECH: dict[str, list[str]] = {
	"kb:NVDA+f7": ["Elements list dialog", "Links radio button checked"],
}

INITIAL_BRAILLE = ["elements lst dlg"]


def _build_listener(transport: str) -> Listener:
	if transport == "tcp":
		return TcpListener("127.0.0.1", 0)
	# Imported lazily: the named-pipe leaf is Win32-only, and the TCP half must run anywhere.
	from nvdaMcpBridge.adapters.named_pipe_listener import NamedPipeListener

	# A unique name, so a run can neither collide with nor be satisfied by an installed bridge.
	return NamedPipeListener(rf"\\.\pipe\nvdaMcpBridgeConformance-{uuid.uuid4().hex}")


def _endpoint_spec(transport: str, endpoint: str) -> str:
	"""The endpoint in the server's --reader spelling: tcp:host:port or local:name."""
	if transport == "tcp":
		return f"tcp:{endpoint}"
	return "local:" + endpoint.rsplit("\\", 1)[-1]


def _session_factory(logs_dir: Path) -> SessionFactory:

	def build(transport: Transport) -> Session:
		factory = FakeAdapterFactory(speech=SCRIPTED_SPEECH)
		factory.braille_source.initial = list(INITIAL_BRAILLE)
		return build_session(
			transport,
			factory,
			logs_dir,
			READER_VERSION,
			FakeSessionSignals(),
			FakeAnnouncer(),
			FakeLogCapture(),
			FakeUserPrompter(),
			FakeGestureResolver(),
			silence_cap=CONFORMANCE_CAP,
			attended=True,
		)

	return build


def main(argv: Sequence[str] | None = None) -> int:
	parser = argparse.ArgumentParser(description="Run a headless NVDA bridge for conformance testing.")
	parser.add_argument("--transport", choices=("pipe", "tcp"), required=True)
	parser.add_argument(
		"--logs-dir",
		default=None,
		help="where session transcripts go; a temporary directory by default",
	)
	args = parser.parse_args(argv)

	transport: str = args.transport
	logs_dir = (
		Path(args.logs_dir) if args.logs_dir else Path(tempfile.mkdtemp(prefix="nvda-mcp-conformance-"))
	)

	server = BridgeServer(_build_listener(transport), _session_factory(logs_dir))
	server.start()
	endpoint = server.status.endpoint
	if endpoint is None:
		server.stop()
		sys.stderr.write("the bridge started but reported no endpoint\n")
		return 1

	try:
		# Flushed: the driver blocks on this line.
		sys.stdout.write(json.dumps({"endpoint": _endpoint_spec(transport, endpoint)}) + "\n")
		sys.stdout.flush()
		sys.stderr.write(f"conformance bridge listening on {endpoint}; transcripts in {logs_dir}\n")
		sys.stderr.flush()

		# Stdin EOF is the stop signal, so the bridge cannot outlive a dead driver.
		sys.stdin.read()
	except KeyboardInterrupt:
		pass
	finally:
		server.stop()
	return 0


if __name__ == "__main__":
	raise SystemExit(main())
