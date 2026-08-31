// Mirrors Sources/VoiceOverBridgeDomain/Entities/UserPrompt.swift.
//
// The entity holds no answer -- that lives in the prompter's table, because the
// window that collects it is AppKit's -- so what is left here is the WINDOW: a
// deadline, and whether asking cost this session its silence. Both are pure
// arithmetic on a clock reading, which is exactly the part that should not be
// inside a view.

import Testing

@testable import VoiceOverBridgeDomain

@Suite("UserPrompt")
struct UserPromptTests {
	@Test("a fresh prompt is open, and has its whole window left")
	func freshlyAsked() {
		let prompt = UserPrompt(ticket: "t", prompt: "ready?", now: 100)
		#expect(!prompt.isExpired(100))
		#expect(prompt.remaining(100) == UserPrompt.window)
	}

	@Test("the window closes on its own after 300 seconds -- protocol.md §5's number")
	func itExpires() {
		// An agent that stops polling must not leave a question on somebody's screen
		// for the rest of the session.
		let prompt = UserPrompt(ticket: "t", prompt: "ready?", now: 0)
		#expect(!prompt.isExpired(UserPrompt.window - 0.001))
		#expect(prompt.isExpired(UserPrompt.window))
		#expect(prompt.isExpired(UserPrompt.window + 60))
	}

	@Test("what is left is never negative, so a bounded poll cannot be asked to wait backwards")
	func remainingIsClamped() {
		let prompt = UserPrompt(ticket: "t", prompt: "ready?", now: 0)
		#expect(prompt.remaining(UserPrompt.window * 2) == 0)
	}

	@Test("whether asking cost the session its silence is RECORDED, not re-derived")
	func theSuspensionIsRemembered() {
		// A live session suspended nothing, so the command that closes the window
		// has to know what the command that opened it actually took.
		let prompt = UserPrompt(ticket: "t", prompt: "ready?", now: 0)
		#expect(!prompt.suspendedSilence)
		prompt.suspendedSilence = true
		#expect(prompt.suspendedSilence)
	}

	@Test("the lifetime is injectable, so a test never waits five real minutes")
	func theWindowIsInjectable() {
		let prompt = UserPrompt(ticket: "t", prompt: "ready?", now: 0, lifetime: 2)
		#expect(prompt.isExpired(2))
	}
}
