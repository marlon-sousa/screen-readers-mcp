// ROLE: entity, `waitForSpeechToFinish`'s params and result.

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
