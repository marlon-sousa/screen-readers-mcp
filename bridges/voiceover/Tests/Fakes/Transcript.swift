// A hand-written stateful fake for the Transcript port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/Transcript.swift.
//
// It records the same lines FileTranscript would render, in the same order, so a
// session test can assert what the record SAYS without a filesystem -- and
// without duplicating the format, which is FileTranscript's own test's business.

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

	public func note(_ text: String) {
		notes.append(text)
	}

	public func sessionClosed(reason: String) {
		closedReasons.append(reason)
		isOpen = false
	}
}
