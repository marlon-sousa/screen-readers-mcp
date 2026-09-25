// Test support: a pair of in-memory transports wired to each other, so a scenario drives the whole session stack without a socket.

import Foundation
import VoiceOverBridgeAdapters

public final class LoopbackTransport: Transport {
	private let lock = NSCondition()
	private var incoming = Data()
	private var closed = false
	private let pollTimeout: Double
	private var peer: LoopbackTransport?

	private init(pollTimeout: Double) {
		self.pollTimeout = pollTimeout
	}

	public static func pair(pollTimeout: Double = 0.05) -> (bridge: LoopbackTransport, client: LoopbackTransport) {
		let first = LoopbackTransport(pollTimeout: pollTimeout)
		let second = LoopbackTransport(pollTimeout: pollTimeout)
		first.peer = second
		second.peer = first
		return (first, second)
	}

	public func receive() throws -> Data {
		lock.lock()
		defer { lock.unlock() }
		if incoming.isEmpty, !closed {
			_ = lock.wait(until: Date().addingTimeInterval(pollTimeout))
		}
		if !incoming.isEmpty {
			let data = incoming
			incoming = Data()
			return data
		}
		if closed { return Data() }
		throw PollTimeout()
	}

	public func sendAll(_ data: Data) throws {
		peer?.deliver(data)
	}

	public func close() {
		lock.lock()
		closed = true
		lock.signal()
		lock.unlock()
		peer?.markPeerClosed()
	}

	private func deliver(_ data: Data) {
		lock.lock()
		incoming.append(data)
		lock.signal()
		lock.unlock()
	}

	private func markPeerClosed() {
		lock.lock()
		closed = true
		lock.signal()
		lock.unlock()
	}

	/// Reads one complete line, waiting up to `timeout`; nil when none arrived or the peer closed first.
	public func readLine(timeout: Double = 2.0) -> String? {
		let deadline = Date().addingTimeInterval(timeout)
		while true {
			if let newline = buffered.firstIndex(of: 0x0A) {
				let line = buffered[buffered.startIndex..<newline]
				buffered = Data(buffered[buffered.index(after: newline)...])
				return String(decoding: line, as: UTF8.self)
			}
			if Date() >= deadline { return nil }
			guard let chunk = try? receive() else { continue }
			if chunk.isEmpty { return nil }
			buffered.append(chunk)
		}
	}

	private var buffered = Data()
}
