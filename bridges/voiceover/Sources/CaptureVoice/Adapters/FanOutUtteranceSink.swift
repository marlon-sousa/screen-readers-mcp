// ROLE: adapter that implements UtteranceSink by emitting to several others.
// BUILT BY: CaptureAudioUnit, over ContainerFileUtteranceSink and OsLogUtteranceSink.

public final class FanOutUtteranceSink: UtteranceSink {
	private let sinks: [UtteranceSink]

	public init(_ sinks: [UtteranceSink]) {
		self.sinks = sinks
	}

	public func emit(_ event: CaptureEvent) {
		for sink in sinks {
			sink.emit(event)
		}
	}
}
