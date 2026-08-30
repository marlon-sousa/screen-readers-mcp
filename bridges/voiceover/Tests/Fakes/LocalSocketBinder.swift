// A hand-written stateful fake for the LocalSocketBinder seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/LocalSocketBinder.swift.
//
// IT RECORDS CALLS IN ORDER, and that is unusual for a fake in this repo --
// everywhere else the assertion is on behaviour rather than on interactions.
// Here the ORDER IS THE BEHAVIOUR: protocol.md §1 requires the directory to
// exist before the bind and the stale socket to be unlinked before it, and
// "unlinked afterwards" would be a bridge that removes the socket it is
// listening on. There is nothing else to observe -- the effects are in a
// filesystem this test does not have -- so the sequence is the contract.

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
	/// Handed back by `accept`, once per scripted connection.
	public var connections: [any Transport] = []
	/// When set, `bind` throws it.
	public var bindFailure: (any Error)?
	/// When set, `createDirectory` throws it.
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
