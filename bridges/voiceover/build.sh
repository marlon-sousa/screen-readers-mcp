#!/bin/bash
# Builds the VoiceOver bridge's shippable artifacts: the container app, the
# speech-provider extension inside it, the audio-unit framework inside that, and
# the diagnostic probe beside them.
#
# WHY BY HAND, AND WHY NOT ENTIRELY FROM SwiftPM. SwiftPM cannot emit .app or
# .appex bundles at all, so something has to assemble them. It also cannot
# express the two things this bundle's shape depends on -- a framework layout
# with a Versions/A symlink farm, and an `-install_name` of
# @rpath/CaptureVoice.framework/Versions/A/CaptureVoice -- so the framework is
# compiled here with swiftc, exactly as it was when VoiceOver spoke through it for
# an hour. The PROBE is taken from SwiftPM's build products, because nothing about
# it needs a bundle.
#
# A 200-line script says exactly what the bundle contains and what it is signed
# with; a project.pbxproj says the same thing in a format nobody can review. The
# shape is copied from Apple's own SiriAUSP.appex on macOS 15.0, read with plutil
# -- ground truth for this OS version rather than a recalled doc.
#
# THREE FINDINGS ARE BUILT IN HERE, each of which failed SILENTLY when it was
# wrong (spec 0041, A1):
#
#  1. SANDBOXED, ALWAYS. An unsandboxed speech provider is not rejected with an
#     error: `pluginkit -a` returns success, nothing appears, and the reason is
#     only in pkd's log -- "plug-ins must be sandboxed". So this is no longer the
#     flag it was in the spike; it is what the script does.
#  2. NO NETWORK ENTITLEMENT. With com.apple.security.network.client present the
#     extension registers, launches, and has its audio unit constructed -- and the
#     system never asks it for its voices, logging "Skipping network entitled
#     extension" from AXTTSCommon. Removing that one entitlement was the whole
#     difference between 190 voices and 191. It is also why the bridge reads a
#     FILE rather than a socket: this is not a limitation to work around, it is
#     the rule.
#  3. NO AudioComponentBundle. That key asks clients to dlopen the unit in their
#     own process, and declaring it stopped the voice working altogether -- not
#     even enumeration survived. Consistent with library validation: the clients
#     are Apple-signed and this framework is ad-hoc signed.
#
# Usage: ./build.sh [--network] [--in-process]
#   --network     ADD the network entitlement, reproducing failure 2.
#   --in-process  ADD AudioComponentBundle, reproducing failure 3.
#
# Both flags exist for one reason: a negative result that cannot be re-run is not
# a result. Build with neither for the configuration that works.
set -euo pipefail
cd "$(dirname "$0")"

NETWORK=0
IN_PROCESS=0
for arg in "$@"; do
	case "$arg" in
		--network) NETWORK=1 ;;
		--in-process) IN_PROCESS=1 ;;
		*) echo "unknown flag: $arg" >&2; exit 2 ;;
	esac
done

# THE BUNDLE IDENTITY IS FROZEN, AND THE "spike" IN IT IS DELIBERATE.
#
# The voice identifier VoiceOver stores when a user selects our voice is derived
# from EXT_ID, so changing any of these names costs every user -- today, the
# maintainer -- a trip to VoiceOver Utility to re-select a voice that silently
# vanished. Entry 13.2 promotes the code; entry 13.11 owns packaging and
# identifiers, and is where that one-time cost is worth paying. See README.md.
APP_NAME="VoiceOverCaptureSpike"
APP_ID="org.screen-readers-mcp.spike.capture"
EXT_NAME="CaptureVoice"
EXT_ID="$APP_ID.voice"
# The Swift module, and therefore the first half of NSExtensionPrincipalClass.
# It matches the SwiftPM target name in Package.swift on purpose: two spellings of
# one module is how a rename half-lands.
MODULE="CaptureVoice"
STUB_MODULE="CaptureVoiceExtension"
TARGET="$(uname -m)-apple-macos14.0"

