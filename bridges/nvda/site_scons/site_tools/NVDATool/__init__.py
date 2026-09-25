"""Builders for NVDA add-ons: NVDAAddon, NVDAManifest, NVDATranslatedManifest and md2html.

The manifest needs addon_info, brailleTables and symbolDictionaries; the HTML needs moFile and mdExtensions.
"""

from SCons.Script import Environment, Builder

from .addon import createAddonBundleFromPath
from .manifests import generateManifest, generateTranslatedManifest
from .docs import md2html



def generate(env: Environment):
	env.SetDefault(excludePatterns=tuple())

	addonAction = env.Action(
		lambda target, source, env: createAddonBundleFromPath(
			source[0].abspath, target[0].abspath, env["excludePatterns"]
		) and None,
		lambda target, source, env: f"Generating Addon {target[0]}",
	)
	env["BUILDERS"]["NVDAAddon"] = Builder(
		action=addonAction,
		suffix=".nvda-addon",
		src_suffix="/"
	)

	env.SetDefault(brailleTables={})
	env.SetDefault(symbolDictionaries={})

	manifestAction = env.Action(
		lambda target, source, env: generateManifest(
			source[0].abspath,
			target[0].abspath,
			addon_info=env["addon_info"],
			brailleTables=env["brailleTables"],
			symbolDictionaries=env["symbolDictionaries"],
		) and None,
		lambda target, source, env: f"Generating manifest {target[0]}",
	)
	env["BUILDERS"]["NVDAManifest"] = Builder(
		action=manifestAction,
		suffix=".ini",
		src_siffix=".ini.tpl"
	)

	translatedManifestAction = env.Action(
		lambda target, source, env: generateTranslatedManifest(
			source[1].abspath,
			target[0].abspath,
			mo=source[0].abspath,
			addon_info=env["addon_info"],
			brailleTables=env["brailleTables"],
			symbolDictionaries=env["symbolDictionaries"],
		) and None,
		lambda target, source, env: f"Generating translated manifest {target[0]}",
	)

	env["BUILDERS"]["NVDATranslatedManifest"] = Builder(
		action=translatedManifestAction,
		suffix=".ini",
		src_siffix=".ini.tpl"
	)

	env.SetDefault(mdExtensions = {})

	mdAction = env.Action(
		lambda target, source, env: md2html(
			source[0].path,
			target[0].path,
			moFile=env["moFile"].path if env["moFile"] else None,
			mdExtensions=env["mdExtensions"],
			addon_info=env["addon_info"],
		) and None,
		lambda target, source, env: f"Generating {target[0]}",
	)
	env["BUILDERS"]["md2html"] = env.Builder(
		action=mdAction,
		suffix=".html",
		src_suffix=".md",
	)


def exists():
	return True
