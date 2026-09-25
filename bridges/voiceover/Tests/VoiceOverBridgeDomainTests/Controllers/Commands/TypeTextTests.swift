// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/TypeText.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("TypeText")
struct TypeTextTests {
	private let handler = TypeTextHandler()

	private func context(
		mode: CaptureMode = .live,
		typer: FakeTextTyper = FakeTextTyper(),
		permissions: FakePermissionBroker = FakePermissionBroker(),
		transcript: FakeTranscript = FakeTranscript(),
		announcer: FakeAnnouncer = FakeAnnouncer()
	) -> SessionContext {
		let context = SessionContext(
			clock: FakeClock(), transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		context.adapters = fakeAdapterSet(
			mode: mode, textTyper: typer, permissions: permissions, announcer: announcer)
		context.speech = SpeechBuffer(clock: FakeClock())
		return context
	}

	private func request(_ text: String, graceMs: Int = 0, announce: String = "") -> Request {
		Request(
			id: 1, cmd: Command.typeText.rawValue,
			params: [
				"text": .string(text),
				"graceMs": .int(graceMs),
				"announce": .string(announce),
			])
	}

	@Test("the text reaches the typer WHOLE and untouched, control characters included")
	func theTextIsHandedOverUnchanged() throws {
		let typer = FakeTextTyper()
		_ = try handler.execute(context(typer: typer), request("one\ntwo\ttab"))
		#expect(typer.typed == ["one\ntwo\ttab"])
	}

	@Test("`typed` counts UNICODE SCALARS, which is what the other two bindings count")
	func typedIsAScalarCount() throws {
		let decomposed = "e\u{0301}"  // "e" + combining acute -- one cluster, two scalars
		let value = try handler.execute(context(), request(decomposed))
		#expect(try #require(value as? TypeResult).typed == 2)
		#expect(decomposed.count == 1, "the trap this test exists for")
	}

	@Test("a typer that fails is reported as an error, and the session survives it")
	func aFailedInjectionIsReported() throws {
		let typer = FakeTextTyper()
		typer.failure = TypingError("the system would not create a keyboard event")
		do {
			_ = try handler.execute(context(typer: typer), request("hello"))
			Issue.record("expected the injection to fail")
		} catch let error as CommandError {
			#expect(error.description.contains("keyboard event"))
		}
	}

	@Test("a session that already holds the grant asks for NOTHING")
	func anExistingGrantIsNotRequested() throws {
		let permissions = FakePermissionBroker(state: .granted)
		_ = try handler.execute(context(permissions: permissions), request("hello"))
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads == [.accessibility])
	}

