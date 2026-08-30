// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/SessionContext.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("SessionContext")
struct SessionContextTests {
	@Test("before hello it holds nothing a handshake produces")
	func emptyBeforeHello() {
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		#expect(context.mode == nil)
		#expect(context.adapters == nil)
		#expect(context.speech == nil)
		#expect(context.persona.isEmpty)
	}

	@Test("the speech buffer is a readable failure before hello, and the buffer after it")
	func theSpeechBufferAccessor() throws {
		// Unreachable through the dispatch loop -- every speech handler runs after
		// hello, and hello always installs a buffer -- which is exactly why it
		// throws rather than crashing: an unreachable case that turns out to be
		// wrong costs one command here and the user's screen reader there.
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in }
		)
		#expect(throws: CommandError.self) { try context.speechBuffer() }

		let buffer = SpeechBuffer(clock: FakeClock())
		context.speech = buffer
		#expect(try context.speechBuffer() === buffer)
	}

	@Test("close passes the reason through to the session, unchanged")
	func closeIsTheOneCapability() {
		var seen: [TeardownReason] = []
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: false, close: { seen.append($0) }
		)
		context.close(.external)
		context.close(.clientBye)
		// It passes both on: deciding that the first request wins is the SESSION's
		// rule, and a context that quietly dropped the second would be making a
		// lifecycle decision it has no business making.
		#expect(seen == [.external, .clientBye])
	}

	@Test("attended is fixed for the session's life -- it is a fact about the room")
	func attendedIsImmutable() {
		let context = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: false, close: { _ in }
		)
		#expect(!context.attended)
	}
}
