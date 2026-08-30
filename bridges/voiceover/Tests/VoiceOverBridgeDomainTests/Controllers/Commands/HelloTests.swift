// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Hello.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("HelloHandler")
struct HelloTests {
	/// The handler under test, plus the collaborators a test wants to inspect.
	/// A builder rather than a fixture, because every test here customises
	/// something -- the factory's answer, the capability list, the attended flag.
	private func makeHandler(
		factory: FakeAdapterFactory = FakeAdapterFactory(),
		capabilities: [Capability] = [],
		bridgeVersion: String = "1.2.3"
	) -> HelloHandler {
		HelloHandler(
			factory: factory,
			reader: ReaderInfo(name: "voiceover", version: "macOS 15.0.0"),
			capabilities: capabilities,
			bridgeVersion: bridgeVersion
		)
	}

	private func makeContext(
		transcript: FakeTranscript = FakeTranscript(),
		attended: Bool = true
	) -> SessionContext {
		SessionContext(clock: FakeClock(), transcript: transcript, attended: attended, close: { _ in })
	}

	private func request(_ params: [String: JSONValue]) -> Request {
		Request(id: 1, cmd: Command.hello.rawValue, params: params)
	}

	@Test("it answers with this bridge's identity, and the version it compared")
	func identity() throws {
		let context = makeContext()
		let result = try makeHandler().execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)])
		) as? HelloResult
		let hello = try #require(result)
		#expect(hello.protocolVersion == ProtocolVersion.current)
		#expect(hello.reader == ReaderInfo(name: "voiceover", version: "macOS 15.0.0"))
		#expect(hello.bridgeVersion == "1.2.3")
		#expect(hello.mode == .live)
	}

	@Test("it announces exactly the capabilities it was built with, and nothing more")
	func capabilitiesAreWhatThisBuildServes() throws {
		// The handler is handed the list rather than knowing one, which is what
		// keeps "what this build serves" a single statement in the Registry.
		let context = makeContext()
		let result = try makeHandler(capabilities: [.speech]).execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)])
		) as? HelloResult
		#expect(try #require(result).capabilities == [.speech])
	}

	@Test("it creates the session's speech buffer and STARTS capture into that same buffer")
	func captureIsStarted() throws {
		let factory = FakeAdapterFactory()
		let context = makeContext()
		_ = try makeHandler(factory: factory).execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)])
		)
		let buffer = try #require(context.speech)
		// The SAME buffer, not merely a buffer: a source started against one the
		// context does not hold would capture everything into a ring no handler
		// can read, and every speech read would answer empty forever.
		#expect(factory.speechSource.started.count == 1)
		#expect(factory.speechSource.started.first === buffer)
	}

	@Test("the adapter set is installed BEFORE capture starts, so teardown can stop it")
	func theSetIsInstalledFirst() throws {
		// The order is the point. If a start threw with the set not yet on the
		// context, teardown would have nothing to stop and the source would run
		// on past the session that started it.
		let factory = FakeAdapterFactory()
		let context = makeContext()
		var setWhenStarted: AdapterSet?
		factory.speechSource.onStart = { setWhenStarted = context.adapters }
		_ = try makeHandler(factory: factory).execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)])
		)
		#expect(setWhenStarted != nil)
	}

	@Test("captured speech reaches the transcript, so a run records itself unasked")
	func theTranscriptObservesSpeech() throws {
		let transcript = FakeTranscript()
		let factory = FakeAdapterFactory()
		let context = makeContext(transcript: transcript)
		_ = try makeHandler(factory: factory).execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)])
		)
		factory.speechSource.emit("Documents, folder")
		// Bridge-side and unconditional: this is the only account a run leaves if
		// the agent crashed before it ever read the buffer.
		#expect(transcript.speeches == ["Documents, folder"])
	}

	@Test("a refused mode leaves no buffer and starts nothing")
	func aRefusalStartsNothing() throws {
		let factory = FakeAdapterFactory(refusal: AdapterFactoryError("no silence until 13.6"))
		let context = makeContext()
		#expect(throws: CommandError.self) {
			try makeHandler(factory: factory).execute(
				context, request(["mode": .string("silent"), "protocolVersion": .int(1)])
			)
		}
		#expect(context.speech == nil)
		#expect(factory.speechSource.started.isEmpty)
	}

	@Test("a version this binding does not speak is refused BEFORE anything is built")
	func versionMismatchBuildsNothing() throws {
		let factory = FakeAdapterFactory()
		let context = makeContext()
		#expect(throws: CommandError.self) {
			try makeHandler(factory: factory).execute(
				context, request(["mode": .string("live"), "protocolVersion": .int(99)])
			)
		}
		// The point of "before": a refused handshake must leave nothing started,
		// so there is nothing for a teardown that never runs to have to undo.
		#expect(factory.builtFor.isEmpty)
		#expect(context.adapters == nil)
	}

	@Test("the client's mode reaches the factory, and the adapter set lands on the context")
	func theModeIsPassedThrough() throws {
		let factory = FakeAdapterFactory()
		let context = makeContext()
		_ = try makeHandler(factory: factory).execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)])
		)
		#expect(factory.builtFor == [.live])
		#expect(context.adapters?.mode == .live)
		#expect(context.mode == .live)
	}

	@Test("a factory that refuses the mode becomes an error the agent can read")
	func aRefusedModeIsACommandError() throws {
		let factory = FakeAdapterFactory(refusal: AdapterFactoryError("no silence until 13.6"))
		let context = makeContext()
		do {
			_ = try makeHandler(factory: factory).execute(
				context, request(["mode": .string("silent"), "protocolVersion": .int(1)])
			)
			Issue.record("expected the refusal to surface")
		} catch let error as CommandError {
			#expect(error.description == "no silence until 13.6")
		}
	}

	@Test("the persona is recorded as received, and never validated")
	func personaIsRecordedNotJudged() throws {
		let transcript = FakeTranscript()
		let context = makeContext(transcript: transcript)
		_ = try makeHandler().execute(
			context,
			request([
				"mode": .string("live"), "protocolVersion": .int(1),
				"persona": .string("a persona nobody has defined"),
			])
		)
		#expect(context.persona == "a persona nobody has defined")
		#expect(transcript.opened.first?.persona == "a persona nobody has defined")
	}

	@Test("the transcript is opened and told what the session is standing in for")
	func theTranscriptIsOpened() throws {
		let transcript = FakeTranscript()
		let context = makeContext(transcript: transcript)
		let result = try makeHandler().execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)])
		) as? HelloResult
		#expect(transcript.isOpen)
		#expect(transcript.opened.count == 1)
		#expect(transcript.opened.first?.mode == "live")
		#expect(try #require(result).logPath == transcript.logPath)
	}

	@Test("`synth` names the capture voice, which is what a silent session would mute")
	func synthNamesTheCaptureVoice() throws {
		let context = makeContext()
		let result = try makeHandler().execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)])
		) as? HelloResult
		#expect(try #require(result).synth == captureVoiceName)
	}

	@Test("`attended` is the MACHINE's answer, and it rides back as itself")
	func attendedComesFromTheMachine() throws {
		for attended in [true, false] {
			let context = makeContext(attended: attended)
			let result = try makeHandler().execute(
				context, request(["mode": .string("live"), "protocolVersion": .int(1)])
			) as? HelloResult
			#expect(try #require(result).attended == attended)
		}
	}

	@Test("params that are not a handshake fail as a validation error naming the field")
	func badParamsNameTheField() {
		let context = makeContext()
		#expect(throws: ValidationError.self) {
			try makeHandler().execute(context, request(["protocolVersion": .int(1)]))
		}
	}

	@Test("it is the one command legal before the handshake")
	func itIsAvailableBeforeHello() {
		#expect(makeHandler().availableBeforeHello)
		#expect(makeHandler().resetsInactivity)
	}
}
