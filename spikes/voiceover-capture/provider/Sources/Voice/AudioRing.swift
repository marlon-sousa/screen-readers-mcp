// SPIKE (spec 0041, probe C4/B3). A single-producer, single-consumer ring of
// float samples, sitting between the thread that re-synthesizes audio and the
// realtime thread that has to hand samples to the system on a deadline.
//
// The consumer uses os_unfair_lock_trylock and NEVER waits: if the producer holds
// the lock at that instant, the render block emits silence for that one block
// rather than blocking the audio thread. A dropout is a glitch; a blocked audio
// thread is a stall of everything the machine is saying.

import Foundation
import os

final class AudioRing {
	private let capacity: Int
	private let storage: UnsafeMutablePointer<Float>
	private let lock: UnsafeMutablePointer<os_unfair_lock>
	private var writeIndex = 0
	private var readIndex = 0
	private var producerFinished = false

	/// Counted so a dropout is reportable rather than merely audible.
	private(set) var contentionDrops = 0
	/// Render blocks that wanted samples, were not finished, and got fewer than
	/// asked. This is glitching, measured at its source.
	private(set) var underruns = 0
	/// Samples the producer could not fit -- the other way audio goes missing.
	private(set) var overflowDrops = 0

	init(capacity: Int) {
		self.capacity = capacity
		self.storage = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
		self.storage.initialize(repeating: 0, count: capacity)
		self.lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
		self.lock.initialize(to: os_unfair_lock())
	}

	deinit {
		storage.deallocate()
		lock.deallocate()
	}

	/// Producer side. Blocking is fine here -- this is not the audio thread -- but
	/// how LONG it blocks is not, because the consumer only ever tries the lock.
	/// A per-sample loop held it for thousands of iterations per buffer and cost
	/// 449 dropped render blocks in eight seconds of live VoiceOver speech, which
	/// is audible. Copy in at most two bulk runs instead.
	func append(_ samples: UnsafePointer<Float>, count: Int) {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		let free = (readIndex + capacity - writeIndex - 1) % capacity
		let usable = min(count, free)
		if usable < count { overflowDrops += count - usable }
		guard usable > 0 else { return }
		let firstRun = min(usable, capacity - writeIndex)
		storage.advanced(by: writeIndex).update(from: samples, count: firstRun)
		if usable > firstRun {
			storage.update(from: samples.advanced(by: firstRun), count: usable - firstRun)
		}
		writeIndex = (writeIndex + usable) % capacity
	}

	func resetCounters() {
		os_unfair_lock_lock(lock)
		contentionDrops = 0
		underruns = 0
		overflowDrops = 0
		os_unfair_lock_unlock(lock)
	}

	/// Samples queued and not yet rendered.
	var available: Int {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		return (writeIndex + capacity - readIndex) % capacity
	}

	var isFinished: Bool {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		return producerFinished
	}

	func markFinished() {
		os_unfair_lock_lock(lock)
		producerFinished = true
		os_unfair_lock_unlock(lock)
	}

	func reset() {
		os_unfair_lock_lock(lock)
		writeIndex = 0
		readIndex = 0
		producerFinished = false
		os_unfair_lock_unlock(lock)
	}

	/// Consumer side, called from the render block. Returns how many samples were
	/// filled and whether the utterance is over.
	func drain(into destination: UnsafeMutablePointer<Float>, count: Int) -> (filled: Int, done: Bool) {
		guard os_unfair_lock_trylock(lock) else {
			contentionDrops += 1
			return (0, false)
		}
		defer { os_unfair_lock_unlock(lock) }
		let available = (writeIndex + capacity - readIndex) % capacity
		let filled = min(count, available)
		if filled > 0 {
			let firstRun = min(filled, capacity - readIndex)
			destination.update(from: storage.advanced(by: readIndex), count: firstRun)
			if filled > firstRun {
				destination.advanced(by: firstRun).update(from: storage, count: filled - firstRun)
			}
			readIndex = (readIndex + filled) % capacity
		}
		let done = producerFinished && readIndex == writeIndex
		if filled < count && !done { underruns += 1 }
		return (filled, done)
	}
}
