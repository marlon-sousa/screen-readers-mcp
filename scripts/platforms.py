# The host this checkout is being worked on, and the few facts that follow.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: the one place anything under scripts/ reads `sys.platform`.
# USED BY: doctor.py, bridges.py, build_server.py and redeploy.py.

from __future__ import annotations

import enum
import sys
from collections.abc import Iterable
from typing import Final


class Host(enum.StrEnum):
	"""Values are the names a bridge writes in its pyproject.toml, not `sys.platform`'s."""

	WINDOWS = "windows"
	MACOS = "macos"
	LINUX = "linux"


ANY_HOST: Final = "*"

_BY_PLATFORM: Final[dict[str, Host]] = {
	"win32": Host.WINDOWS,
	"darwin": Host.MACOS,
	"linux": Host.LINUX,
}


def current() -> Host:
	try:
		return _BY_PLATFORM[sys.platform]
	except KeyError:
		known = ", ".join(sorted(_BY_PLATFORM))
		raise RuntimeError(
			f"unsupported host: sys.platform is {sys.platform!r}, and this repo knows {known}. "
			f"Add it to scripts/platforms.py if it is meant to be supported."
		) from None


HOST: Final[Host] = current()


def supports(hosts: Iterable[str]) -> bool:
	listed = tuple(hosts)
	return ANY_HOST in listed or HOST in listed


SERVER_BINARY_NAME: Final = "screenreader-mcp.exe" if HOST is Host.WINDOWS else "screenreader-mcp"
