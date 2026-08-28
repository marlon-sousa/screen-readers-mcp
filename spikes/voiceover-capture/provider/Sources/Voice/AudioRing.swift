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

	/// Producer side. Blocking is fine here -- this is not the audio thread.
	func append(_ samples: UnsafePointer<Float>, count: Int) {
		os_unfair_lock_lock(lock)
		defer { os_unfair_lock_unlock(lock) }
		for index in 0..<count {
			let next = (writeIndex + 1) % capacity
			if next == readIndex { break }  // full: drop the tail rather than overwrite unread audio
			storage[writeIndex] = samples[index]
			writeIndex = next
		}
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
		var filled = 0
		while filled < count && readIndex != writeIndex {
			destination[filled] = storage[readIndex]
			readIndex = (readIndex + 1) % capacity
			filled += 1
		}
		return (filled, producerFinished && readIndex == writeIndex)
	}
}
