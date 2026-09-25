// ROLE: the container app that carries the capture voice extension and prints where it is.

import Foundation

let bundle = Bundle.main
print("host bundle: \(bundle.bundlePath)")
print("identifier: \(bundle.bundleIdentifier ?? "<none>")")
if let plugins = bundle.builtInPlugInsPath {
	let contents = (try? FileManager.default.contentsOfDirectory(atPath: plugins)) ?? []
	print("plugins: \(contents.joined(separator: ", "))")
}
