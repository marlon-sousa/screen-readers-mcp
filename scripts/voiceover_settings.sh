#!/bin/bash
# What does VoiceOver actually write when a setting is changed by hand?
# Copyright (C) 2026 Marlon Brandao de Sousa. GPL-2. See COPYING.txt.
#
#     bash scripts/voiceover_settings.sh snapshot before
#     ... change ONE setting in VoiceOver Utility ...
#     bash scripts/voiceover_settings.sh snapshot after
#     bash scripts/voiceover_settings.sh compare before after
#
# ROLE: the instrument for spec 0047's open questions 1 to 3. That spec found the
# voice's preference key and then failed to make VoiceOver honour a write to it,
# leaving three hypotheses and no way to choose between them.
#
# WHY OBSERVE RATHER THAN GUESS. Each hypothesis is a different guess about a
# mechanism nobody has watched: the CFPreferences domain versus the file, a
# journal entry, a companion key. Guessing costs one live round per guess against
# a reader that crashes routinely. Watching VoiceOver set the value ITSELF costs
# one round total and answers all three at once -- and it cannot be wrong about
# the mechanism, because it IS the mechanism. This is the same move spec 0041
# made when it stopped reasoning about the provider route and built one.
#
# IT IS READ-ONLY. It copies files and reads preferences. It never writes a
# setting, never restarts VoiceOver, and never touches the reader. The only thing
# that changes anything is the human, in VoiceOver Utility, between the two
# snapshots.
#
# THE TWO VIEWS ARE THE POINT. A preference has a file on disk AND a cfprefsd
# view, and they are not guaranteed to agree. Spec 0047 wrote the FILE and
# VoiceOver ignored it; Guidepup writes the DOMAIN. If a snapshot ever shows the
# two disagreeing, that alone answers open question 1 -- so both are captured
# every time, even though most runs will show them identical.
set -u

GROUP="$HOME/Library/Group Containers/group.com.apple.VoiceOver/Library/Preferences"
DEFAULT="$GROUP/com.apple.VoiceOver4/default.plist"
JOURNAL="$GROUP/com.apple.VoiceOver4/journal.plist"
LOCAL="$GROUP/com.apple.VoiceOver4.local.plist"
ROOT="${VOICEOVER_SNAPSHOT_DIR:-$HOME/.screenreader-mcp/voiceover-snapshots}"

usage() {
	echo "usage: $(basename "$0") snapshot <label>"
	echo "       $(basename "$0") compare <label> <label>"
	echo
	echo "  Snapshots live under $ROOT"
	exit 2
}

snapshot() {
	local label="$1" dir="$ROOT/$1"
	mkdir -p "$dir" || exit 1
	# The FILE view.
	for src in "$DEFAULT:default" "$JOURNAL:journal" "$LOCAL:local"; do
		local path="${src%:*}" name="${src##*:}"
		if [ -f "$path" ]; then
			plutil -convert xml1 -o "$dir/$name.xml" "$path" 2>/dev/null \
				|| echo "(could not convert $path)" > "$dir/$name.xml"
		else
			echo "(absent)" > "$dir/$name.xml"
		fi
	done
	# The cfprefsd DOMAIN view, which is what VoiceOver itself reads through.
	defaults read com.apple.VoiceOver4/default > "$dir/domain.txt" 2>&1
	{
		echo "captured   $(date '+%Y-%m-%d %H:%M:%S')"
		echo "macOS      $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
		echo "VoiceOver  $(pgrep -x VoiceOver || echo 'not running')"
	} > "$dir/context.txt"
	echo "snapshot '$label' written to $dir"
	sed 's/^/  /' "$dir/context.txt"
}

compare() {
	local a="$ROOT/$1" b="$ROOT/$2"
	[ -d "$a" ] && [ -d "$b" ] || { echo "no such snapshot: $a or $b" >&2; exit 1; }
	echo "== $1 -> $2"
	sed 's/^/  before: /' "$a/context.txt"; sed 's/^/  after:  /' "$b/context.txt"
	python3 - "$a" "$b" <<'PY'
import plistlib, subprocess, sys, os

before_dir, after_dir = sys.argv[1], sys.argv[2]

def load(directory, name):
	path = os.path.join(directory, f"{name}.xml")
	try:
		with open(path, "rb") as handle:
			return plistlib.load(handle)
	except Exception:
		return {}

for name in ("default", "journal", "local"):
	before, after = load(before_dir, name), load(after_dir, name)
	added   = {k: after[k]  for k in after  if k not in before}
	removed = {k: before[k] for k in before if k not in after}
	changed = {k: (before[k], after[k]) for k in after if k in before and before[k] != after[k]}
	if not (added or removed or changed):
		print(f"\n-- {name}.plist: no change")
		continue
	print(f"\n-- {name}.plist")
	for k, v in sorted(added.items()):
		print(f"   ADDED    {k} = {v!r}")
	for k, v in sorted(removed.items()):
		print(f"   REMOVED  {k}  (was {v!r})")
	for k, (was, now) in sorted(changed.items()):
		print(f"   CHANGED  {k}: {was!r} -> {now!r}")

# The two views, compared. If these ever disagree, that IS the answer to spec
# 0047's open question 1 and nothing else needs measuring.
same = subprocess.run(["diff", "-q", os.path.join(before_dir, "domain.txt"),
                       os.path.join(after_dir, "domain.txt")], capture_output=True)
print(f"\n-- cfprefsd domain view: {'no change' if same.returncode == 0 else 'CHANGED (see domain.txt)'}")
PY
}

case "${1:-}" in
	snapshot) [ $# -eq 2 ] || usage; snapshot "$2" ;;
	compare)  [ $# -eq 3 ] || usage; compare "$2" "$3" ;;
	*) usage ;;
esac
