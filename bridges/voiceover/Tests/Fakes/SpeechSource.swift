// Hand-written stateful fake for the SpeechSource port; `emit` appends on the caller's thread.

import VoiceOverBridgeDomain

public final class FakeSpeechSource: SpeechSource {
	public private(set) var started: [SpeechBuffer] = []
	public private(set) var stopCount = 0
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

	public func emit(_ utterance: CapturedUtterance) {
		for buffer in started {
			buffer.append(utterance)
		}
	}

	public func emit(_ text: String, at emittedAt: Double = 0) {
		emit(CapturedUtterance(text: text, emittedAt: emittedAt))
	}
}
