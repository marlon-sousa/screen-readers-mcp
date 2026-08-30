// TEST SUPPORT, NOT A PORT DOUBLE -- which is why it is under Support/ rather
// than beside the fakes. Lane 1 draws the same line with two directories
// (tests/fakes/ and tests/support/); Swift has one module either way, so the
// directory is what carries the distinction.
//
// A pair of in-memory transports wired to each other: what one sends, the other
// receives. It is a real, working Transport rather than a scripted one, which is
// what lets an integration scenario drive the WHOLE session stack -- the real
// JsonLinesChannel, the real Session, the real handlers -- with no socket and no
// second process, and still exercise every byte of framing.

import Foundation
import VoiceOverBridgeAdapters

public final class LoopbackTransport: Transport {
	private let lock = NSCondition()
	private var incoming = Data()
	private var closed = false
	private let pollTimeout: Double
	/// The other end. Weak in one direction would be enough, but a pair is made
	/// and held by the test, so both are strong and neither outlives the test.
	private var peer: LoopbackTransport?

	private init(pollTimeout: Double) {
		self.pollTimeout = pollTimeout
	}

	/// A connected pair. The bridge holds one end; whatever stands in for the
	/// server holds the other.
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
			// Waits, so a scenario driving both ends from two threads behaves like
			// a socket rather than spinning; times out, so the session's own poll
			// window still means something.
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

	/// Read one complete line, waiting up to `timeout`. What a scenario standing
	/// in for the server uses to read a reply, and nil when none arrived before
	/// the deadline or the peer closed first.
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
