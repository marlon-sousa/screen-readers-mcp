// Hand-written stateful fake for the LoopbackBinder seam.

import VoiceOverBridgeAdapters

public final class FakeLoopbackBinder: LoopbackBinder {
	public private(set) var boundHosts: [String] = []
	public private(set) var boundPorts: [Int] = []
	public private(set) var closeCount = 0
	public var answersWithPort: Int?
	public var bindFailure: (any Error)?
	public var connections: [any Transport] = []

	public init(answersWithPort: Int? = nil) {
		self.answersWithPort = answersWithPort
	}

	public func bind(host: String, port: Int) throws -> Int {
		boundHosts.append(host)
		boundPorts.append(port)
		if let bindFailure { throw bindFailure }
		return answersWithPort ?? port
	}

	public func accept() throws -> any Transport {
		guard !connections.isEmpty else { throw PollTimeout() }
		return connections.removeFirst()
	}

	public func close() {
		closeCount += 1
	}
}
