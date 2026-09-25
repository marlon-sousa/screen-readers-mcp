// Hand-written stateful fake for the MessageChannel port: a script of what the peer does.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class FakeChannel: MessageChannel {
	public enum Step {
		case request([String: JSONValue])
		case quiet
		case unreadable(String)
		case closed
	}

	private var script: [Step]

	public private(set) var written: [Response] = []
	public private(set) var isClosed = false
	public var onRead: (() -> Void)?

	public init(_ script: [Step] = []) {
		self.script = script
	}

	public static func requests(_ requests: [[String: JSONValue]]) -> FakeChannel {
		FakeChannel(requests.map { .request($0) })
	}

	public func read() throws -> ChannelRead {
		defer { onRead?() }
		guard !script.isEmpty else { return .timedOut }
		switch script.removeFirst() {
		case .request(let fields):
			return .message(fields)
		case .quiet:
			return .timedOut
		case .unreadable(let reason):
			throw ValidationError(path: "", reason: reason)
		case .closed:
			throw ChannelClosed()
		}
	}

	public func write(_ response: Response) throws {
		written.append(response)
	}

	public func close() {
		isClosed = true
	}
}
