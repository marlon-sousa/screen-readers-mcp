// Hand-written stateful fake for the LocalSocketBinder seam.
// Records calls in order, because the order is the contract: directory created and stale socket removed before the bind.

import VoiceOverBridgeAdapters

public final class FakeLocalSocketBinder: LocalSocketBinder {
	public enum Call: Equatable {
		case createDirectory(path: String, mode: Int)
		case removeFile(path: String)
		case bind(path: String)
		case accept
		case close
	}

	public private(set) var calls: [Call] = []
	public var connections: [any Transport] = []
	public var bindFailure: (any Error)?
	public var directoryFailure: (any Error)?

	public init() {}

	public func createDirectory(at path: String, mode: Int) throws {
		calls.append(.createDirectory(path: path, mode: mode))
		if let directoryFailure { throw directoryFailure }
	}

	public func removeFile(at path: String) {
		calls.append(.removeFile(path: path))
	}

	public func bind(to path: String) throws {
		calls.append(.bind(path: path))
		if let bindFailure { throw bindFailure }
	}

	public func accept() throws -> any Transport {
		calls.append(.accept)
		guard !connections.isEmpty else { throw PollTimeout() }
		return connections.removeFirst()
	}

	public func close() {
		calls.append(.close)
	}
}
