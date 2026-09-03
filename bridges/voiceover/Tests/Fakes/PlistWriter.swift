// A hand-written stateful fake for the PlistWriter adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/PlistWriter.swift.
//
// It records EVERY write with its path and its format, because both are
// assertions the store above it has to earn: the file written must be the same
// one that was read (never the legacy path when the current one answered), and
// the format must be the one the file was already in -- a plist silently
// re-serialized as XML is the kind of change nobody reviews.
//
// IT DOES NOT FEED THE READER BACK AUTOMATICALLY, and that is deliberate: the
// store CONFIRMS its write by reading the key back, and a fake that made that
// confirmation succeed for free would make the confirmation untestable. A test
// wires `onWrite` to move the fake reader when it wants a write that took, and
// leaves it alone when it wants one that did not.

import Foundation
import VoiceOverBridgeAdapters

public final class FakePlistWriter: PlistWriter {
	public struct Write {
		public let plist: [String: Any]
		public let path: String
		public let format: PropertyListSerialization.PropertyListFormat
	}

	public private(set) var writes: [Write] = []

	/// What the next write does. Set to drive the store's named failure.
	public var failure: PlistWriteFailure?

	/// Called on each accepted write, so a test can make the reader answer with
	/// what was just written -- which is what a real file does.
	public var onWrite: (([String: Any], String) -> Void)?

	public init() {}

	public func write(
		_ plist: [String: Any], to path: String,
		format: PropertyListSerialization.PropertyListFormat
	) throws {
		if let failure { throw failure }
		writes.append(Write(plist: plist, path: path, format: format))
		onWrite?(plist, path)
	}
}
