// ROLE: entity -- the indexed capture of what the reader said, and this bridge's
// central subject matter.
//
// FED BY: the SpeechSource port's implementation, on the source's own thread.
// READ BY: the five speech handlers, on the session thread.
// DEPENDS ON: the Clock port (injected), and nothing else. Pure in the sense
// that matters -- it does no IO -- while owning the one lock in this domain,
// because it is the one place two threads meet.
//
// THE BRIDGE NUMBERS UTTERANCES ITSELF, AND THAT IS THE WHOLE REASON THIS CLASS
// ASSIGNS INDICES. The capture extension stamps every line with a sequence
// number of its own, and it looks exactly as trustworthy as this one -- but the
// system relaunches that extension freely and the counter restarts when it does
// (measured, spec 0041 A4). A bridge that trusted those numbers would have its
// ordering reset mid-session with no signal at all: two utterances would share
// an index, a bookmark taken before an action would point after it, and
// `getSpeech { sinceIndex: n }` would answer with speech from before the mark.
// So the extension's counter is DISCARDED at the adapter and the position in
// this array is the index the agent sees.
//
// THE INDEX CONVENTION IS LANE 1'S, deliberately: one empty sentinel entry at
// index 0, so the first real capture lands at 1 and `getLastSpeech` on an
// untouched session answers with an empty string rather than an error.
// `nextIndex` is the index the next capture will occupy -- the bookmark an agent
// takes BEFORE acting, which is what makes an assertion race-free against
// speech that was already in flight.
//
// EVERY READ CLAMPS. A stale bookmark -- an index from before a reconnect, or
// one an agent invented -- answers with the sentinel or an empty range and never
// raises: the agent asked a legitimate question about a place that does not
// exist, and an error frame would tell it less than an empty answer does.

import Foundation

/// Poll cadence for the wait loops. Small enough to feel instant, large enough
/// not to spin. A FakeClock makes `sleep` an instant advance, so a test that
/// exercises these loops never actually pauses.
public let speechPollInterval: Double = 0.03

/// How long the buffer must stay quiet before speech counts as finished.
///
/// THERE IS NO EXACT "FINISHED" SIGNAL ON THIS ROUTE, and there cannot be: the
/// capture voice is handed an utterance BEFORE any audio exists, and in silent
/// mode no audio is ever produced, so the only observable is that nothing new
/// has arrived for a while. The wire type's own header says the same: this waits
/// for the buffer to stop growing, not for the machine to fall silent.
///
/// One second, which is lane 1's number for the same heuristic. Lane 1 measured
/// that the constant is rarely paid at all -- a reader finishes producing a
/// keystroke's speech far faster than an agent's round trip arrives -- and there
/// is no reason to expect a different answer here. What has NOT been measured on
/// this route is the feed's own tail latency (spec 0046, open question 3), which
/// is the one thing that could make a shorter window wrong.
public let speechFinishedSeconds: Double = 1.0

public final class SpeechBuffer {
	private let clock: any Clock
	/// Recursive because a public method that already holds the lock calls
	/// another one that takes it -- `waitFor` reads through `indexOf` -- and two
	/// lock types for one invariant is how a deadlock gets introduced later.
	private let lock = NSRecursiveLock()

	/// Append-only and unbounded within a session (protocol.md §7): nothing ages
	/// out while the session lives, so `getSpeech { sinceIndex: 0 }` still
	/// answers with everything at the end of a long run.
	private var entries: [CapturedUtterance]

	/// MONOTONIC, and it must stay that way: this drives the elapsed-time
	/// heuristic, which has to survive a clock correction. The wall-clock stamp
	/// an agent reads back is a different number for a different job, and it
	/// rides on the entry itself (spec 0028).
	private var lastAppendedAt: Double

	private var observer: ((String) -> Void)?

	public init(clock: any Clock) {
		self.clock = clock
		self.entries = [CapturedUtterance(text: "")]
		self.lastAppendedAt = clock.monotonic()
	}

	// -- writing -------------------------------------------------------------

	/// Register a callback fired for each appended utterance that has words.
	///
	/// The Session's handshake wires this to the Transcript port, so captured
	/// speech is recorded bridge-side even when the agent never fetches it --
	/// which is the only record a run leaves if it crashed before reading.
	/// Fired OUTSIDE the lock: the transcript writes to a file, and holding a
	/// mutex across an IO call would stall the reader's own capture thread.
	public func setObserver(_ observer: ((String) -> Void)?) {
		lock.lock()
		defer { lock.unlock() }
		self.observer = observer
	}

	/// Record one captured utterance. Called from the speech source's thread.
	public func append(_ utterance: CapturedUtterance) {
		let notify: ((String) -> Void)?
		lock.lock()
		entries.append(utterance)
		lastAppendedAt = clock.monotonic()
		notify = observer
		lock.unlock()
		if !utterance.text.isEmpty {
			notify?(utterance.text)
		}
	}

