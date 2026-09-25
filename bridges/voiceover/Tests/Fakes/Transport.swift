// Hand-written stateful fake for the Transport seam: scripted bytes in, recorded bytes out.

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

	public var sentLines: [String] {
		String(decoding: sent, as: UTF8.self)
			.split(separator: "\n", omittingEmptySubsequences: true)
			.map(String.init)
	}
}
