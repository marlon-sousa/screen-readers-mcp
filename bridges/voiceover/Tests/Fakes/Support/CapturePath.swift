// SCAFFOLDING, not a port double -- which is why it is in Support/ rather than
// beside the fakes.
//
// A session's factory needs a path to the capture voice's feed, and most tests
// do not care what is in it: they drive the reader edge through a fake source or
// they are asserting something else entirely. What they must NOT do is point at
// the developer's own container file, where a real reader may be appending: a
// test that read that would pass or fail depending on whether VoiceOver happened
// to be talking.
//
// So this hands out a path in a fresh temporary directory that nothing writes
// to. The tailer polls it, finds nothing, and stops when the session tears down.

import Foundation

/// A path no capture voice writes to, unique per call.
public func unusedCapturePath(_ label: String = "capture") -> String {
	NSTemporaryDirectory() + "screen-readers-mcp-\(label)-\(UUID().uuidString).jsonl"
}
