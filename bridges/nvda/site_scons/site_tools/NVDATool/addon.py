import zipfile
from collections.abc import Iterable
from pathlib import Path



def matchesNoPatterns(path: Path, patterns: Iterable[str]) -> bool:
	return not any((path.match(pattern) for pattern in patterns))


def createAddonBundleFromPath(path: str | Path, dest: str, excludePatterns: Iterable[str]):
	if isinstance(path, str):
		path = Path(path)
	basedir = path.absolute()
	with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as z:
		for p in basedir.rglob("*"):
			if p.is_dir():
				continue
			pathInBundle = p.relative_to(basedir)
			if matchesNoPatterns(pathInBundle, excludePatterns):
				z.write(p, pathInBundle)
	return dest
