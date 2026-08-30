// ROLE: entity -- `waitForSpeechToFinish`'s params and result.
//
// Pure. Built by the WaitForSpeechToFinish handler (entry 13.5), which waits for
// the buffer to stop growing rather than for the audio to stop: on the macOS
// capture route the utterance reaches the bridge before any audio exists, and in
// silent mode there is no audio at all.
//
// The type names are the contract's -- WaitToFinishParams, not
// WaitForSpeechToFinishParams -- so the binding and the schema compare by name.

public struct WaitToFinishParams: Codable, Equatable, Sendable {
	public var timeout: Double = 5.0

	public init(timeout: Double = 5.0) {
		self.timeout = timeout
	}

	public init(from decoder: any Decoder) throws {
		let box = try decoder.container(keyedBy: CodingKeys.self)
		timeout = try box.decode(Double.self, forKey: .timeout, orDefault: timeout)
	}
}

public struct WaitToFinishResult: Codable, Equatable, Sendable {
	public var finished: Bool

	public init(finished: Bool) {
		self.finished = finished
	}
}
