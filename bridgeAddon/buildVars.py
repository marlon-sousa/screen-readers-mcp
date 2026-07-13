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
		"""Test-automation bridge for NVDA. Lets an AI agent functionally test NVDA add-ons: it drives NVDA with keyboard gestures and reads back what NVDA would speak and braille.

The add-on is inert until a test session connects: it never swaps your synthesizer or installs hooks with side effects while idle, so it is safe to leave permanently installed. Pair it with the nvda-mcp server (see the add-on documentation for setup)."""
	),
	# Translators: what's new text for this add-on version shown in add-on store.
	addon_changelog=_("""First release."""),
	addon_version="0.1.0",
	addon_author="Marlon Brandão de Sousa <marlon.bsousa@gmail.com>",
	addon_url="https://github.com/marlon-sousa/nvda-mcp",
	addon_sourceURL="https://github.com/marlon-sousa/nvda-mcp",
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


pythonSources: list[str] = [
	"addon/globalPlugins/nvdaMcpBridge/*.py",
	"addon/synthDrivers/nvdaMcpSpy.py",
]
i18nSources: list[str] = pythonSources + ["buildVars.py"]

# Paths are relative to the addon directory when building the bundle.
excludedFiles: list[str] = [
	"doc/*/contributing*.*",
	"doc/*/*.tpl.md",
]

baseLanguage: str = "en"
markdownExtensions: list[str] = []

brailleTables: BrailleTables = {}
symbolDictionaries: SymbolDictionaries = {}
