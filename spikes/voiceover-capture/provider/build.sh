#!/bin/bash
# SPIKE (spec 0041, group A). Builds the container app and its speech-provider
# extension by hand -- no Xcode project.
#
# Why by hand: this is evidence, and evidence has to be re-runnable by someone
# else (the 2026-08-22 fixture rule). A 40-line script says exactly what the
# bundle contains and what it is signed with; a project.pbxproj says it in a
# format nobody can review. The bundle shape is copied from Apple's own
# SiriAUSP.appex on macOS 15.0, read with plutil.
#
# Usage: ./build.sh [--sandbox]
#   --sandbox  sign the extension with App Sandbox + network client + app group.
#              Group B's question. Off by default so group A measures the feed
#              itself and not the sandbox.
set -euo pipefail
cd "$(dirname "$0")"

SANDBOX=0
NETWORK=0
IN_PROCESS=0
for arg in "$@"; do
	case "$arg" in
		--sandbox) SANDBOX=1 ;;
		--network) NETWORK=1 ;;
		--in-process) IN_PROCESS=1 ;;
		*) echo "unknown flag: $arg" >&2; exit 2 ;;
	esac
done

APP_NAME="VoiceOverCaptureSpike"
APP_ID="org.screen-readers-mcp.spike.capture"
EXT_NAME="CaptureVoice"
EXT_ID="$APP_ID.voice"
MODULE="VOCaptureVoice"
TARGET="$(uname -m)-apple-macos14.0"

BUILD="build"
APP="$BUILD/$APP_NAME.app"
EXT="$APP/Contents/PlugIns/$EXT_NAME.appex"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$EXT/Contents/MacOS"

FW_ID="$APP_ID.au"
FW="$EXT/Contents/Frameworks/$MODULE.framework"
mkdir -p "$FW/Versions/A/Modules" "$FW/Versions/A/Resources"

echo "== compiling audio-unit framework ($TARGET)"
swiftc \
	-emit-library -emit-module \
	-module-name "$MODULE" \
	-target "$TARGET" \
	-framework Foundation -framework AVFoundation -framework AudioToolbox \
	-Xlinker -install_name -Xlinker "@rpath/$MODULE.framework/Versions/A/$MODULE" \
	-emit-module-path "$FW/Versions/A/Modules/$MODULE.swiftmodule" \
	-o "$FW/Versions/A/$MODULE" \
	Sources/Voice/*.swift

cat > "$FW/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>$MODULE</string>
	<key>CFBundleIdentifier</key><string>$FW_ID</string>
	<key>CFBundleName</key><string>$MODULE</string>
	<key>CFBundlePackageType</key><string>FMWK</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST

ln -sf A "$FW/Versions/Current"
ln -sf Versions/Current/"$MODULE" "$FW/$MODULE"
ln -sf Versions/Current/Modules "$FW/Modules"
ln -sf Versions/Current/Resources "$FW/Resources"

echo "== compiling extension stub ($TARGET)"
# -e _NSExtensionMain: an app extension's entry point is NSExtensionMain, not
# main(). This is the one linker flag Xcode would otherwise supply invisibly.
swiftc \
	-module-name "${MODULE}Stub" \
	-parse-as-library \
	-target "$TARGET" \
	-F "$EXT/Contents/Frameworks" -I "$FW/Versions/A/Modules" \
	-framework "$MODULE" -framework Foundation \
	-Xlinker -rpath -Xlinker "@loader_path/../Frameworks" \
	-Xlinker -e -Xlinker _NSExtensionMain \
	-o "$EXT/Contents/MacOS/$EXT_NAME" \
	Sources/Stub/stub.swift

echo "== compiling host app"
swiftc -target "$TARGET" -o "$APP/Contents/MacOS/$APP_NAME" Sources/Host/main.swift

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundleIdentifier</key><string>$APP_ID</string>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
</dict></plist>
PLIST

# Mirrors SiriAUSP.appex / MauiAUSP.appex: package type XPC!, extension point
# com.apple.AudioUnit-Speech, one AudioComponents entry of type ausp.
# AudioComponentBundle names a bundle the CLIENT dlopens to instantiate the unit
# IN ITS OWN PROCESS. Measured on macOS 15.0: declaring it stopped the voice
# working entirely -- axassetsd no longer even enumerated it -- which is what
# library validation predicts, since the clients are Apple-signed and the
# framework is ad-hoc signed. Left behind a flag because a negative result that
# cannot be re-run is not a result.
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
	<key>CFBundleShortVersionString</key><string>1.0</string>
	<key>CFBundleVersion</key><string>1</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>NSExtension</key><dict>
		<key>NSExtensionAttributes</key><dict>
			<key>AudioComponents</key><array><dict>
				<key>description</key><string>screen-readers-mcp capture spike</string>
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

if [[ $SANDBOX == 1 ]]; then
	# The network entitlement is a FLAG, not a default, and that is the whole
	# point of probe B1: macOS logs "Skipping network entitled extension" and
	# refuses to publish the voice at all when a speech provider asks for
	# network access. Turning it on is how that is demonstrated rather than
	# asserted.
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
else
	codesign --force --sign - --timestamp=none "$EXT"
fi
codesign --force --sign - --timestamp=none "$APP"

echo "== compiling probe"
# The probe compiles the audio-unit sources IN, rather than linking the
# framework, so it can exercise PassThrough directly without those types having
# to be public for the sake of a test.
swiftc -target "$TARGET" \
	-framework AVFoundation -framework AudioToolbox \
	-o "$BUILD/probe" Sources/Probe/main.swift Sources/Voice/*.swift

echo "== built $APP (sandbox=$SANDBOX network=$NETWORK in-process=$IN_PROCESS)"
codesign -dv --entitlements - "$EXT" 2>&1 | sed 's/^/   /'
