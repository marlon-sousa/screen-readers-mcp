// A hand-written stateful fake for the Transport seam, mirroring
// Sources/VoiceOverBridgeAdapters/Ports/Transport.swift.
//
// Scripted bytes in, recorded bytes out. It is what makes JsonLinesChannel's
// framing testable in the shape that actually goes wrong: a frame split across
// two chunks, two frames in one chunk, a chunk that ends mid-frame -- none of
// which a real socket can be asked to produce on demand.

import Foundation
import VoiceOverBridgeAdapters

public final class FakeTransport: Transport {
	public enum Step {
		case chunk(Data)
		case idle
		case endOfStream
	}

	private var script: [Step]
	public private(set) var sent = Data()
	public private(set) var isClosed = false

	public init(_ script: [Step] = []) {
		self.script = script
	}

	/// The common case: some text arrives in one piece.
	public static func delivering(_ text: String) -> FakeTransport {
		FakeTransport([.chunk(Data(text.utf8)), .endOfStream])
	}

	public func receive() throws -> Data {
		guard !script.isEmpty else { return Data() }
		switch script.removeFirst() {
		case .chunk(let data): return data
		case .idle: throw PollTimeout()
		case .endOfStream: return Data()
		}
	}

	public func sendAll(_ data: Data) throws {
		sent.append(data)
	}

	public func close() {
		isClosed = true
	}

	/// What was written, as the lines it was framed into.
	public var sentLines: [String] {
		String(decoding: sent, as: UTF8.self)
			.split(separator: "\n", omittingEmptySubsequences: true)
			.map(String.init)
	}
}
