// Hand-written stateful fake for the VoiceStore adapter seam.

@testable import VoiceOverBridgeAdapters

public final class FakeVoiceStore: VoiceStore {
	public var voice: String?
	public var rejectsWrites = false
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
