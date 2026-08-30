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
	/// Every captured utterance the session recorded, in order. The buffer's
	/// observer is wired to this by `hello`, so an empty list after speech was
	/// captured means the wiring is missing, not the transcript.
	public private(set) var speeches: [String] = []
	/// Every command dispatched to the reader, in order -- recorded BEFORE it was
	/// sent, so a command that failed or hung is in this list too. That is the
	/// property a session test asserts on, and the reason the port records it
	/// first rather than on success.
	public private(set) var gestures: [String] = []
	/// Every typed LENGTH, in order -- never the text, because the port never
	/// receives it. A test asserting on this list is asserting the obligation
	/// protocol.md §5 puts on the transcript: the record says how much was typed
	/// and can never say what.
	public private(set) var typedLengths: [Int] = []
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

	public func note(_ text: String) {
		notes.append(text)
	}

	public func sessionClosed(reason: String) {
		closedReasons.append(reason)
		isOpen = false
	}
}
