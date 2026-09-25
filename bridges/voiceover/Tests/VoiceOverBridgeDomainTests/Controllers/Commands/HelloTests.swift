// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/Hello.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("HelloHandler")
struct HelloTests {
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
		attended: Bool = true,
		silenceCap: SilenceCapPolicy = .attendedDefault
	) -> SessionContext {
		SessionContext(
			clock: FakeClock(),
			transcript: transcript,
			attended: attended,
			silenceCapPolicy: silenceCap,
			close: { _ in }
		)
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
		#expect(factory.speechSource.started.count == 1)
		#expect(factory.speechSource.started.first === buffer)
	}

	@Test("the adapter set is installed BEFORE capture starts, so teardown can stop it")
	func theSetIsInstalledFirst() throws {
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
		#expect(transcript.speeches == [captureProbeUtterance, "Documents, folder"])
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

	@Test("THE USER'S OWN VOICE IS RECORDED BEFORE OURS IS WRITTEN, so teardown can put it back")
	func theUsersVoiceIsRecordedFirst() throws {
		let factory = FakeAdapterFactory(
			providerLifecycle: FakeProviderLifecycle(selected: "com.apple.eloquence.pt-BR.Reed"))
		let context = makeContext()
		_ = try makeHandler(factory: factory).execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)]))
		#expect(context.previousVoice == "com.apple.eloquence.pt-BR.Reed")
		#expect(factory.providerLifecycle.selectCalls == 1)
	}

	@Test("RULE 1: a previous session's leftover -- OUR voice -- is not recorded as the user's")
	func ourOwnVoiceIsNotTheUsers() throws {
		let lifecycle = FakeProviderLifecycle(selected: "org.screen-readers-mcp.capture.voice")
		let factory = FakeAdapterFactory(providerLifecycle: lifecycle)
		let context = makeContext()
		_ = try makeHandler(factory: factory).execute(
			context, request(["mode": .string("live"), "protocolVersion": .int(1)]))
		#expect(context.previousVoice == nil)
		#expect(lifecycle.selectCalls == 0)
	}

	@Test("the marker channel is opened carrying the user's voice, in LIVE mode too")
	func theChannelCarriesTheVoiceInLiveMode() throws {
		let factory = FakeAdapterFactory(
			providerLifecycle: FakeProviderLifecycle(selected: "com.apple.eloquence.pt-BR.Reed"))
		_ = try makeHandler(factory: factory).execute(
			makeContext(), request(["mode": .string("live"), "protocolVersion": .int(1)]))
		#expect(
			factory.silenceControl.acts == [.begin(preferredVoice: "com.apple.eloquence.pt-BR.Reed")])
		#expect(factory.silenceControl.isSuppressing == false)
	}

	@Test("a SILENT handshake opens the channel and then suppresses, in that order")
	func silentSuppresses() throws {
		let factory = FakeAdapterFactory()
		let transcript = FakeTranscript()
		let result = try makeHandler(factory: factory).execute(
			makeContext(transcript: transcript),
			request(["mode": .string("silent"), "protocolVersion": .int(1)])) as? HelloResult
		#expect(try #require(result).mode == .silent)
		#expect(
			factory.silenceControl.acts
				== [.begin(preferredVoice: "com.apple.voice.compact.pt-BR.Luciana"), .suppress])
		#expect(factory.silenceControl.isSuppressing)
		#expect(transcript.notes.contains { $0.contains("lease") })
	}

	@Test("A SILENT SESSION IS REFUSED when the reader edge cannot deliver silence, BY NAME")
	func silentIsRefusedOnAnUnusableEdge() {
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		lifecycle.stateAfterRegistering = .registered
		lifecycle.stateAfterPublishing = .registered
		let factory = FakeAdapterFactory(providerLifecycle: lifecycle)
		do {
			_ = try makeHandler(factory: factory).execute(
				makeContext(), request(["mode": .string("silent"), "protocolVersion": .int(1)]))
			Issue.record("expected the silent handshake to be refused")
		} catch let error as CommandError {
			#expect(error.description.contains(SetupRung.registration.rawValue))
			#expect(error.description.contains(ReaderCondition.providerNotRunning.rawValue))
			#expect(factory.silenceControl.acts.isEmpty)
			#expect(lifecycle.registerCalls == 1)
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("a silent session whose voice would not STICK is refused too")
	func silentIsRefusedWhenSelectionFails() {
		let lifecycle = FakeProviderLifecycle()
		lifecycle.selectionRefusal = ProviderError("the capture voice was written and did not take")
		do {
			_ = try makeHandler(factory: FakeAdapterFactory(providerLifecycle: lifecycle)).execute(
				makeContext(), request(["mode": .string("silent"), "protocolVersion": .int(1)]))
			Issue.record("expected the silent handshake to be refused")
		} catch let error as CommandError {
			#expect(error.description.contains("did not take"))
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("A LIVE SESSION ON THE SAME MACHINE IS REFUSED TOO, which is 13.20's one reversal")
	func liveIsRefusedOnAnUnusableEdge() {
		let transcript = FakeTranscript()
		let lifecycle = FakeProviderLifecycle(machineState: .notRegistered)
		lifecycle.stateAfterRegistering = .registered
		lifecycle.stateAfterPublishing = .registered
		let factory = FakeAdapterFactory(providerLifecycle: lifecycle)
		do {
			_ = try makeHandler(factory: factory).execute(
				makeContext(transcript: transcript),
				request(["mode": .string("live"), "protocolVersion": .int(1)]))
			Issue.record("expected the live handshake to be refused as well")
		} catch let error as CommandError {
			#expect(error.description.contains(ReaderCondition.providerNotRunning.rawValue))
			#expect(transcript.notes.contains { $0.contains("registering it") })
		} catch {
			Issue.record("unexpected error: \(error)")
		}
	}

	@Test("`synth` NAMES WHAT IS ACTUALLY SELECTED, so it cannot quietly disagree with reality")
	func synthIsAsked() throws {
		let ours = try makeHandler(factory: FakeAdapterFactory()).execute(
			makeContext(), request(["mode": .string("live"), "protocolVersion": .int(1)])) as? HelloResult
		#expect(try #require(ours).synth == captureVoiceName)

		let lifecycle = FakeProviderLifecycle()
		let second = try makeHandler(factory: FakeAdapterFactory(providerLifecycle: lifecycle)).execute(
			makeContext(), request(["mode": .string("live"), "protocolVersion": .int(1)])) as? HelloResult
		#expect(try #require(second).synth == captureVoiceName)
		#expect(lifecycle.selectCalls == 1)

		let third = try makeHandler(factory: FakeAdapterFactory(providerLifecycle: lifecycle)).execute(
			makeContext(), request(["mode": .string("live"), "protocolVersion": .int(1)])) as? HelloResult
		#expect(try #require(third).synth == captureVoiceName)
		#expect(lifecycle.selectCalls == 1)
	}

	@Test("the silence cap travels in hello, from the same machine fact as `attended`")
	func theCapIsReported() throws {
		let capped = try makeHandler().execute(
			makeContext(), request(["mode": .string("silent"), "protocolVersion": .int(1)])) as? HelloResult
		let helloResult = try #require(capped)
		let cap = try #require(helloResult.silenceCap)
		#expect(cap.enabled)
		#expect(cap.warnAfterSeconds == 45)
		#expect(cap.liftAfterSeconds == 90)

		let unattended = try makeHandler().execute(
			makeContext(attended: false, silenceCap: SilenceCapPolicy(enabled: false)),
			request(["mode": .string("silent"), "protocolVersion": .int(1)])) as? HelloResult
		let unattendedResult = try #require(unattended)
		#expect(try #require(unattendedResult.silenceCap).enabled == false)
	}

	@Test("capture is started BEFORE the reader is pointed at us, or the first utterance is lost")
	func captureListensFirst() throws {
		let factory = FakeAdapterFactory()
		var selectedWhenCaptureStarted: Int?
		factory.speechSource.onStart = {
			selectedWhenCaptureStarted = factory.providerLifecycle.selectCalls
		}
		_ = try makeHandler(factory: factory).execute(
			makeContext(), request(["mode": .string("live"), "protocolVersion": .int(1)]))
		#expect(selectedWhenCaptureStarted == 0)
		#expect(factory.providerLifecycle.selectCalls == 1)
	}
}