	@Test("the grant is REQUESTED on a typeText that does not already have it")
	func theGrantIsRequestedWhenTyping() throws {
		let permissions = FakePermissionBroker(state: .notGranted)
		let typer = FakeTextTyper()
		#expect(throws: CommandError.self) {
			try handler.execute(context(typer: typer, permissions: permissions), request("hello"))
		}
		#expect(permissions.requests == [.accessibility])
		#expect(typer.typed.isEmpty)
	}

	@Test("a request the human grants goes straight on to type")
	func aGrantedRequestProceeds() throws {
		let permissions = FakePermissionBroker(state: .notGranted)
		permissions.onRequest = { permissions.state = .granted }
		let typer = FakeTextTyper()
		_ = try handler.execute(context(typer: typer, permissions: permissions), request("hello"))
		#expect(permissions.requests == [.accessibility])
		#expect(typer.typed == ["hello"])
	}

	@Test("a request that is not granted says NOT YET and names the recovery")
	func aRefusedRequestSaysWhatToDo() throws {
		let permissions = FakePermissionBroker(state: .notGranted)
		do {
			_ = try handler.execute(context(permissions: permissions), request("hello"))
			Issue.record("expected typing to be refused without the grant")
		} catch let error as CommandError {
			#expect(error.description.contains(Permission.accessibility.rawValue))
			#expect(error.description.contains("System Settings"))
			#expect(error.description.contains("sshd-keygen-wrapper"))
			#expect(!error.description.contains("pressGesture"))
			#expect(error.description.contains("nothing was typed"))
		}
	}

	@Test("the transcript records a LENGTH, before the injection, and never the text")
	func theTranscriptRecordsALengthOnly() throws {
		let transcript = FakeTranscript()
		let typer = FakeTextTyper()
		typer.failure = TypingError("boom")
		_ = try? handler.execute(
			context(typer: typer, transcript: transcript), request("hunter2"))
		#expect(transcript.typedLengths == [7])
		#expect(!transcript.notes.contains { $0.contains("hunter2") })
	}

	@Test("the window spans what was said while typing, and the entries carry their indices")
	func theWindowSpansTheTyping() throws {
		let typer = FakeTextTyper()
		let ctx = context(typer: typer)
		let buffer = try #require(ctx.speech)
		typer.onType = { _ in buffer.append(CapturedUtterance(text: "h")) }
		let value = try handler.execute(ctx, request("h", graceMs: 50))
		let result = try #require(value as? TypeResult)
		#expect(result.speechFrom == 1)
		#expect(result.speechTo == 2)
		#expect(result.speech.map(\.index) == [1])
	}

	@Test("an empty window is a FACT about an instant, not a claim that nothing was said")
	func anEmptyWindowIsNotAClaim() throws {
		let value = try handler.execute(context(), request("hello"))
		let result = try #require(value as? TypeResult)
		#expect(result.speech.isEmpty)
		#expect(result.speechFrom == result.speechTo)
	}

	@Test("`graceMs` DEFAULTS TO 0 here, where a gesture's defaults to 100")
	func theDefaultGraceIsZero() throws {
		let bare = Request(id: 1, cmd: Command.typeText.rawValue, params: ["text": .string("hi")])
		#expect(try bare.params(as: TypeParams.self).graceMs == 0)
		#expect(PressGestureParams(gestures: []).graceMs == 100)
		_ = try handler.execute(context(), bare)
	}

	@Test("`state` is never sampled: this bridge announces no `state` capability")
	func stateIsAlwaysNil() throws {
		let value = try handler.execute(context(), request("hello"))
		#expect(try #require(value as? TypeResult).state == nil)
	}

	@Test("the announce IS SPOKEN, in BOTH modes -- 13.10 made that keepable")
	func announceIsSpokenInEitherMode() throws {
		for mode in [CaptureMode.silent, .live] {
			let announcer = FakeAnnouncer()
			let typer = FakeTextTyper()
			_ = try handler.execute(
				context(mode: mode, typer: typer, announcer: announcer),
				request("hello", announce: "about to type"))
			#expect(announcer.spoken == ["about to type"])
			#expect(typer.typed == ["hello"])
		}
	}

	@Test("a warning that could not be spoken TYPES NOTHING and asks for no grant")
	func anUnspeakableWarningStopsEverything() throws {
		let announcer = FakeAnnouncer()
		announcer.fails = true
		let typer = FakeTextTyper()
		let permissions = FakePermissionBroker()
		#expect(throws: CommandError.self) {
			try handler.execute(
				context(mode: .silent, typer: typer, permissions: permissions, announcer: announcer),
				request("hello", announce: "about to type"))
		}
		#expect(typer.typed.isEmpty)
		#expect(permissions.requests.isEmpty)
		#expect(permissions.statusReads.isEmpty)
	}

	@Test("it declares that it MOVES the user's machine")
	func itMutatesTheReader() {
		#expect(handler.mutatesReader)
		#expect(!handler.availableBeforeHello)
		#expect(handler.resetsInactivity)
	}

	@Test("typed before `hello`, it says so rather than crashing")
	func withoutAReaderEdgeItSaysSo() throws {
		let bare = SessionContext(
			clock: FakeClock(), transcript: FakeTranscript(), attended: true, close: { _ in })
		#expect(throws: CommandError.self) {
			try handler.execute(bare, request("hello"))
		}
	}
}
