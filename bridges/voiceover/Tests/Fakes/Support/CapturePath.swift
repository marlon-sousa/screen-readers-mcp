// Test scaffolding: capture and marker paths that no real capture voice writes or reads.

import Foundation

public func unusedCapturePath(_ label: String = "capture") -> String {
	NSTemporaryDirectory() + "screen-readers-mcp-\(label)-\(UUID().uuidString).jsonl"
}

public func unusedMarkerPath(_ label: String = "marker") -> String {
	NSTemporaryDirectory() + "screen-readers-mcp-\(label)-\(UUID().uuidString).silent"
}
