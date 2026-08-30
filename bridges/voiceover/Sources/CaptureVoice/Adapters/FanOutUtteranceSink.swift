// ROLE: adapter -- implements UtteranceSink by emitting to several others.
//
// The spike emitted two ways ON PURPOSE, and this is what makes that a
// composition rather than an `if` inside the one place that emits. Built by
// CaptureAudioUnit over ContainerFileUtteranceSink and OsLogUtteranceSink; the
// controller holds it and cannot tell.
//
// It is the reason "which routes exist" is a wiring decision: entry 13.6 can add
// a third without touching the controller, and a route that fails cannot stop
// the others, since each sink already reports its own failures rather than
// throwing.

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
