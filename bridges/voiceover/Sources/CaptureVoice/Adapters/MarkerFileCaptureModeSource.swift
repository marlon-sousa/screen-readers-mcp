// ROLE: adapter -- implements CaptureModeSource by reading a marker file.
//
// The file is written and refreshed by the bridge (entry 13.6); this side only
// reads it, once per utterance, because a lift must take effect on the very next
// thing VoiceOver says.
//
// SILENCE IS OPT-IN AND THE ABSENCE OF THE MARKER IS THE SAFE ANSWER. On this
// route the provider IS the voice: unlike NVDA, where silent capture intercepts
// BEFORE the synthesizer and the user's own one stays loaded (spec 0008), here
// rendering silence leaves the machine's owner unable to hear their own computer.
// So the default -- and the answer when the question cannot be answered -- is
// "speak".
//
// SILENCE IS A LEASE, NOT A STATE. This is the load-bearing rule and it is why
// this file is no longer a bare `fileExists`.
//
// `protocol.md` section 6 asks a bridge to arrange its interception so that
// LOSING THE BRIDGE ITSELF lifts it. The NVDA bridge gets that free: NVDA holds
// extension-point handlers weakly, so killing the add-on drops the speech filter
// with it. macOS gives no equivalent. The marker is a file on disk and this
// extension is a separate process owned by the system, so it would go on reading
// that file forever -- and a teardown path that deletes it cannot run at SIGKILL,
// at a panic, or on a power cut, which are precisely the cases that matter.
//
// So the marker EXPIRES. The bridge refreshes it while a session lives; a marker
// older than the lease is treated as pass-through. A dead bridge therefore
// un-mutes the machine BY DOING NOTHING AT ALL -- no code has to survive the
// crash. The bridge's own `defer` still deletes it, because that is free and
// makes the ordinary case immediate, but nothing depends on that running.
//
// An unreadable modification date is also "speak", for the reason above: the
// question could not be answered, so the answer is the safe one.

import Foundation

public final class MarkerFileCaptureModeSource: CaptureModeSource {
	/// How stale a marker may be before it stops meaning silence.
	///
	/// Chosen so that a bridge refreshing on any ordinary cadence stays well
	/// inside it, while a dead one un-mutes the machine in a time a human would
	/// describe as "it came back" rather than "it was stuck". It is deliberately
	/// short: the cost of expiring early is that the user hears their computer,
	/// and the cost of expiring late is that they do not.
	public static let lease: TimeInterval = 30

	private let path: String
	private let lease: TimeInterval
	private let now: () -> Date

	/// `now` is injected so the expiry is testable without sleeping, which is the
	/// same reason the bridge's domain takes a Clock port.
	public init(
		path: String,
		lease: TimeInterval = MarkerFileCaptureModeSource.lease,
		now: @escaping () -> Date = Date.init
	) {
		self.path = path
		self.lease = lease
		self.now = now
	}

	public var isSilent: Bool {
		guard
			let attributes = try? FileManager.default.attributesOfItem(atPath: path),
			let modified = attributes[.modificationDate] as? Date
		else { return false }
		return now().timeIntervalSince(modified) <= lease
	}
}
