// A hand-written stateful fake for the MessageChannel port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/MessageChannel.swift.
//
// IT IS A SCRIPT, NOT A MOCK. A test hands it the sequence of things the peer
// does -- frames, quiet windows, an unreadable line, a close -- and then asserts
// on what the session WROTE. That is the shape the session's own protocol has, so
// a double that only recorded calls would need every return value hand-fed per
// test, which is re-implementing the channel once per assertion.
//
// A SCRIPT THAT RUNS OUT KEEPS TIMING OUT rather than closing, because those are
// different session outcomes: a test that wants a channel-closed teardown says so
// by scripting `.closed`, and one that wants a watchdog to fire says so by
// advancing the clock. Ending the script must not silently choose one of them.

import ScreenReaderWire
import VoiceOverBridgeDomain

public final class FakeChannel: MessageChannel {
	/// One thing the peer does.
	public enum Step {
		case request([String: JSONValue])
		case quiet
		case unreadable(String)
		case closed
	}

	private var script: [Step]

	/// Everything the session replied, in order.
	public private(set) var written: [Response] = []
	public private(set) var isClosed = false
	/// Called after each step is served, so a test can advance a clock or flip a
	/// flag exactly between two frames.
	public var onRead: (() -> Void)?

	public init(_ script: [Step] = []) {
		self.script = script
	}

	/// The convenience the session tests use most: a run of requests, then quiet.
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
