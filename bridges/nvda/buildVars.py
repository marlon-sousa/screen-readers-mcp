# Build customizations
# Change this file instead of sconstruct or manifest files, whenever possible.

from site_scons.site_tools.NVDATool.typings import AddonInfo, BrailleTables, SymbolDictionaries
from site_scons.site_tools.NVDATool.utils import _

addon_info = AddonInfo(
	addon_name="nvdaMcpBridge",
	# Translators: Summary/title for this add-on.
	addon_summary=_("NVDA MCP Bridge"),
	# Translators: Long description for this add-on in add-on store.
	addon_description=_(
		"""A bridge that lets an AI agent drive NVDA: send keyboard gestures, read back what NVDA would speak and braille, and introspect its state. Its first use is functional testing of NVDA add-ons, but the same primitives support a wider range of agent-driven NVDA workflows.

The add-on is inert until a session connects: it never swaps your synthesizer or installs hooks with side effects while idle, so it is safe to leave permanently installed. Pair it with the nvda-mcp server (see the add-on documentation for setup)."""
	),
	# Translators: what's new text for this add-on version shown in add-on store.
	addon_changelog=_("""First release."""),
	addon_version="0.1.0",
	addon_author="Marlon Brandão de Sousa <marlon.bsousa@gmail.com>",
	addon_url="https://github.com/marlon-sousa/screen-readers-mcp",
	addon_sourceURL="https://github.com/marlon-sousa/screen-readers-mcp",
	addon_docFileName="readme.html",
	# 2026.1 is an addon API compat break point; nothing older can load this.
	addon_minimumNVDAVersion="2026.1.0",
	addon_lastTestedNVDAVersion="2026.1.0",
	addon_updateChannel=None,
	# GPL v2 or later: the spy synth driver is adapted from NVDA's own GPL-2
	# system tests, and the addon loads into NVDA (GPL-2).
	addon_license="GNU General Public License version 2 or later",
	addon_licenseURL="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html",
)


# RECURSIVE on purpose: this addon is a hexagonal PACKAGE (adapters/, domain/,
# ...), not the usual flat globalPlugins/<name>.py. sconstruct turns each of
# these into a build dependency of the .nvda-addon, so the non-recursive "*.py"
# the template ships with would track only the top-level files -- editing an
# adapter would leave the build "up to date" and ship stale code. "**/*.py"
# matches every module at any depth (including the top level).
pythonSources: list[str] = [
	"addon/globalPlugins/nvdaMcpBridge/**/*.py",
]
i18nSources: list[str] = [*pythonSources, "buildVars.py"]

# NON-PYTHON FILES THE ADDON SHIPS AND READS AT RUN TIME -- today, the persona
# guidance documents `getGuidance` serves (spec 0029). The bundler rglobs the
# whole addon tree, so these are packaged whether or not they are named here;
# what this list buys is that scons treats an EDITED one as a reason to rebuild.
#
# Without it the failure is silent and total: reword a document, run
# `poe build-bridge`, get "is up to date", install an addon carrying the previous
# text, and read it back believing it is what the file says. That is this
# platform's version of the trap //go:embed has on the server side -- there the
# bytes are copied at compile time and a stale binary serves old prose; here they
# are read at run time and a stale BUNDLE ships old prose. Same class, opposite
# mechanism, and neither is caught by anything else.
#
# Kept OUT of i18nSources, deliberately: that list is fed to xgettext, which
# parses its inputs as Python. These documents are for the agent, not the human
# at the reader, and are not translated.
bundledDataSources: list[str] = [
	"addon/globalPlugins/nvdaMcpBridge/**/documents/*.md",
]

# Paths are relative to the addon directory when building the bundle.
excludedFiles: list[str] = [
	"doc/*/contributing*.*",
	"doc/*/*.tpl.md",
	# The bundler rglobs the whole addon tree, so a developer's compiled bytecode
	# was being shipped to users -- 90-odd entries, INCLUDING ORPHANS from modules
	# deleted long ago (framing, session, speech_buffer and transcript, back when
	# they lived at the top level rather than under domain/). Inert, because
	# Python will not import a .pyc with no source beside it, but it is dead
	# weight from a layout that no longer exists, and the contents of a release
	# then depend on whose machine built it.
	"**/__pycache__/*",
	"**/__pycache__",
]

baseLanguage: str = "en"
markdownExtensions: list[str] = []

brailleTables: BrailleTables = {}
symbolDictionaries: SymbolDictionaries = {}
