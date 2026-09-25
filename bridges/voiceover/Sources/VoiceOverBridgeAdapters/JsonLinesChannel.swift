// ROLE: adapter implementing the MessageChannel port as newline-delimited JSON over a byte transport.
// BUILT BY: Wiring, which pairs it with whatever transport the accept produced.
// Drain a buffered line before reading the transport: two frames can arrive in one read, and the second would otherwise wait out an idle timeout.

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

	/// A line that is not a JSON object has no `id` to answer, so it is rejected here as a protocol fault.
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