# THE VERSION IS DECLARED IN SWIFT AND DERIVED HERE, not spelled twice (13.11).
#
# Until then Wiring said `0.1.0-dev` while all three plists below said `1.0`, so
# the version an agent read in `hello` and the version macOS shows in Get Info
# were unrelated numbers. Sources/VoiceOverBridgeAdapters/BridgeVersion.swift is
# now the one declaration and this reads it -- lane 1's shape, where buildVars.py
# declares `addon_version` and scons reads it, for lane 1's reason: the value
# belongs with the code that ships it.
#
# EXTRACTED BY sed RATHER THAN BY A SWIFT BUILD, because this runs before
# anything is compiled and must work when nothing compiles at all. It depends on
# that file's declaration keeping its shape -- a `let` with a double-quoted
# literal -- which that file's header says in as many words. A missing or
# unreadable value FAILS the build rather than defaulting: a bundle stamped with
# an empty version installs fine and is then impossible to tell apart from any
# other build of it.
VERSION_FILE="Sources/VoiceOverBridgeAdapters/BridgeVersion.swift"
VERSION="$(sed -n 's/^public let voiceOverBridgeVersion = "\(.*\)"$/\1/p' "$VERSION_FILE")"
if [[ -z "$VERSION" ]]; then
	echo "could not read the bridge version from $VERSION_FILE" >&2
	echo "it must contain a line of the form: public let voiceOverBridgeVersion = \"1.2.3\"" >&2
	exit 1
fi

BUILD="build"
APP="$BUILD/$APP_NAME.app"
EXT="$APP/Contents/PlugIns/$EXT_NAME.appex"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$EXT/Contents/MacOS"

FW_ID="$APP_ID.au"
FW="$EXT/Contents/Frameworks/$MODULE.framework"
mkdir -p "$FW/Versions/A/Modules" "$FW/Versions/A/Resources"

# Every .swift under Sources/CaptureVoice, recursively: the module is laid out as
# Domain/Ports, Domain/Entities, Domain/Controllers and Adapters, and a flat glob
# would have compiled an empty module while reporting success.
VOICE_SOURCES=()
while IFS= read -r file; do VOICE_SOURCES+=("$file"); done < <(find Sources/CaptureVoice -name '*.swift' | sort)
echo "== compiling audio-unit framework ($TARGET, ${#VOICE_SOURCES[@]} files)"
swiftc \
	-emit-library -emit-module \
	-module-name "$MODULE" \
	-target "$TARGET" \
	-framework Foundation -framework AVFoundation -framework AudioToolbox \
	-Xlinker -install_name -Xlinker "@rpath/$MODULE.framework/Versions/A/$MODULE" \
	-emit-module-path "$FW/Versions/A/Modules/$MODULE.swiftmodule" \
	-o "$FW/Versions/A/$MODULE" \
	"${VOICE_SOURCES[@]}"

cat > "$FW/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>$MODULE</string>
	<key>CFBundleIdentifier</key><string>$FW_ID</string>
	<key>CFBundleName</key><string>$MODULE</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST

ln -sf A "$FW/Versions/Current"
ln -sf Versions/Current/"$MODULE" "$FW/$MODULE"
ln -sf Versions/Current/Modules "$FW/Modules"
ln -sf Versions/Current/Resources "$FW/Resources"

echo "== compiling extension stub ($TARGET)"
# -e _NSExtensionMain: an app extension's entry point is NSExtensionMain, not
# main(). This is the one linker flag Xcode would otherwise supply invisibly, and
# it is why the stub is a LIBRARY target in Package.swift and its file is named
# Stub.swift rather than main.swift.
swiftc \
	-module-name "$STUB_MODULE" \
	-parse-as-library \
	-target "$TARGET" \
	-F "$EXT/Contents/Frameworks" -I "$FW/Versions/A/Modules" \
	-framework "$MODULE" -framework Foundation \
	-Xlinker -rpath -Xlinker "@loader_path/../Frameworks" \
	-Xlinker -e -Xlinker _NSExtensionMain \
	-o "$EXT/Contents/MacOS/$EXT_NAME" \
	Sources/CaptureVoiceExtension/Stub.swift

