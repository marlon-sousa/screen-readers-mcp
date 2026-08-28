# The host this checkout is being worked on, and the few facts that follow.
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
# ROLE: the ONE place anything under scripts/ reads `sys.platform`. Everything
# else asks this module, so "what does this repo do differently per host?" has a
# single answer that can be read in one screen -- and so adding a host is adding
# a member here rather than hunting for string comparisons.
#
# WHO USES IT: doctor.py (which checks are asked at all), bridges.py (whether a
# bridge's tier runs here), build_server.py and redeploy.py (the binary's name,
# and how to find a running one).
#
# WHAT IS DELIBERATELY NOT HERE: anything Go. The server is built and tested on
# every host with no guard, and its one host-shaped part -- the named-pipe
# transport -- is handled by Go's own build tags. See spec 0042, decision 1.

from __future__ import annotations

import enum
import sys
from collections.abc import Iterable
from typing import Final


class Host(enum.StrEnum):
	"""A machine this repo can be developed on.

	`StrEnum` so a member compares equal to the string a bridge writes in its
	`pyproject.toml` declaration, and so it prints as itself in a report. The
	values are OUR names, not `sys.platform`'s: `macos` rather than `darwin`,
	because these are read and written by people in TOML and in documentation.
	"""

	WINDOWS = "windows"
	MACOS = "macos"
	LINUX = "linux"


#: What a bridge writes when a tier has no host restriction at all.
ANY_HOST: Final = "*"

#: `sys.platform` is the only input; every other host question is derived.
#: `sys.platform` reports "linux" for every Linux, and "win32" even on 64-bit
#: Windows -- a historical name, not a claim about the word size.
_BY_PLATFORM: Final[dict[str, Host]] = {
	"win32": Host.WINDOWS,
	"darwin": Host.MACOS,
	"linux": Host.LINUX,
}


def current() -> Host:
	"""This machine, or a loud failure.

	An unrecognised platform RAISES rather than guessing a default. A wrong
	guess here would make every check downstream ask the wrong questions and
	answer them confidently, which is the one outcome the doctor exists to
	prevent.
	"""
	try:
		return _BY_PLATFORM[sys.platform]
	except KeyError:
		known = ", ".join(sorted(_BY_PLATFORM))
		raise RuntimeError(
			f"unsupported host: sys.platform is {sys.platform!r}, and this repo knows {known}. "
			f"Add it to scripts/platforms.py if it is meant to be supported."
		) from None


#: Resolved once, at import: it cannot change while the process runs.
HOST: Final[Host] = current()


def supports(hosts: Iterable[str]) -> bool:
	"""Is THIS host in a declared host list, where `*` means every host?"""
	listed = tuple(hosts)
	return ANY_HOST in listed or HOST in listed


#: The MCP server binary's filename on this host.
#:
#: The host's own convention for naming an executable and nothing more -- `.exe`
#: on Windows, bare elsewhere. A fully-qualified `-<os>-<arch>` name (what the
#: RELEASE artifacts carry, since those are downloaded by strangers who must
#: tell them apart) was considered and rejected for a build sitting in your own
#: checkout: it lengthens every path typed into an MCP config to solve a problem
#: -- two hosts sharing one checkout -- that nobody here has. Spec 0042.
SERVER_BINARY_NAME: Final = "screenreader-mcp.exe" if HOST is Host.WINDOWS else "screenreader-mcp"
