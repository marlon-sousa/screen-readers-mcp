// Mirrors Sources/VoiceOverBridgeAdapters/AppKitUserPrompter.swift.
// No test here opens a real window: it needs an NSApplication, steals focus and is announced by a running screen reader.

import Fakes
import Testing
import VoiceOverBridgeDomain

@testable import VoiceOverBridgeAdapters

@Suite("AppKitUserPrompter")
struct AppKitUserPrompterTests {
	private func prompter(_ window: FakePromptWindow) -> AppKitUserPrompter {
		var minted = 0
		return AppKitUserPrompter(
			window: window,
			mintId: {
				minted += 1
				return "prompt-\(minted)"
			})
	}

	@Test("presenting puts the question up and answers with a ticket, at once")
	func presenting() throws {
		let window = FakePromptWindow()
		let ticket = try prompter(window).present("did the menu open?")
		#expect(ticket == "prompt-1")
		#expect(window.opened.map(\.prompt) == ["did the menu open?"])
		#expect(window.opened.map(\.id) == ["prompt-1"])
	}

	@Test("there is no reply until there is one, and then it WAITS to be collected")
	func theAnswerWaits() throws {
		let window = FakePromptWindow()
		let subject = prompter(window)
		let ticket = try subject.present("ready?")
		#expect(subject.reply(for: ticket) == nil)
		window.report(ticket, .answered("yes"))
		#expect(subject.reply(for: ticket) == .answered("yes"))
		#expect(subject.reply(for: ticket) == .answered("yes"))
	}

	@Test("THE FIRST OUTCOME WINS: a window that closes after an answer is still an answer")
	func firstOutcomeWins() throws {
		let window = FakePromptWindow()
		let subject = prompter(window)
		let ticket = try subject.present("ready?")
		window.report(ticket, .answered("yes"))
		window.report(ticket, .dismissed)
		#expect(subject.reply(for: ticket) == .answered("yes"))
	}

	@Test("cancelling takes the window away and forgets the answer")
	func cancelling() throws {
		let window = FakePromptWindow()
		let subject = prompter(window)
		let ticket = try subject.present("ready?")
		window.report(ticket, .answered("yes"))
		subject.cancel(ticket)
		#expect(window.closed == [ticket])
		#expect(subject.reply(for: ticket) == nil)
	}

	@Test("a cancelled prompt does not come back to life when its own window closes")
	func aCancelledPromptStaysGone() throws {
		let window = FakePromptWindow()
		let subject = prompter(window)
		let ticket = try subject.present("ready?")
		subject.cancel(ticket)
		window.report(ticket, .dismissed)
		#expect(subject.reply(for: ticket) == nil)
	}

	@Test("two questions are two tickets, and neither answer lands on the other")
	func ticketsAreDistinct() throws {
		let window = FakePromptWindow()
		let subject = prompter(window)
		let first = try subject.present("one")
		let second = try subject.present("two")
		window.report(second, .answered("second"))
		#expect(subject.reply(for: first) == nil)
		#expect(subject.reply(for: second) == .answered("second"))
	}

	@Test("cancelling something that was never opened is safe")
	func cancellingIsIdempotent() {
		let window = FakePromptWindow()
		let subject = prompter(window)
		subject.cancel("prompt-99")
		subject.cancel("prompt-99")
		#expect(window.closed == ["prompt-99", "prompt-99"])
	}
}
