// A hand-written stateful fake for the LoopbackBinder seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/LoopbackBinder.swift.
//
// It answers with a port of its own choosing, which is how TCPListener's test
// proves the endpoint it reports is the port BOUND rather than the port asked
// for -- the difference that matters whenever somebody asks for port 0.

import VoiceOverBridgeAdapters

public final class FakeLoopbackBinder: LoopbackBinder {
	public private(set) var boundHosts: [String] = []
	public private(set) var boundPorts: [Int] = []
	public private(set) var closeCount = 0
	/// What `bind` answers with, whatever it was asked for.
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
