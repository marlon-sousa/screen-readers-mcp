// A hand-written stateful fake for the SpeechSource port, mirroring
// Sources/VoiceOverBridgeDomain/Ports/SpeechSource.swift.
//
// IT DELIVERS SYNCHRONOUSLY, WHICH IS THE POINT. The real source feeds the
// buffer from a thread of its own; a test that wants to know what the buffer
// then answers should not have to wait for one. So `emit` appends on the
// caller's thread, and every timing question is asked of the FakeClock instead.
//
// It records start and stop because the lifecycle is what the session's own
// tests assert on: capture must be started by the handshake and stopped by every
// teardown path, including the ones where the handshake failed.

import VoiceOverBridgeDomain

public final class FakeSpeechSource: SpeechSource {
	public private(set) var started: [SpeechBuffer] = []
	public private(set) var stopCount = 0
	/// Run when `start` is called, so a test can observe the state of the world
	/// AT that moment -- which is how the handshake's ordering is asserted.
	public var onStart: (() -> Void)?

	public var isStarted: Bool { !started.isEmpty }

	public init() {}

	public func start(_ buffer: SpeechBuffer) {
		started.append(buffer)
		onStart?()
	}

	public func stop() {
		stopCount += 1
	}

	/// Capture an utterance into every buffer this source was started against.
	public func emit(_ utterance: CapturedUtterance) {
		for buffer in started {
			buffer.append(utterance)
		}
	}

	/// The common case: words, and an instant.
	public func emit(_ text: String, at emittedAt: Double = 0) {
		emit(CapturedUtterance(text: text, emittedAt: emittedAt))
	}
}
