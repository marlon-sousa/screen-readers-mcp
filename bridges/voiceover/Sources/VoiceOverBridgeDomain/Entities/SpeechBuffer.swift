// ROLE: entity -- the indexed capture of what the reader said.
// FED BY: the SpeechSource implementation, on the source's own thread.
// READ BY: the five speech handlers, on the session thread.
// The index is this array's position, never the extension's own sequence number, which restarts when the system relaunches the extension.
// Index 0 is an empty sentinel, so the first capture lands at 1 and `getLastSpeech` on an untouched session answers with an empty string.
// Every read clamps: a stale bookmark answers with the sentinel or an empty range, never an error.

import Foundation

public let speechPollInterval: Double = 0.03

/// There is no exact finished signal (silent mode produces no audio), so this waits for the buffer to stop growing.
public let speechFinishedSeconds: Double = 1.0

public final class SpeechBuffer {
	private let clock: any Clock
	/// Recursive because `waitFor` reads through `indexOf` while holding the lock.
	private let lock = NSRecursiveLock()

	/// Append-only and unbounded within a session.
	private var entries: [CapturedUtterance]

	/// Monotonic, so the elapsed-time heuristic survives a clock correction.
	private var lastAppendedAt: Double

	private var observer: ((String) -> Void)?

	public init(clock: any Clock) {
		self.clock = clock
		self.entries = [CapturedUtterance(text: "")]
		self.lastAppendedAt = clock.monotonic()
	}

	/// Fired outside the lock: the transcript writes to a file, and IO under the mutex would stall the capture thread.
	public func setObserver(_ observer: ((String) -> Void)?) {
		lock.lock()
		defer { lock.unlock() }
		self.observer = observer
	}

	/// Called from the speech source's thread.
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

	public func lastIndex() -> Int {
		lock.lock()
		defer { lock.unlock() }
		return entries.count - 1
	}

	public var isEmpty: Bool {
		lock.lock()
		defer { lock.unlock() }
		return entries.count <= 1
	}

	public func nextIndex() -> Int {
		lock.lock()
		defer { lock.unlock() }
		return entries.count
	}

	public func last() -> (utterance: CapturedUtterance, index: Int) {
		lock.lock()
		defer { lock.unlock() }
		return (entries[entries.count - 1], entries.count - 1)
	}

	public func entry(at index: Int) -> CapturedUtterance {
		lock.lock()
		defer { lock.unlock() }
		guard index >= 0, index < entries.count else { return entries[0] }
		return entries[index]
	}

	/// Returns the half-open range read, not the span returned: empty entries are skipped, so each carries its own index.
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

	/// An empty result means nothing had arrived by the deadline, not that nothing will; returns as soon as anything with words arrives.
	public func collectSince(_ index: Int, grace: Double) -> (
		entries: [(utterance: CapturedUtterance, index: Int)], fromIndex: Int, toIndex: Int
	) {
		_ = wait(timeout: grace) { !self.entriesSince(index).entries.isEmpty }
		return entriesSince(index)
	}

	/// `afterIndex` is inclusive: an exclusive reading drops the first utterance an action caused.
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

	/// On a miss the index is a fresh bookmark and the utterance is empty.
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

	public func waitToFinish(timeout: Double) -> Bool {
		wait(timeout: timeout) { self.hasFinished() }
	}

	private func hasFinished() -> Bool {
		lock.lock()
		defer { lock.unlock() }
		return (clock.monotonic() - lastAppendedAt) > speechFinishedSeconds
	}

	private func wait(timeout: Double, _ predicate: () -> Bool) -> Bool {
		let deadline = clock.monotonic() + max(0, timeout)
		while true {
			if predicate() { return true }
			if clock.monotonic() >= deadline { return false }
			clock.sleep(speechPollInterval)
		}
	}
}
