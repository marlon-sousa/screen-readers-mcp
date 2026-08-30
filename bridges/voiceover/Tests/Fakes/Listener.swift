// A hand-written stateful fake for the Listener seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/Listener.swift.
//
// It scripts the three things an accept loop has to survive -- a connection, an
// idle poll, and a fault -- and it goes on timing out once the script is spent,
// so a server under test keeps accepting until the test stops it rather than
// falling out of its loop on its own.

import Foundation
import VoiceOverBridgeAdapters

public final class FakeListener: Listener {
	public enum Step {
		case connection(any Transport)
		case idle
		case fault(any Error)
	}

	private let lock = NSLock()
	private var script: [Step]
	public let endpoint: String
	public private(set) var openCount = 0
	public private(set) var closeCount = 0

	public init(endpoint: String = "fake-endpoint", script: [Step] = []) {
		self.endpoint = endpoint
		self.script = script
	}

	public func open() throws {
		lock.lock()
		openCount += 1
		lock.unlock()
	}

	public func accept() throws -> any Transport {
		lock.lock()
		let closed = closeCount > 0
		let next = script.isEmpty ? nil : script.removeFirst()
		lock.unlock()
		if closed { throw ListenerClosed() }
		guard let next else { throw PollTimeout() }
		switch next {
		case .connection(let transport): return transport
		case .idle: throw PollTimeout()
		case .fault(let error): throw error
		}
	}

	public func close() {
		lock.lock()
		closeCount += 1
		lock.unlock()
	}
}
