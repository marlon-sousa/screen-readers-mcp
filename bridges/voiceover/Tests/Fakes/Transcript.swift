// Hand-written stateful fake for the Transcript port.

import VoiceOverBridgeDomain

public final class FakeTranscript: Transcript {
	public struct Opened: Equatable {
		public let mode: String
		public let voice: String
		public let persona: String
	}

	public var logPath: String
	public private(set) var isOpen = false
	public private(set) var opened: [Opened] = []
	public private(set) var speeches: [String] = []
	public private(set) var gestures: [String] = []
	public private(set) var typedLengths: [Int] = []
	public private(set) var announcements: [String] = []
	public private(set) var notes: [String] = []
	public private(set) var closedReasons: [String] = []

	public init(logPath: String = "/tmp/fake-session.log") {
		self.logPath = logPath
	}

	public func open() {
		isOpen = true
	}

	public func sessionOpened(mode: String, voice: String, persona: String) {
		opened.append(Opened(mode: mode, voice: voice, persona: persona))
	}

	public func speech(_ text: String) {
		speeches.append(text)
	}

	public func gesture(_ command: String) {
		gestures.append(command)
	}

	public func typed(_ length: Int) {
		typedLengths.append(length)
	}

	public func announced(_ text: String) {
		announcements.append(text)
	}

	public func note(_ text: String) {
		notes.append(text)
	}

	public func sessionClosed(reason: String) {
		closedReasons.append(reason)
		isOpen = false
	}
}