	// -- reading -------------------------------------------------------------

	/// Index of the most recent entry; 0 when only the sentinel is present.
	public func lastIndex() -> Int {
		lock.lock()
		defer { lock.unlock() }
		return entries.count - 1
	}

	/// The index the next capture will occupy: the agent's bookmark.
	public func nextIndex() -> Int {
		lock.lock()
		defer { lock.unlock() }
		return entries.count
	}

	/// The most recent entry and the index it sits at.
	public func last() -> (utterance: CapturedUtterance, index: Int) {
		lock.lock()
		defer { lock.unlock() }
		return (entries[entries.count - 1], entries.count - 1)
	}

	/// The entry at `index`, or the sentinel when the index is out of range.
	public func entry(at index: Int) -> CapturedUtterance {
		lock.lock()
		defer { lock.unlock() }
		guard index >= 0, index < entries.count else { return entries[0] }
		return entries[index]
	}

	/// Everything with words from `index` to now, each carrying its own index.
	///
	/// Returns the half-open range `[fromIndex, toIndex)` that was READ, not the
	/// span of what came back: an entry that renders empty is skipped, so the
	/// caller cannot recover an entry's index by counting from `fromIndex`, which
	/// is exactly why each entry carries its own. The next call passes `toIndex`
	/// as its `sinceIndex` and nothing is read twice or skipped.
	public func entriesSince(_ index: Int) -> (
		entries: [(utterance: CapturedUtterance, index: Int)], fromIndex: Int, toIndex: Int
	) {
		lock.lock()
		defer { lock.unlock() }
		let from = max(0, index)
		let to = entries.count
		var found: [(utterance: CapturedUtterance, index: Int)] = []
		for position in from..<max(from, to) where !entries[position].text.isEmpty {
			found.append((entries[position], position))
		}
		return (found, from, to)
	}

	/// The first index at or after `afterIndex` whose text contains `text`.
	///
	/// `afterIndex` IS AN INCLUSIVE LEFT EDGE, matching every other range in this
	/// protocol and what `waitForSpeech` promises ("at or after this index").
	/// Lane 1 shipped the exclusive reading, borrowed from a library whose
	/// conventions are not ours, and it silently discarded the FIRST utterance an
	/// action caused -- the one the bookmark-act-wait pattern is always waiting
	/// for -- failing as a timeout that read like "the reader never said it"
	/// (spec 0037). Written this way here rather than re-learned.
	///
	/// `nil` means no constraint. A negative index is clamped, so a stale
	/// bookmark never slices from the end of the array.
	public func indexOf(_ text: String, afterIndex: Int? = nil) -> Int? {
		lock.lock()
		defer { lock.unlock() }
		let first = max(0, afterIndex ?? 0)
		guard first < entries.count else { return nil }
		for position in first..<entries.count where entries[position].text.contains(text) {
			return position
		}
		return nil
	}

	// -- waiting -------------------------------------------------------------

	/// Block until `text` is captured at or after `afterIndex`, or `timeout`.
	///
	/// On a miss the index is a FRESH BOOKMARK -- what `nextIndex` says now --
	/// so a caller that timed out can still resume from a usable mark, and the
	/// utterance is empty because nothing matched. `found == false` is a normal
	/// answer: "the reader did not say it" is frequently what a test asserts.
	public func waitFor(_ text: String, afterIndex: Int?, timeout: Double) -> (
		found: Bool, index: Int, utterance: CapturedUtterance
	) {
		var hit: Int?
		let seen = wait(timeout: timeout) {
			hit = self.indexOf(text, afterIndex: afterIndex)
			return hit != nil
		}
		if seen, let hit {
			return (true, hit, entry(at: hit))
		}
		return (false, nextIndex(), CapturedUtterance(text: ""))
	}

	/// Block until nothing has been captured for `speechFinishedSeconds`, or
	/// until `timeout` elapses. Returns whether it settled.
	public func waitToFinish(timeout: Double) -> Bool {
		wait(timeout: timeout) { self.hasFinished() }
	}

	private func hasFinished() -> Bool {
		lock.lock()
		defer { lock.unlock() }
		return (clock.monotonic() - lastAppendedAt) > speechFinishedSeconds
	}

	/// Poll `predicate` until it holds or `timeout` seconds elapse.
	///
	/// Checked once IMMEDIATELY, so a zero timeout still evaluates the current
	/// state, then the clock is slept between polls -- injected, so a five-second
	/// wait costs microseconds in a test.
	private func wait(timeout: Double, _ predicate: () -> Bool) -> Bool {
		let deadline = clock.monotonic() + max(0, timeout)
		while true {
			if predicate() { return true }
			if clock.monotonic() >= deadline { return false }
			clock.sleep(speechPollInterval)
		}
	}
}
