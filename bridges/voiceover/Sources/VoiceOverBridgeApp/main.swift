// ROLE: the container app -- element 3, 4 and 5 of the five (spec 0046, part 3),
// once they exist.
//
// TODAY IT IS ONLY A CONTAINER, and that is not a placeholder: a macOS app
// extension cannot be installed on its own. The .appex ships inside an app's
// Contents/PlugIns and the system registers it from there, so this bundle has to
// exist before anything else in the lane can.
//
// It deliberately does nothing but report where it is, so that "the voice did not
// appear" is never ambiguous between a broken app and a broken extension.
// Printing is this target's whole purpose -- it is run from a terminal by a human
// diagnosing a registration; nothing inside CaptureVoice prints, because a
// synchronous console write there would be paid on the thread that has to start
// synthesis.
//
// WHAT IT BECOMES: the bridge session on a background thread (13.4), the input
// path (13.7, 13.8), and the control dialog on AppKit's main thread (13.10). At
// that point it gains VoiceOverBridgeDomain, VoiceOverBridgeAdapters and
// ScreenReaderWire as dependencies, and Wiring.swift becomes the answer to "who
// connects what".

import Foundation

let bundle = Bundle.main
print("host bundle: \(bundle.bundlePath)")
print("identifier: \(bundle.bundleIdentifier ?? "<none>")")
if let plugins = bundle.builtInPlugInsPath {
	let contents = (try? FileManager.default.contentsOfDirectory(atPath: plugins)) ?? []
	print("plugins: \(contents.joined(separator: ", "))")
}