echo "== compiling container app"
swiftc -target "$TARGET" -o "$APP/Contents/MacOS/$APP_NAME" Sources/VoiceOverBridgeApp/main.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundleIdentifier</key><string>$APP_ID</string>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
</dict></plist>
PLIST

# Mirrors SiriAUSP.appex / MauiAUSP.appex: package type XPC!, extension point
# com.apple.AudioUnit-Speech, one AudioComponents entry of type ausp. See
# finding 3 above for AudioComponentBundle.
COMPONENT_BUNDLE=""
[[ $IN_PROCESS == 1 ]] && COMPONENT_BUNDLE="<key>AudioComponentBundle</key><string>$FW_ID</string>"

cat > "$EXT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>$EXT_NAME</string>
	<key>CFBundleIdentifier</key><string>$EXT_ID</string>
	<key>CFBundleName</key><string>$EXT_NAME</string>
	<key>CFBundlePackageType</key><string>XPC!</string>
	<key>CFBundleShortVersionString</key><string>$VERSION</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSExtension</key><dict>
		<key>NSExtensionAttributes</key><dict>
			<key>AudioComponents</key><array><dict>
				<key>description</key><string>screen-readers-mcp capture voice</string>
				<key>manufacturer</key><string>SRMC</string>
				<key>name</key><string>screen-readers-mcp: Capture Spike</string>
				<key>sandboxSafe</key><true/>
				<key>subtype</key><string>cap1</string>
				<key>tags</key><array><string>Speech Synthesizer</string></array>
				<key>type</key><string>ausp</string>
				<key>version</key><integer>1</integer>
			</dict></array>
			$COMPONENT_BUNDLE
		</dict>
		<key>NSExtensionPointIdentifier</key><string>com.apple.AudioUnit-Speech</string>
		<key>NSExtensionPrincipalClass</key><string>$MODULE.AudioUnitFactory</string>
	</dict>
</dict></plist>
PLIST

codesign --force --sign - --timestamp=none "$FW/Versions/A"

# THE SANDBOX IS NOT OPTIONAL (finding 1). The app group was requested during the
# spike and turned out to be unnecessary for the extension-to-bridge direction --
# the container file is readable by an ordinary unsandboxed process without it --
# but it is kept because removing it is a change to the container path, and the
# path is what entry 13.5 reads.
NETWORK_ENTITLEMENT=""
[[ $NETWORK == 1 ]] && NETWORK_ENTITLEMENT="<key>com.apple.security.network.client</key><true/>"
cat > "$BUILD/ext.entitlements" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>com.apple.security.app-sandbox</key><true/>
	$NETWORK_ENTITLEMENT
	<key>com.apple.security.application-groups</key><array><string>group.$APP_ID</string></array>
</dict></plist>
PLIST
codesign --force --sign - --timestamp=none --entitlements "$BUILD/ext.entitlements" "$EXT"
codesign --force --sign - --timestamp=none "$APP"

echo "== building probe (from SwiftPM's build products)"
# The one artifact that needs no bundle, so it is the one SwiftPM can produce
# outright. It links CaptureVoice statically, which is also what keeps the probe
# honest: it exercises the SAME controller and adapters the extension does.
swift build -c release --product CaptureProbe > /dev/null
cp "$(swift build -c release --product CaptureProbe --show-bin-path)/CaptureProbe" "$BUILD/probe"

echo "== built $APP (network=$NETWORK in-process=$IN_PROCESS)"
codesign -dv --entitlements - "$EXT" 2>&1 | sed 's/^/   /'
