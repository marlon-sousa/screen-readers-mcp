// Mirrors Sources/VoiceOverBridgeAdapters/JsonLinesChannel.swift.
//
// The assertions are protocol.md §1's framing rules, tested in the shapes a real
// socket cannot be asked to produce on demand: a frame split across two reads,
// two frames in one read, and a read that ends mid-frame.

import Fakes
import Foundation
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeAdapters
@testable import VoiceOverBridgeDomain

@Suite("JsonLinesChannel")
struct JsonLinesChannelTests {
	@Test("one line becomes one message")
	func oneLine() throws {
		let channel = JsonLinesChannel(transport: FakeTransport.delivering("{\"id\":1,\"cmd\":\"ping\"}\n"))
		#expect(try channel.read() == .message(["id": .int(1), "cmd": .string("ping")]))
	}

	@Test("a frame split across two chunks is reassembled")
	func splitFrame() throws {
		let transport = FakeTransport([
			.chunk(Data("{\"id\":1,\"c".utf8)),
			.chunk(Data("md\":\"ping\"}\n".utf8)),
		])
		let channel = JsonLinesChannel(transport: transport)
		#expect(try channel.read() == .message(["id": .int(1), "cmd": .string("ping")]))
	}

	@Test("two frames in one chunk are BOTH delivered, without touching the transport again")
	func twoFramesInOneChunk() throws {
		// The rule protocol.md §1 states out loud: a reader must drain complete
		// buffered lines before polling again. Without it the second frame waits
		// for whatever arrives next -- a message lost to an idle timeout although
		// it had already been delivered.
		let transport = FakeTransport([
			.chunk(Data("{\"id\":1,\"cmd\":\"ping\"}\n{\"id\":2,\"cmd\":\"bye\"}\n".utf8)),
			.endOfStream,
		])
		let channel = JsonLinesChannel(transport: transport)
		#expect(try channel.read() == .message(["id": .int(1), "cmd": .string("ping")]))
		#expect(try channel.read() == .message(["id": .int(2), "cmd": .string("bye")]))
	}

	@Test("an idle transport is a timeout, and the session goes on")
	func idleIsATimeout() throws {
		let channel = JsonLinesChannel(transport: FakeTransport([.idle]))
		#expect(try channel.read() == .timedOut)
	}

	@Test("a partial frame followed by silence is a timeout, not a fault")
	func partialThenIdle() throws {
		let channel = JsonLinesChannel(transport: FakeTransport([.chunk(Data("{\"id\":1".utf8)), .idle]))
		#expect(try channel.read() == .timedOut)
	}

	@Test("end of stream is the peer going away")
	func endOfStreamCloses() {
		let channel = JsonLinesChannel(transport: FakeTransport([.endOfStream]))
		#expect(throws: ChannelClosed.self) {
			try channel.read()
		}
	}

	@Test("a line that is not JSON is a validation error, not a closed channel")
	func garbageIsAFault() {
		let channel = JsonLinesChannel(transport: FakeTransport.delivering("not json at all\n"))
		#expect(throws: ValidationError.self) {
			try channel.read()
		}
	}

	@Test("a JSON array is a protocol fault: there is no id to answer it with")
	func aNonObjectLineIsAFault() {
		let channel = JsonLinesChannel(transport: FakeTransport.delivering("[1,2,3]\n"))
		#expect(throws: ValidationError.self) {
			try channel.read()
		}
	}

	@Test("a write is one line, newline-terminated, with no newline inside it")
	func writesAreFramed() throws {
		let transport = FakeTransport()
		let channel = JsonLinesChannel(transport: transport)
		try channel.write(Response.succeeded(id: 4, with: EchoResult(payload: .string("two\nlines"))))
		#expect(transport.sent.last == 0x0A)
		#expect(transport.sentLines.count == 1)
		// The payload's own newline survives as an escape, which is what keeps a
		// frame a frame: JSON escaping is the reason the framing can be this
		// simple.
		#expect(transport.sentLines[0].contains("two\\nlines"))
	}

	@Test("what it writes is what it reads: a reply round-trips through the framing")
	func aReplyRoundTrips() throws {
		let outbound = FakeTransport()
		try JsonLinesChannel(transport: outbound)
			.write(Response.succeeded(id: 5, with: PingResult()))
		let inbound = JsonLinesChannel(transport: FakeTransport([.chunk(outbound.sent)]))
		guard case .message(let fields) = try inbound.read() else {
			Issue.record("expected a message")
			return
		}
		#expect(fields["id"] == .int(5))
	}

	@Test("closing the channel closes the transport under it")
	func closePropagates() {
		let transport = FakeTransport()
		JsonLinesChannel(transport: transport).close()
		#expect(transport.isClosed)
	}
}
