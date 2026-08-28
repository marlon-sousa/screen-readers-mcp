// SPIKE (spec 0041, group A). The container app, which exists only because a
// macOS app extension cannot be installed on its own: the .appex ships inside
// an app's Contents/PlugIns, and the system registers it from there.
//
// It deliberately does nothing but stay alive briefly and print where it is, so
// that "the voice did not appear" is never ambiguous between a broken app and a
// broken extension.

import Foundation

let bundle = Bundle.main
print("host bundle: \(bundle.bundlePath)")
print("identifier: \(bundle.bundleIdentifier ?? "<none>")")
if let plugins = bundle.builtInPlugInsPath {
	let contents = (try? FileManager.default.contentsOfDirectory(atPath: plugins)) ?? []
	print("plugins: \(contents.joined(separator: ", "))")
}
