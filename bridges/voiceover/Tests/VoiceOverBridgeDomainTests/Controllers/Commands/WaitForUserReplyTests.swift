// Mirrors Sources/VoiceOverBridgeDomain/Controllers/Commands/WaitForUserReply.swift.
//
// THE COMMAND IS A POLL, AND THAT IS WHAT THIS FILE CHECKS. It waits on the
// injected Clock -- so a thirty-second poll costs microseconds here -- it comes
// back with `answered: false` rather than an error when nobody has answered yet,
// and it CLOSES the window on all three of the endings that are endings.
//
// The reason it is a poll rather than an await is in UserPrompter's header: the
// thread that would block is the one renewing the silence lease, and a lease
// expiring while somebody reads a dialog is the failure 13.6's whole design
// exists to prevent.

import Fakes
import ScreenReaderWire
import Testing

@testable import VoiceOverBridgeDomain

@Suite("WaitForUserReply")
struct WaitForUserReplyTests {
	private let ask = AskUserHandler()
	private let handler = WaitForUserReplyHandler()

	/// A session with a prompt already outstanding, which is the only state this
	/// command is ever dispatched in. Built by running the real `askUser`, so the
	/// two halves cannot drift apart about what an open window looks like.
	private func asked(
		mode: CaptureMode = .silent,
		prompter: FakeUserPrompter = FakeUserPrompter(),
		silence: FakeSilenceControl = FakeSilenceControl(),
		transcript: FakeTranscript = FakeTranscript(),
		clock: FakeClock = FakeClock()
	) throws -> SessionContext {
		let context = SessionContext(
			clock: clock, transcript: transcript, attended: true, close: { _ in })
		context.mode = mode
		context.adapters = fakeAdapterSet(
			mode: mode, silenceControl: silence, userPrompter: prompter)
		if mode == .silent { try silence.suppress() }
		_ = try ask.execute(
			context, Request(id: 1, cmd: Command.askUser.rawValue, params: ["prompt": .string("ready?")]))
		return context
	}

	private func poll(_ ticket: String, timeout: Double = 30) -> Request {
		Request(
			id: 2, cmd: Command.waitForUserReply.rawValue,
			params: ["ticket": .string(ticket), "timeout": .double(timeout)])
	}

	@Test("the human's answer comes back, and the window is closed behind it")
	func anAnswer() throws {
		let prompter = FakeUserPrompter()
		let session = try asked(prompter: prompter)
		prompter.answer("yes, it opened")
		let result = try #require(
			try handler.execute(session, poll(prompter.lastTicket)) as? WaitForUserReplyResult)
		#expect(result.answered)
		#expect(result.text == "yes, it opened")
		#expect(session.outstandingPrompt == nil)
		#expect(prompter.cancelled == [prompter.lastTicket])
	}

	@Test("A POLL THAT TIMES OUT IS `answered: false` AND LEAVES THE WINDOW OPEN")
	func aPollMissKeepsTheWindow() throws {
		// `waitForSpeech`'s manners: a wait that expires is an ordinary outcome an
		// agent branches on, and the next poll continues the same wait.
		let clock = FakeClock()
		let prompter = FakeUserPrompter()
		let session = try asked(prompter: prompter, clock: clock)
		let result = try #require(
			try handler.execute(session, poll(prompter.lastTicket, timeout: 5)) as? WaitForUserReplyResult)
		#expect(!result.answered)
		#expect(result.text.isEmpty)
		#expect(session.outstandingPrompt != nil)
		#expect(prompter.cancelled.isEmpty)
		// It waited on the injected clock rather than on the wall: five seconds of
		// polls, instantly.
		#expect(clock.sleeps.allSatisfy { $0 == promptPollInterval })
		#expect(!clock.sleeps.isEmpty)
	}

	@Test("a dismissal is `answered: false` and CLOSES the window -- a different thing")
	func aDismissal() throws {
		let prompter = FakeUserPrompter()
		let session = try asked(prompter: prompter)
		prompter.dismiss()
		let result = try #require(
			try handler.execute(session, poll(prompter.lastTicket)) as? WaitForUserReplyResult)
		#expect(!result.answered)
		#expect(session.outstandingPrompt == nil)
	}

	@Test("the WINDOW's own deadline ends it, even mid-poll, and reports no answer")
	func theWindowExpires() throws {
		let clock = FakeClock()
		let prompter = FakeUserPrompter()
		let session = try asked(prompter: prompter, clock: clock)
		clock.advance(UserPrompt.window + 1)
		let result = try #require(
			try handler.execute(session, poll(prompter.lastTicket)) as? WaitForUserReplyResult)
		#expect(!result.answered)
		#expect(session.outstandingPrompt == nil)
		#expect(prompter.cancelled == [prompter.lastTicket])
	}

	@Test("A SILENT SESSION GOES QUIET AGAIN once the window is closed")
	func theSuppressionComesBack() throws {
		let silence = FakeSilenceControl()
		let prompter = FakeUserPrompter()
		let session = try asked(prompter: prompter, silence: silence)
		#expect(!silence.isSuppressing)
		prompter.answer("yes")
		_ = try handler.execute(session, poll(prompter.lastTicket))
		#expect(silence.isSuppressing)
	}

	@Test("but NOT if the silence cap has already lifted: that was a guarantee, not a loan")
	func aLiftedCapIsNotUndone() throws {
		// protocol.md §6.1 gives the human their machine back for good unless a
		// fresh window is opened and audibly marked, which this bridge does not do.
		// Re-muting them here would take back a guarantee.
		let clock = FakeClock()
		let silence = FakeSilenceControl()
		let prompter = FakeUserPrompter()
		let session = try asked(prompter: prompter, silence: silence, clock: clock)
		let cap = SilenceCap(policy: .attendedDefault, now: clock.monotonic())
		clock.advance(defaultLiftAfter + 1)
		#expect(cap.check(clock.monotonic()) == SilenceCapAction.lift)
		session.silenceCap = cap
		prompter.answer("yes")
		_ = try handler.execute(session, poll(prompter.lastTicket))
		#expect(!silence.isSuppressing)
	}

	@Test("a LIVE session's window closing suppresses nothing, because it took nothing")
	func aLiveSessionIsUntouched() throws {
		let silence = FakeSilenceControl()
		let prompter = FakeUserPrompter()
		let session = try asked(mode: .live, prompter: prompter, silence: silence)
		prompter.answer("yes")
		_ = try handler.execute(session, poll(prompter.lastTicket))
		#expect(!silence.isSuppressing)
	}

	@Test("a ticket nobody is holding is an error that says the window may have gone")
	func anUnknownTicket() throws {
		let session = try asked()
		#expect(throws: CommandError.self) { try handler.execute(session, poll("prompt-99")) }
	}

	@Test("A POLL LONGER THAN THE INACTIVITY WINDOW IS CLAMPED, and says so in the record")
	func aLongPollIsClamped() throws {
		// The inactivity watchdog is measured from DISPATCH and is not extended by a
		// handler that blocks, so a poll allowed to run past it would answer the
		// agent and have the session torn down under it one line later.
		let clock = FakeClock()
		let transcript = FakeTranscript()
		let prompter = FakeUserPrompter()
		let session = try asked(prompter: prompter, transcript: transcript, clock: clock)
		let before = clock.monotonic()
		_ = try handler.execute(session, poll(prompter.lastTicket, timeout: 600))
		#expect(clock.monotonic() - before <= maxPollTimeout + promptPollInterval)
		#expect(transcript.notes.contains { $0.contains("clamped") })
	}
}
