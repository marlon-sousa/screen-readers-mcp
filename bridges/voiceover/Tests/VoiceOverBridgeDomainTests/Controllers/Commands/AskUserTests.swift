// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/AskUser.swift.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("AskUser")
struct AskUserTests {
	private let handler = AskUserHandler()

	private func context(
		mode: CaptureMode = .silent,
		prompter: FakeUserPrompter = FakeUserPrompter(),
		announcer: FakeAnnouncer = FakeAnnouncer(),
		silence: FakeSilenceControl = FakeSilenceControl(),
		transcript: FakeTranscript = FakeTranscript(),
		clock: FakeClock = FakeClock()
	) -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		context.adapters = fakeAdapterSet(
			mode: mode, silenceControl: silence, announcer: announcer, userPrompter: prompter)
		return context
	}

	private func request(_ prompt: String) -> Request {
		Request(id: 1, cmd: Command.askUser.rawValue, params: ["prompt": .string(prompt)])
	}

	@Test("the question goes up and the TICKET comes back, with nobody having answered")
	func itReturnsATicket() throws {
		let prompter = FakeUserPrompter()
		let session = context(prompter: prompter)
		let result = try handler.execute(session, request("did the menu open?"))
		#expect(prompter.presented == ["did the menu open?"])
		#expect((result as? AskUserResult)?.ticket == prompter.lastTicket)
		#expect(session.outstandingPrompt?.ticket == prompter.lastTicket)
		#expect(prompter.reply(for: prompter.lastTicket) == nil)
	}

	@Test("the question is SPOKEN as well as shown, which is what reaches a muted reader")
	func itSpeaksTheQuestion() throws {
		let announcer = FakeAnnouncer()
		_ = try handler.execute(context(announcer: announcer), request("did the menu open?"))
		#expect(announcer.spoken == ["did the menu open?"])
	}

	@Test("A SILENT SESSION PASSES THROUGH WHILE THE WINDOW IS OPEN")
	func itLiftsTheSuppressionToAsk() throws {
		let silence = FakeSilenceControl()
		try silence.suppress()
		let session = context(mode: .silent, silence: silence)
		_ = try handler.execute(session, request("ready?"))
		#expect(!silence.isSuppressing)
		#expect(session.outstandingPrompt?.suspendedSilence == true)
	}

	@Test("a LIVE session suspends nothing, and records that it took nothing")
	func aLiveSessionTakesNothing() throws {
		let silence = FakeSilenceControl()
		let session = context(mode: .live, silence: silence)
		_ = try handler.execute(session, request("ready?"))
		#expect(session.outstandingPrompt?.suspendedSilence == false)
		#expect(!silence.isSuppressing)
	}

	@Test("ONE OUTSTANDING PROMPT AT A TIME: a second ask is refused, and the first survives")
	func onlyOneAtATime() throws {
		let prompter = FakeUserPrompter()
		let session = context(prompter: prompter)
		let first = try #require(try handler.execute(session, request("one")) as? AskUserResult)
		#expect(throws: CommandError.self) { try handler.execute(session, request("two")) }
		#expect(session.outstandingPrompt?.ticket == first.ticket)
		#expect(prompter.presented == ["one"])
	}

	@Test("a prompt that cannot be presented is an error, and leaves nothing outstanding")
	func aWindowThatWillNotOpen() throws {
		let prompter = FakeUserPrompter()
		prompter.fails = true
		let session = context(prompter: prompter)
		#expect(throws: CommandError.self) { try handler.execute(session, request("anyone there?")) }
		#expect(session.outstandingPrompt == nil)
	}

	@Test("a question that could not be SPOKEN still succeeds -- the window is up")
	func speechIsNotTheWholeQuestion() throws {
		let announcer = FakeAnnouncer()
		announcer.fails = true
		let transcript = FakeTranscript()
		let session = context(announcer: announcer, transcript: transcript)
		let result = try handler.execute(session, request("still there?"))
		#expect((result as? AskUserResult)?.ticket.isEmpty == false)
		#expect(transcript.notes.contains { $0.contains("could not be spoken") })
	}

	@Test("an empty question is refused: there is nothing for a human to answer")
	func anEmptyQuestion() {
		#expect(throws: CommandError.self) { try handler.execute(context(), request("   ")) }
	}

	@Test("it resets the silence window, because the human was just spoken to")
	func itResetsTheSilenceWindow() throws {
		let clock = FakeClock()
		let session = context(clock: clock)
		session.silenceCap = SilenceCap(policy: .attendedDefault, now: clock.monotonic())
		clock.advance(defaultWarnAfter + 1)
		_ = try handler.execute(session, request("are you there?"))
		#expect(session.silenceCap?.check(clock.monotonic()) == SilenceCapAction.none)
	}

	@Test("it MUTATES the reader, unlike `announce`: a question demands something")
	func itIsAMutation() {
		#expect(handler.mutatesReader)
	}
}
