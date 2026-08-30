// ROLE: adapter -- IMPLEMENTS the MessageChannel domain port, as newline
// delimited JSON over a byte transport.
//
// DEPENDS ON: the Transport seam, never on a concrete transport. That is what
// keeps it testable against scripted bytes while the socket underneath stays a
// decision-free leaf.
// BUILT BY: Wiring, which pairs it with whatever transport the accept produced.
//
// EVERY WIRE CONCERN THE DOMAIN MUST NOT KNOW ABOUT LIVES HERE: reassembling
// chunks into frames, splitting on newlines, encoding and decoding. Framing is
// pure code and is still not domain -- which is the example AGENTS.md uses to
// say that "pure" is not the test for where something belongs.
//
// A BUFFERED LINE IS DRAINED BEFORE THE TRANSPORT IS TOUCHED, and protocol.md §1
// requires exactly that: two frames can arrive in one read, and a reader that
// polled the socket first would sit on the second one until something else
// happened to arrive -- a message lost to an idle timeout that had already been
// delivered.

import Foundation
import ScreenReaderWire
import VoiceOverBridgeDomain

public final class JsonLinesChannel: MessageChannel {
	private let transport: any Transport
	private let reader = LineReader()

	public init(transport: any Transport) {
		self.transport = transport
	}

	public func read() throws -> ChannelRead {
		while true {
			if let line = reader.nextLine() {
				return .message(try decode(line))
			}
			let chunk: Data
			do {
				chunk = try transport.receive()
			} catch is PollTimeout {
				return .timedOut
			}
			if chunk.isEmpty {
				throw ChannelClosed()
			}
			reader.feed(chunk)
		}
	}

	public func write(_ response: Response) throws {
		var data = try JSONEncoder().encode(response)
		data.append(0x0A)
		try transport.sendAll(data)
	}

	public func close() {
		transport.close()
	}

	/// One line into the object the session dispatches on.
	///
	/// A LINE THAT IS NOT A JSON OBJECT IS A PROTOCOL FAULT (protocol.md §1), and
	/// it is rejected here rather than being handed up as something the session
	/// would have to re-check: an array or a bare scalar has no `id` to answer
	/// with, so there is no useful error frame to send about it.
	private func decode(_ line: Data) throws -> [String: JSONValue] {
		let value: JSONValue
		do {
			value = try JSONDecoder().decode(JSONValue.self, from: line)
		} catch {
			throw ValidationError(path: "", reason: "line is not JSON: \(error)")
		}
		guard case .object(let fields) = value else {
			throw ValidationError(path: "", reason: "line is not a JSON object")
		}
		return fields
	}
}

/// Private to this adapter: reassembles chunks into complete lines.
///
/// A class rather than a struct because the channel mutates it from a method
/// that is not itself mutating, and because there is exactly one of it per
/// connection -- it is a buffer, not a value.
final class LineReader {
	private var buffer = Data()

	func feed(_ chunk: Data) {
		buffer.append(chunk)
	}

	/// Pop one complete line, without its newline, or nil when none is complete.
	func nextLine() -> Data? {
		guard let newline = buffer.firstIndex(of: 0x0A) else { return nil }
		let line = buffer[buffer.startIndex..<newline]
		buffer = buffer[buffer.index(after: newline)...]
		return Data(line)
	}
}
