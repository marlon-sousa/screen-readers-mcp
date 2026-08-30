// A hand-written stateful fake for the VoiceStore adapter seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/VoiceStore.swift.
//
// An in-memory preference. It ACCEPTS the write and remembers it, so the
// lifecycle's own confirmation step is exercised against a store that behaved --
// and `rejectsWrites` makes it behave like the real one under the type trap:
// the write appears to succeed and the value is not what was asked for (spec
// 0047, finding 17). That is the case a fake that only threw could not produce.

@testable import VoiceOverBridgeAdapters

public final class FakeVoiceStore: VoiceStore {
	public var voice: String?
	/// When true, `select` returns normally and the stored value does not change
	/// -- the shape of a record VoiceOver silently rejected.
	public var rejectsWrites = false
	/// When set, `select` throws instead.
	public var failure: VoiceStoreError?
	public private(set) var writes: [String] = []

	public init(voice: String? = nil) {
		self.voice = voice
	}

	public func selectedVoice() -> String? { voice }

	public func select(_ identifier: String) throws {
		writes.append(identifier)
		if let failure { throw failure }
		guard !rejectsWrites else { return }
		voice = identifier
	}
}
